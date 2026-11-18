import type { DatabaseSync } from "node:sqlite";

export const FLOW_FLOWS_DDL = `CREATE TABLE IF NOT EXISTS flows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  position INTEGER NOT NULL,
  graph TEXT NOT NULL DEFAULT '{"nodes":[],"edges":[]}'
)`;

/** A database from the version that had projects and sections is flattened once: flows keep their ids and graphs, in project, section, flow order;
 *  a repeated name gets its section in brackets. */
export function flattenFlows(db: DatabaseSync): void {
  const columns = (db.prepare("PRAGMA table_info(flows)").all() as { name: string }[]).map((c) => c.name);
  if (!columns.includes("section_id")) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    const old = db.prepare(`SELECT f.id, f.name, COALESCE(s.name, '') AS section, f.graph FROM flows f
      LEFT JOIN flow_sections s ON s.id = f.section_id LEFT JOIN flow_projects p ON p.id = s.project_id
      ORDER BY p.position, s.position, f.position, f.id`).all() as { id: number; name: string; section: string; graph: string }[];
    db.exec(FLOW_FLOWS_DDL.replace("EXISTS flows (", "EXISTS flows_flat ("));
    const used = new Set<string>();
    old.forEach((flow, index) => {
      let name = flow.name;
      if (used.has(name)) name = `${flow.name} (${flow.section})`;
      for (let n = 2; used.has(name); n++) name = `${flow.name} (${flow.section}) ${n}`;
      used.add(name);
      db.prepare("INSERT INTO flows_flat (id, name, position, graph) VALUES (?, ?, ?, ?)").run(flow.id, name, index, flow.graph);
    });
    db.exec("DROP TABLE flows");
    db.exec("DROP TABLE IF EXISTS flow_sections");
    db.exec("DROP TABLE IF EXISTS flow_projects");
    db.exec("ALTER TABLE flows_flat RENAME TO flows");
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

/** The node components the Flows page draws; React Flow's own input, output and default are restyled to match. */
export const FLOW_NODE_TYPES = ["input", "output", "default", "decision", "service", "database", "queue", "api", "actor", "external", "note", "group"];
/** Colour names a node or connector may use in data.color. */
export const FLOW_COLORS = ["blue", "green", "amber", "red", "purple", "gray"];
export const FLOW_EDGE_TYPES = ["default", "straight", "step", "smoothstep", "simplebezier"];

type Json = Record<string, unknown>;
export type Point = { x: number; y: number };
export type FlowInput = { name: string; nodes: Json[]; edges: Json[] };
export type FlowRow = { id: number; name: string; graph: { nodes: Json[]; edges: Json[] } };

const isPoint = (p: unknown): p is Point =>
  typeof p === "object" && p !== null && Number.isFinite((p as Point).x) && Number.isFinite((p as Point).y) && typeof (p as Point).x === "number" && typeof (p as Point).y === "number";

function clean(value: string, what: string): string {
  const trimmed = (value ?? "").trim();
  if (!trimmed) throw new Error(`The ${what} name must not be empty`);
  return trimmed;
}

/** Position of the nth node without one: four columns, row by row. */
function gridSlot(index: number): Point {
  return { x: (index % 4) * 240, y: Math.floor(index / 4) * 120 };
}

function checkColor(color: unknown, who: string): void {
  if (color !== undefined && !FLOW_COLORS.includes(String(color))) throw new Error(`${who} has colour "${color}". Use one of: ${FLOW_COLORS.join(", ")}`);
}

function buildGraph(input: FlowInput, stored: Map<string, Point>): { nodes: Json[]; edges: Json[] } {
  const ids = new Set<string>();
  const nodes = input.nodes.map((node, index) => {
    if (typeof node.id !== "string" || node.id === "") throw new Error(`Node ${index + 1} needs an id`);
    if (ids.has(node.id)) throw new Error(`Flow has a duplicate node id "${node.id}"`);
    ids.add(node.id);
    if (node.type !== undefined && !FLOW_NODE_TYPES.includes(String(node.type))) throw new Error(`Node "${node.id}" has unknown type "${node.type}". Use one of: ${FLOW_NODE_TYPES.join(", ")}`);
    checkColor((node.data as Json | undefined)?.color, `Node "${node.id}"`);
    if (node.parentId !== undefined && !ids.has(String(node.parentId)) ) throw new Error(`Node "${node.id}" has parent "${node.parentId}", which must be a node listed before it`);
    if (node.position !== undefined && !isPoint(node.position)) throw new Error(`Node "${node.id}" position must be {x, y} numbers`);
    return { ...node, position: (node.position as Point | undefined) ?? stored.get(node.id) ?? gridSlot(index) };
  });
  const edges = input.edges.map((edge) => {
    const source = String(edge.source);
    const target = String(edge.target);
    checkColor((edge.data as Json | undefined)?.color, `Edge ${source} to ${target}`);
    if (edge.type !== undefined && !FLOW_EDGE_TYPES.includes(String(edge.type))) throw new Error(`Edge ${source} to ${target} has edge type "${edge.type}". Use one of: ${FLOW_EDGE_TYPES.join(", ")}`);
    for (const end of [source, target]) if (!ids.has(end)) throw new Error(`Edge ${source} to ${target} points at unknown node "${end}"`);
    return { ...edge, id: typeof edge.id === "string" && edge.id ? edge.id : `${source}-${target}` };
  });
  return { nodes, edges };
}

function nextPosition(db: DatabaseSync): number {
  return (db.prepare("SELECT COALESCE(MAX(position), -1) + 1 AS n FROM flows").get() as { n: number }).n;
}

export function upsertFlow(db: DatabaseSync, input: FlowInput): { action: "created" | "updated"; id: number } {
  const name = clean(input.name, "flow");
  db.exec("BEGIN IMMEDIATE");
  try {
    const existing = db.prepare("SELECT id, graph FROM flows WHERE name = ?").get(name) as { id: number; graph: string } | undefined;
    const stored = new Map<string, Point>();
    if (existing) for (const node of (JSON.parse(existing.graph).nodes ?? []) as Json[]) if (typeof node.id === "string" && isPoint(node.position)) stored.set(node.id, node.position);
    const graph = JSON.stringify(buildGraph(input, stored));
    let result: { action: "created" | "updated"; id: number };
    if (existing) {
      db.prepare("UPDATE flows SET graph = ? WHERE id = ?").run(graph, existing.id);
      result = { action: "updated", id: existing.id };
    } else {
      const id = Number(db.prepare("INSERT INTO flows (name, position, graph) VALUES (?, ?, ?)").run(name, nextPosition(db), graph).lastInsertRowid);
      result = { action: "created", id };
    }
    db.exec("COMMIT");
    return result;
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

export function listFlows(db: DatabaseSync): { id: number; name: string }[] {
  return (db.prepare("SELECT id, name FROM flows ORDER BY position, id").all() as { id: number; name: string }[]).map((f) => ({ id: f.id, name: f.name }));
}

export function getFlow(db: DatabaseSync, key: { id?: number; name?: string }): FlowRow | undefined {
  const row = (key.id !== undefined ? db.prepare("SELECT id, name, graph FROM flows WHERE id = ?").get(key.id) : db.prepare("SELECT id, name, graph FROM flows WHERE name = ?").get(key.name ?? "")) as
    | { id: number; name: string; graph: string }
    | undefined;
  return row && { id: row.id, name: row.name, graph: JSON.parse(row.graph) };
}

export function deleteFlow(db: DatabaseSync, key: { id?: number; name?: string }): { deleted: boolean; name: string } {
  const flow = getFlow(db, key);
  if (!flow) return { deleted: false, name: key.name ?? String(key.id ?? "") };
  db.prepare("DELETE FROM flows WHERE id = ?").run(flow.id);
  return { deleted: true, name: flow.name };
}
