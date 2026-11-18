import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { openDb } from "../src/slackdb.ts";
import { FLOW_COLORS, FLOW_FLOWS_DDL, FLOW_NODE_TYPES, deleteFlow, getFlow, listFlows, upsertFlow } from "../src/flows.ts";

async function fresh(): Promise<DatabaseSync> {
  return openDb(join(await mkdtemp(join(tmpdir(), "flows-")), "t.db"));
}

const NODES = [
  { id: "a", data: { label: "Start" } },
  { id: "b", data: { label: "Pay" }, position: { x: 50, y: 60 } },
];
const EDGES = [{ source: "a", target: "b" }];
const BASE = { name: "Happy path", nodes: NODES, edges: EDGES };

test("creates a flow by name", async () => {
  const db = await fresh();
  const r = upsertFlow(db, BASE);
  assert.equal(r.action, "created");
  assert.deepEqual(listFlows(db), [{ id: r.id, name: "Happy path" }]);
});

test("flows are listed in the order they were created", async () => {
  const db = await fresh();
  upsertFlow(db, BASE);
  upsertFlow(db, { ...BASE, name: "Failure" });
  upsertFlow(db, { ...BASE, name: "Top up" });
  assert.deepEqual(listFlows(db).map((f) => f.name), ["Happy path", "Failure", "Top up"]);
});

test("nodes without a position get a grid slot; given positions are kept", async () => {
  const db = await fresh();
  const { id } = upsertFlow(db, BASE);
  const flow = getFlow(db, { id })!;
  const [a, b] = flow.graph.nodes as { id: string; position: { x: number; y: number } }[];
  assert.ok(Number.isFinite(a.position.x) && Number.isFinite(a.position.y));
  assert.deepEqual(b.position, { x: 50, y: 60 });
});

test("edges get an id from source and target", async () => {
  const db = await fresh();
  const { id } = upsertFlow(db, BASE);
  assert.deepEqual((getFlow(db, { id })!.graph.edges as { id: string }[]).map((e) => e.id), ["a-b"]);
});

test("upserting again replaces the graph but keeps the position a user dragged a node to", async () => {
  const db = await fresh();
  const first = upsertFlow(db, BASE);
  const stored = getFlow(db, { id: first.id })!.graph as { nodes: Record<string, unknown>[] };
  stored.nodes[0].position = { x: 999, y: 888 };
  db.prepare("UPDATE flows SET graph = ? WHERE id = ?").run(JSON.stringify(stored), first.id);
  const again = upsertFlow(db, { ...BASE, nodes: [{ id: "a", data: { label: "Start v2" } }, { id: "c", data: { label: "New" } }], edges: [{ source: "a", target: "c" }] });
  assert.equal(again.action, "updated");
  assert.equal(again.id, first.id);
  const nodes = getFlow(db, { id: first.id })!.graph.nodes as { id: string; data: { label: string }; position: { x: number; y: number } }[];
  assert.deepEqual(nodes.map((n) => n.id), ["a", "c"]);
  assert.equal(nodes[0].data.label, "Start v2");
  assert.deepEqual(nodes[0].position, { x: 999, y: 888 });
});

test("an edge to an unknown node is rejected and nothing is written", async () => {
  const db = await fresh();
  assert.throws(() => upsertFlow(db, { ...BASE, edges: [{ source: "a", target: "zzz" }] }), /unknown node "zzz"/);
  assert.deepEqual(listFlows(db), []);
});

test("duplicate node ids, a blank name and a node without an id are rejected", async () => {
  const db = await fresh();
  assert.throws(() => upsertFlow(db, { ...BASE, nodes: [{ id: "a" }, { id: "a" }], edges: [] }), /duplicate node id "a"/);
  assert.throws(() => upsertFlow(db, { ...BASE, nodes: [{ data: {} } as never], edges: [] }), /needs an id/);
  assert.throws(() => upsertFlow(db, { ...BASE, name: "  " }), /name/);
});

test("a position that is not two numbers is rejected", async () => {
  const db = await fresh();
  assert.throws(() => upsertFlow(db, { ...BASE, nodes: [{ id: "a", position: { x: "1", y: 2 } }], edges: [] }), /position/);
});

test("getFlow finds a flow by id or by name and returns undefined when missing", async () => {
  const db = await fresh();
  const { id } = upsertFlow(db, BASE);
  assert.equal(getFlow(db, { id })!.name, "Happy path");
  assert.equal(getFlow(db, { name: "Happy path" })!.id, id);
  assert.equal(getFlow(db, { id: 999 }), undefined);
  assert.equal(getFlow(db, { name: "Nope" }), undefined);
});

test("Swift and TypeScript flow DDL are identical", async () => {
  const swift = await readFile(join(import.meta.dirname, "..", "..", "Sources", "StudioCore", "FlowStore.swift"), "utf8");
  const match = /static let flowsDDL = """\n([\s\S]*?)"""/.exec(swift);
  assert.ok(match, "FlowStore.swift must define static let flowsDDL");
  assert.equal(match[1].replace(/\s+/g, " ").trim(), FLOW_FLOWS_DDL.replace(/\s+/g, " ").trim());
});

test("openDb creates only the flows table", async () => {
  const db = await fresh();
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all() as { name: string }[]).map((r) => r.name);
  assert.ok(names.includes("flows"));
  assert.ok(!names.includes("flow_projects") && !names.includes("flow_sections"));
});

test("a database with projects and sections is flattened keeping ids, graphs and order; repeated names get the section", async () => {
  const file = join(await mkdtemp(join(tmpdir(), "flows-old-")), "t.db");
  const old = new DatabaseSync(file);
  old.exec(`
    CREATE TABLE flow_projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, position INTEGER NOT NULL);
    CREATE TABLE flow_sections (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL, UNIQUE (project_id, name));
    CREATE TABLE flows (id INTEGER PRIMARY KEY AUTOINCREMENT, section_id INTEGER NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL, graph TEXT NOT NULL DEFAULT '{"nodes":[],"edges":[]}', UNIQUE (section_id, name));
    INSERT INTO flow_projects VALUES (1, 'Payments', 0), (2, 'Lending', 1);
    INSERT INTO flow_sections VALUES (1, 1, 'Refund', 0), (2, 1, 'Top up', 1), (3, 2, 'Disbursal', 0);
    INSERT INTO flows VALUES (10, 1, 'Main', 0, '{"nodes":[{"id":"a"}],"edges":[]}'), (11, 2, 'Main', 0, '{"nodes":[],"edges":[]}'), (12, 3, 'Other', 0, '{"nodes":[],"edges":[]}'), (13, 1, 'Failure', 1, '{"nodes":[],"edges":[]}');
  `);
  old.close();
  const db = openDb(file);
  assert.deepEqual(listFlows(db), [{ id: 10, name: "Main" }, { id: 13, name: "Failure" }, { id: 11, name: "Main (Top up)" }, { id: 12, name: "Other" }]);
  assert.equal((getFlow(db, { id: 10 })!.graph.nodes as unknown[]).length, 1);
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all() as { name: string }[]).map((r) => r.name);
  assert.ok(!names.includes("flow_projects") && !names.includes("flow_sections"));
  openDb(file).close();
});

test("deleteFlow removes a flow by id or by name and says what it removed", async () => {
  const db = await fresh();
  const a = upsertFlow(db, BASE);
  upsertFlow(db, { ...BASE, name: "Failure" });
  upsertFlow(db, { ...BASE, name: "Top up" });
  assert.deepEqual(deleteFlow(db, { id: a.id }), { deleted: true, name: "Happy path" });
  assert.deepEqual(deleteFlow(db, { name: "Failure" }), { deleted: true, name: "Failure" });
  assert.deepEqual(listFlows(db).map((f) => f.name), ["Top up"]);
});

test("deleteFlow on a missing flow deletes nothing and reports it", async () => {
  const db = await fresh();
  upsertFlow(db, BASE);
  assert.deepEqual(deleteFlow(db, { name: "Nope" }), { deleted: false, name: "Nope" });
  assert.equal(listFlows(db).length, 1);
});

test("node and connector colours must be one of the named colours", async () => {
  const db = await fresh();
  for (const color of FLOW_COLORS) upsertFlow(db, { ...BASE, nodes: [{ id: "a", data: { label: "A", color } }], edges: [] });
  assert.throws(() => upsertFlow(db, { ...BASE, nodes: [{ id: "a", data: { color: "pink" } }], edges: [] }), /colour "pink".*blue/);
  assert.throws(() => upsertFlow(db, { ...BASE, edges: [{ source: "a", target: "b", data: { color: "pink" } }] }), /colour "pink"/);
  const { id } = upsertFlow(db, { ...BASE, edges: [{ source: "a", target: "b", data: { color: "red", dashed: true, arrow: false } }] });
  assert.deepEqual((getFlow(db, { id })!.graph.edges as { data: unknown }[])[0].data, { color: "red", dashed: true, arrow: false });
});
