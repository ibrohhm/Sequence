import { test } from "node:test";
import assert from "node:assert/strict";
import { copySelection, parseClipboard, pasteSelection, serializeClipboard } from "../src/clipboard.js";

const node = (id, extra = {}) => ({ id, position: { x: 0, y: 0 }, data: { label: id }, ...extra });
let counter = 0;
const nextId = (prefix) => `${prefix}${++counter}`;

test("copy takes the selected nodes and only the edges between them", () => {
  const nodes = [node("a", { selected: true }), node("b", { selected: true }), node("c")];
  const edges = [{ id: "ab", source: "a", target: "b" }, { id: "bc", source: "b", target: "c" }];
  const copied = copySelection(nodes, edges);
  assert.deepEqual(copied.nodes.map((n) => n.id), ["a", "b"]);
  assert.deepEqual(copied.edges.map((e) => e.id), ["ab"]);
});

test("copy of nothing selected is null", () => {
  assert.equal(copySelection([node("a")], []), null);
});

test("copy strips runtime keys and selection", () => {
  const copied = copySelection([node("a", { selected: true, dragging: true, measured: { width: 1 }, width: 5, height: 6 })], []);
  assert.deepEqual(Object.keys(copied.nodes[0]).sort(), ["data", "id", "position"]);
});

test("copying a group brings its children along", () => {
  const nodes = [node("g", { type: "group", selected: true }), node("k", { parentId: "g", position: { x: 5, y: 6 } }), node("x")];
  const copied = copySelection(nodes, []);
  assert.deepEqual(copied.nodes.map((n) => n.id), ["g", "k"]);
});

test("a child copied without its group is detached at its absolute position", () => {
  const nodes = [node("g", { type: "group", position: { x: 100, y: 200 } }), node("k", { parentId: "g", position: { x: 5, y: 6 }, selected: true })];
  const [only] = copySelection(nodes, []).nodes;
  assert.equal(only.parentId, undefined);
  assert.deepEqual(only.position, { x: 105, y: 206 });
});

test("paste gives new ids, remaps edges and parents, and offsets top-level nodes only", () => {
  const payload = {
    nodes: [node("g", { type: "group", position: { x: 10, y: 10 } }), node("k", { parentId: "g", position: { x: 5, y: 6 } }), node("m", { position: { x: 50, y: 50 } })],
    edges: [{ id: "km", source: "k", target: "m", label: "x" }],
  };
  const out = pasteSelection(payload, nextId, { x: 30, y: 30 });
  const ids = out.nodes.map((n) => n.id);
  assert.equal(new Set(ids).size, 3);
  assert.ok(!ids.includes("g") && !ids.includes("k") && !ids.includes("m"));
  const [g, k, m] = out.nodes;
  assert.deepEqual(g.position, { x: 40, y: 40 });
  assert.equal(k.parentId, g.id);
  assert.deepEqual(k.position, { x: 5, y: 6 });
  assert.deepEqual(m.position, { x: 80, y: 80 });
  assert.equal(out.edges[0].source, k.id);
  assert.equal(out.edges[0].target, m.id);
  assert.notEqual(out.edges[0].id, "km");
  assert.equal(out.edges[0].label, "x");
});

test("paste leaves the clipboard payload untouched so it can be pasted again", () => {
  const payload = { nodes: [node("a")], edges: [] };
  const before = JSON.stringify(payload);
  pasteSelection(payload, nextId, { x: 30, y: 30 });
  assert.equal(JSON.stringify(payload), before);
});

test("clipboard text round-trips and ignores ordinary text", () => {
  const payload = { nodes: [node("a")], edges: [] };
  assert.deepEqual(parseClipboard(serializeClipboard(payload)), payload);
  assert.equal(parseClipboard("hello"), null);
  assert.equal(parseClipboard('{"nodes":[]}'), null);
  assert.equal(parseClipboard(""), null);
});
