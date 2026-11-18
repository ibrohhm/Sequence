const RUNTIME_KEYS = ["measured", "selected", "dragging", "resizing", "positionAbsolute", "width", "height"];
const MARK = "sequenceFlowClipboard";

const clean = (node) => {
  const copy = { ...node };
  for (const key of RUNTIME_KEYS) delete copy[key];
  return copy;
};

function absolute(node, byId) {
  const parent = node.parentId ? byId.get(node.parentId) : null;
  if (!parent) return { ...node.position };
  const base = absolute(parent, byId);
  return { x: base.x + node.position.x, y: base.y + node.position.y };
}

/** The selected nodes (with the children of selected groups) and the edges between them, or null when nothing is selected. */
export function copySelection(nodes, edges) {
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const picked = new Set(nodes.filter((n) => n.selected).map((n) => n.id));
  if (!picked.size) return null;
  let grew = true;
  while (grew) {
    grew = false;
    for (const n of nodes) {
      if (n.parentId && picked.has(n.parentId) && !picked.has(n.id)) {
        picked.add(n.id);
        grew = true;
      }
    }
  }
  const copied = nodes
    .filter((n) => picked.has(n.id))
    .map((n) => {
      const out = clean(n);
      if (n.parentId && !picked.has(n.parentId)) {
        delete out.parentId;
        delete out.extent;
        out.position = absolute(n, byId);
      }
      return out;
    });
  return { nodes: copied, edges: edges.filter((e) => picked.has(e.source) && picked.has(e.target)).map(({ selected, ...e }) => e) };
}

/** Copies of a payload with new ids; top-level nodes move by `offset`, children keep their place in their group. */
export function pasteSelection(payload, newId, offset) {
  const ids = new Map(payload.nodes.map((n) => [n.id, newId("n")]));
  const nodes = payload.nodes.map((n) => {
    const out = structuredClone(n);
    out.id = ids.get(n.id);
    if (n.parentId && ids.has(n.parentId)) out.parentId = ids.get(n.parentId);
    else out.position = { x: n.position.x + offset.x, y: n.position.y + offset.y };
    return out;
  });
  const edges = payload.edges.map((e) => ({ ...structuredClone(e), id: newId("e"), source: ids.get(e.source), target: ids.get(e.target) }));
  return { nodes, edges };
}

export const serializeClipboard = (payload) => JSON.stringify({ [MARK]: 1, ...payload });

export function parseClipboard(text) {
  try {
    const data = JSON.parse(text);
    if (data?.[MARK] === 1 && Array.isArray(data.nodes) && Array.isArray(data.edges)) return { nodes: data.nodes, edges: data.edges };
  } catch {
    /* ordinary text */
  }
  return null;
}
