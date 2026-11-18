import React, { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { addEdge, Background, BaseEdge, ControlButton, Controls, EdgeLabelRenderer, getBezierPath, getSimpleBezierPath, getSmoothStepPath, getStraightPath, Handle, MarkerType, NodeResizer, Position, ReactFlow, ReactFlowProvider, SelectionMode, useEdgesState, useNodesState, useReactFlow } from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import "./flow.css";
import { copySelection, parseClipboard, pasteSelection, serializeClipboard } from "./clipboard.js";
import { createHistory } from "./history.js";

const post = (message) => window.webkit?.messageHandlers?.flow?.postMessage(message);

const STATUS = { todo: "todo", "in progress": "progress", inprogress: "progress", blocked: "blocked", done: "done" };

/** Named colours: nodes tint through CSS variables per theme (flow.css); connectors use the line colour directly. */
const COLORS = {
  blue: "#4c7fd6",
  green: "#36b37e",
  amber: "#d99a00",
  red: "#de350b",
  purple: "#8a63d2",
  gray: "#7a7f87",
};
const tint = (data) => (data?.color ? { "data-color": data.color } : {});

const withClass = (current, name) => (current?.split(" ").includes(name) ? current : [current, name].filter(Boolean).join(" "));

/** Drag handles on a selected node; the size is kept in the node's style so it is saved with the graph. */
function Resizer({ id, selected, minWidth = 60, minHeight = 30 }) {
  const { updateNode } = useReactFlow();
  return (
    <NodeResizer
      isVisible={!!selected}
      minWidth={minWidth}
      minHeight={minHeight}
      onResizeEnd={(_event, p) =>
        updateNode(id, (n) => ({ ...n, position: { x: p.x, y: p.y }, style: { ...n.style, width: p.width, height: p.height }, className: withClass(n.className, "sized") }))
      }
    />
  );
}

const Icon = ({ children }) => (
  <svg className="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {children}
  </svg>
);
const ICONS = {
  service: (
    <Icon>
      <rect x="2" y="3" width="20" height="8" rx="2" />
      <rect x="2" y="13" width="20" height="8" rx="2" />
      <path d="M6 7h.01M6 17h.01" />
    </Icon>
  ),
  queue: (
    <Icon>
      <path d="M3 6h18M3 12h18M3 18h12" />
    </Icon>
  ),
  actor: (
    <Icon>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21a8 8 0 0 1 16 0" />
    </Icon>
  ),
  external: (
    <Icon>
      <path d="M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" />
    </Icon>
  ),
};

const text = (value) => (typeof value === "string" || typeof value === "number" ? String(value) : "");

function Handles({ target = true, source = true }) {
  return (
    <>
      {target && <Handle type="target" position={Position.Top} />}
      {target && <Handle type="target" position={Position.Left} id="l" />}
      {source && <Handle type="source" position={Position.Bottom} />}
      {source && <Handle type="source" position={Position.Right} id="r" />}
    </>
  );
}

/** The label itself becomes editable in place, so starting an edit changes nothing in the layout. */
function EditableLabel({ id, label, selected, className }) {
  const { updateNodeData } = useReactFlow();
  const [editing, setEditing] = useState(false);
  const ref = useRef(null);
  const down = useRef(null);
  const active = useRef(false);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!editing || !el) return;
    active.current = true;
    el.textContent = label;
    el.focus();
    const range = document.createRange();
    range.selectNodeContents(el);
    range.collapse(false);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }, [editing]); // eslint-disable-line react-hooks/exhaustive-deps

  const finish = (save) => {
    const el = ref.current;
    if (!active.current || !el) return;
    active.current = false;
    const value = el.innerText.replace(/\n+$/, "");
    el.textContent = "";
    setEditing(false);
    if (save && value !== label) updateNodeData(id, { label: value });
  };

  return (
    <div
      ref={ref}
      className={`${className ?? ""} editable${editing ? " editing nodrag nopan" : ""}`}
      contentEditable={editing ? "plaintext-only" : undefined}
      suppressContentEditableWarning
      spellCheck={false}
      onPointerDown={(e) => {
        if (!editing) down.current = { x: e.clientX, y: e.clientY, selected };
      }}
      onClick={(e) => {
        if (editing) return;
        const start = down.current;
        down.current = null;
        if (start?.selected && Math.hypot(e.clientX - start.x, e.clientY - start.y) < 4) setEditing(true);
      }}
      onDoubleClick={() => setEditing(true)}
      onBlur={editing ? () => finish(true) : undefined}
      onKeyDown={
        editing
          ? (e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                finish(true);
              } else if (e.key === "Escape") {
                e.preventDefault();
                finish(false);
              }
            }
          : undefined
      }
    >
      {editing ? null : label}
    </div>
  );
}

function Text({ id, selected, data, mono = false }) {
  const status = text(data?.status);
  const tone = STATUS[status.toLowerCase()] ?? "todo";
  return (
    <div className="text">
      <EditableLabel id={id} selected={selected} label={text(data?.label)} className={mono ? "label mono" : "label"} />
      {text(data?.detail) && <div className="detail">{text(data.detail)}</div>}
      {(status || text(data?.tech)) && (
        <div className="chips">
          {text(data?.tech) && <span className="chip chip-todo">{text(data.tech)}</span>}
          {status && <span className={`chip chip-${tone}`}>{status}</span>}
        </div>
      )}
    </div>
  );
}

const Step = ({ id, data, selected }) => (
  <div className="card" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles />
    <Text id={id} selected={selected} data={data} />
  </div>
);
const Start = ({ id, data, selected }) => (
  <div className="card terminal" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles target={false} />
    <Text id={id} selected={selected} data={data} />
  </div>
);
const End = ({ id, data, selected }) => (
  <div className="card terminal" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles source={false} />
    <Text id={id} selected={selected} data={data} />
  </div>
);
const Decision = ({ id, data, selected }) => (
  <div className="decision" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles />
    <Text id={id} selected={selected} data={data} />
  </div>
);
const Service = ({ id, data, selected }) => (
  <div className="card row" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles />
    {ICONS.service}
    <Text id={id} selected={selected} data={data} />
  </div>
);
const Database = ({ id, data, selected }) => (
  <div className="database" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles />
    <Text id={id} selected={selected} data={data} />
  </div>
);
const Queue = ({ id, data, selected }) => (
  <div className="card row" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles />
    {ICONS.queue}
    <Text id={id} selected={selected} data={data} mono />
  </div>
);
const Api = ({ id, data, selected }) => (
  <div className="card row" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles />
    {text(data?.method) && <span className="method">{text(data.method).toUpperCase()}</span>}
    <Text id={id} selected={selected} data={data} mono />
  </div>
);
const Actor = ({ id, data, selected }) => (
  <div className="actor" {...tint(data)}>
    <Handles />
    <span className="avatar">{ICONS.actor}</span>
    <Text id={id} selected={selected} data={data} />
  </div>
);
const External = ({ id, data, selected }) => (
  <div className="card row external" {...tint(data)}>
    <Resizer id={id} selected={selected} />
    <Handles />
    {ICONS.external}
    <Text id={id} selected={selected} data={data} />
  </div>
);
const Note = ({ id, data, selected }) => (
  <div className="note" {...tint(data)}>
    <Resizer id={id} selected={selected} minWidth={60} minHeight={28} />
    <EditableLabel id={id} selected={selected} label={text(data?.label)} />
  </div>
);
const Group = ({ id, data, selected }) => (
  <div className="group" {...tint(data)}>
    <Resizer id={id} selected={selected} minWidth={120} minHeight={80} />
    <EditableLabel id={id} selected={selected} label={text(data?.label)} />
  </div>
);

const nodeTypes = {
  input: Start,
  output: End,
  default: Step,
  decision: Decision,
  service: Service,
  database: Database,
  queue: Queue,
  api: Api,
  actor: Actor,
  external: External,
  note: Note,
  group: Group,
};
/** Text typed in place on a connector. Enter or clicking away saves, Esc cancels; the caret starts at the end. */
function InlineEdit({ initial, onFinish }) {
  const ref = useRef(null);
  const active = useRef(true);

  useLayoutEffect(() => {
    const el = ref.current;
    el.textContent = initial;
    el.focus();
    const range = document.createRange();
    range.selectNodeContents(el);
    range.collapse(false);
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const finish = (save) => {
    if (!active.current) return;
    active.current = false;
    onFinish(save ? ref.current.innerText.replace(/\n+$/, "").trim() : null);
  };
  return (
    <div
      ref={ref}
      className="edge-text editing"
      contentEditable="plaintext-only"
      suppressContentEditableWarning
      spellCheck={false}
      onBlur={() => finish(true)}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          finish(true);
        } else if (e.key === "Escape") {
          e.preventDefault();
          finish(false);
        }
      }}
    />
  );
}

const PATHS = {
  default: getBezierPath,
  simplebezier: getSimpleBezierPath,
  straight: getStraightPath,
  smoothstep: getSmoothStepPath,
  step: (args) => getSmoothStepPath({ ...args, borderRadius: 0 }),
};

function makeEdge(getPath) {
  return function LabeledEdge({ id, sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, label, selected, markerEnd, style, data }) {
    const { setEdges } = useReactFlow();
    const [editing, setEditing] = useState(false);
    const was = useRef(false);
    const [path, x, y] = getPath({ sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition });
    const text = typeof label === "string" ? label : "";

    useEffect(() => {
      if (selected && !was.current) setEditing(true);
      if (!selected) setEditing(false);
      was.current = !!selected;
    }, [selected]);

    const commit = (value) => {
      setEditing(false);
      if (value === null || value === text) return;
      setEdges((all) => all.map((e) => {
        if (e.id !== id) return e;
        const { label: _drop, ...rest } = e;
        return value ? { ...rest, label: value } : rest;
      }));
    };
    const select = () => setEdges((all) => all.map((e) => ({ ...e, selected: e.id === id })));

    return (
      <>
        <BaseEdge id={id} path={path} markerEnd={data?.arrow === false ? undefined : markerEnd} style={{ ...style, ...(data?.color ? { stroke: COLORS[data.color] } : {}), ...(data?.dashed ? { strokeDasharray: "6 4" } : {}) }} interactionWidth={24} />
        {(text || selected) && (
          <EdgeLabelRenderer>
            <div className="edge-label nodrag nopan" style={{ transform: `translate(-50%, -50%) translate(${x}px, ${y}px)` }}>
              {editing ? (
                <InlineEdit initial={text} onFinish={commit} />
              ) : (
                <div className={text ? "edge-text" : "edge-text ghost"} onClick={() => (selected ? setEditing(true) : select())}>
                  {text || "Add text"}
                </div>
              )}
            </div>
          </EdgeLabelRenderer>
        )}
      </>
    );
  };
}

const edgeTypes = Object.fromEntries(Object.entries(PATHS).map(([name, fn]) => [name, makeEdge(fn)]));
const edgeOptions = { markerEnd: { type: MarkerType.ArrowClosed } };

const PALETTE = [
  { key: "start", group: "Flow", title: "Start", type: "input", label: "Start", shape: "pill" },
  { key: "step", group: "Flow", title: "Step", type: "default", label: "Step", shape: "box" },
  { key: "task", group: "Flow", title: "Task", type: "default", label: "Task", status: "todo", shape: "box" },
  { key: "decision", group: "Flow", title: "Decision", type: "decision", label: "Decision?", shape: "diamond" },
  { key: "end", group: "Flow", title: "End", type: "output", label: "End", shape: "pill" },
  { key: "service", group: "System", title: "Service", type: "service", label: "service", data: { tech: "Go" }, shape: "box" },
  { key: "database", group: "System", title: "Database", type: "database", label: "database", data: { tech: "PostgreSQL" }, shape: "cylinder" },
  { key: "queue", group: "System", title: "Queue", type: "queue", label: "topic.name", shape: "box" },
  { key: "api", group: "System", title: "API", type: "api", label: "/v1/path", data: { method: "get" }, shape: "box" },
  { key: "external", group: "System", title: "External", type: "external", label: "Third party", shape: "dashed" },
  { key: "actor", group: "System", title: "Actor", type: "actor", label: "User", shape: "circle" },
  { key: "note", group: "Other", title: "Note", type: "note", label: "Note", shape: "note" },
  { key: "group", group: "Other", title: "Group", type: "group", label: "Group", style: { width: 360, height: 220 }, zIndex: -1, shape: "dashed" },
];
const GROUPS = ["Flow", "System", "Other"];
const STATUSES = ["", "todo", "in progress", "blocked", "done"];
const RUNTIME_KEYS = ["measured", "selected", "dragging", "resizing", "positionAbsolute", "width", "height"];

const cleanNode = (node) => {
  const copy = { ...node };
  for (const key of RUNTIME_KEYS) delete copy[key];
  return copy;
};
const cleanEdge = ({ selected, ...edge }) => edge;
const serialize = (nodes, edges) => JSON.stringify({ nodes: nodes.map(cleanNode), edges: edges.map(cleanEdge) });
const newId = (prefix) => `${prefix}${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;

let apply = null;
let queued = [];
window.sequenceFlow = {
  load: (payload) => (apply ? apply({ load: payload }) : queued.push({ load: payload })),
  theme: (mode) => (apply ? apply({ mode }) : queued.push({ mode })),
};

function Palette() {
  const [open, setOpen] = useState(() => {
    try {
      return localStorage.getItem("flowPalette") !== "closed";
    } catch {
      return true;
    }
  });
  const toggle = () =>
    setOpen((value) => {
      try {
        localStorage.setItem("flowPalette", value ? "closed" : "open");
      } catch {}
      return !value;
    });
  return (
    <aside className="float palette-panel">
      <button className="palette-head" onClick={toggle} aria-expanded={open}>
        <span>Components</span>
        <span className="caret">{open ? "\u25B4" : "\u25BE"}</span>
      </button>
      {open && (
        <>
          {GROUPS.map((group) => (
            <div key={group} className="palette-group">
              <div className="palette-title">{group}</div>
              <div className="palette">
                {PALETTE.filter((item) => item.group === group).map((item) => (
                  <div
                    key={item.key}
                    className="palette-item"
                    draggable
                    title="Drag onto the canvas, or click to add"
                    onDragStart={(event) => {
                      event.dataTransfer.setData("application/sequence-flow", item.key);
                      event.dataTransfer.effectAllowed = "move";
                    }}
                    onClick={() => window.sequenceAdd?.(item)}
                  >
                    <span className={`swatch swatch-${item.shape}`} />
                    <span className="palette-name">{item.title}</span>
                    {item.status && <span className={`chip chip-${STATUS[item.status]}`}>{item.status}</span>}
                  </div>
                ))}
              </div>
            </div>
          ))}
          <p className="hint">Drag onto the canvas, or click to add. Drag from a dot to connect.</p>
        </>
      )}
    </aside>
  );
}

const FIELDS = {
  service: [["tech", "Tech"]],
  database: [["tech", "Engine"]],
  queue: [["tech", "Broker"]],
  external: [["tech", "Kind"]],
  api: [["method", "Method"]],
};

const PATH_KINDS = [
  ["default", "Curved"],
  ["smoothstep", "Rounded steps"],
  ["step", "Steps"],
  ["straight", "Straight"],
];

/** Merges `patch` into `data`, dropping keys set to "" or undefined. */
const patchData = (data, patch) => {
  const out = { ...data, ...patch };
  for (const key of Object.keys(out)) if (out[key] === "" || out[key] === undefined) delete out[key];
  return out;
};
const omitUndefined = (object) => Object.fromEntries(Object.entries(object).filter(([, value]) => value !== undefined));

function Swatches({ value, onPick }) {
  return (
    <div className="dots" role="group" aria-label="Colour">
      <button className={`dot none${value ? "" : " on"}`} title="Default" aria-label="Default colour" onClick={() => onPick("")} />
      {Object.keys(COLORS).map((name) => (
        <button key={name} className={`dot${value === name ? " on" : ""}`} style={{ background: COLORS[name] }} title={name} aria-label={name} onClick={() => onPick(name)} />
      ))}
    </div>
  );
}

function Inspector({ nodes, edges, onNode, onNodes, onEdges, onDelete }) {
  const pickedNodes = nodes.filter((n) => n.selected);
  const pickedEdges = pickedNodes.length ? [] : edges.filter((e) => e.selected);
  if (!pickedNodes.length && !pickedEdges.length) return null;

  const nodeIds = pickedNodes.map((n) => n.id);
  const edgeIds = pickedEdges.map((e) => e.id);
  const setNodeColor = (color) => onNodes(nodeIds, (n) => ({ ...n, data: patchData(n.data, { color }) }));
  const setEdgeColor = (color) =>
    onEdges(edgeIds, (e) => ({ ...e, data: patchData(e.data, { color }), markerEnd: color ? { type: MarkerType.ArrowClosed, color: COLORS[color] } : undefined }));

  if (pickedNodes.length > 1) {
    return (
      <aside className="float inspector">
        <h3>{pickedNodes.length} selected</h3>
        <Swatches value={pickedNodes.every((n) => n.data?.color === pickedNodes[0].data?.color) ? pickedNodes[0].data?.color : ""} onPick={setNodeColor} />
        <button onClick={onDelete}>Delete {pickedNodes.length} items</button>
      </aside>
    );
  }

  if (pickedNodes.length === 1) {
    const node = pickedNodes[0];
    const sized = node.type !== "group" && (node.style?.width || node.style?.height);
    return (
      <aside className="float inspector">
        <h3>{PALETTE.find((p) => p.type === (node.type ?? "default") && !p.status)?.title ?? "Step"}</h3>
        <input value={node.data?.label ?? ""} placeholder="Label" onChange={(e) => onNode(node.id, { label: e.target.value })} />
        {!["note", "group"].includes(node.type) && <input value={node.data?.detail ?? ""} placeholder="Detail" onChange={(e) => onNode(node.id, { detail: e.target.value })} />}
        {(FIELDS[node.type] ?? []).map(([key, label]) => (
          <input key={key} value={node.data?.[key] ?? ""} placeholder={label} onChange={(e) => onNode(node.id, { [key]: e.target.value })} />
        ))}
        {!["note", "group", "actor"].includes(node.type) && (
          <select value={node.data?.status ?? ""} onChange={(e) => onNode(node.id, { status: e.target.value })}>
            {STATUSES.map((value) => (
              <option key={value} value={value}>{value || "No status"}</option>
            ))}
          </select>
        )}
        <Swatches value={node.data?.color} onPick={setNodeColor} />
        {sized && (
          <button
            className="plain"
            onClick={() =>
              onNodes(nodeIds, (n) => {
                const { width, height, className, ...rest } = n;
                const style = { ...rest.style };
                delete style.width;
                delete style.height;
                const classes = (className ?? "").split(" ").filter((c) => c && c !== "sized").join(" ");
                return { ...rest, style: Object.keys(style).length ? style : undefined, className: classes || undefined };
              })
            }
          >
            Fit to content
          </button>
        )}
        <button onClick={onDelete}>Delete</button>
      </aside>
    );
  }

  const first = pickedEdges[0];
  return (
    <aside className="float inspector">
      <h3>{pickedEdges.length > 1 ? `${pickedEdges.length} connectors` : "Connector"}</h3>
      {pickedEdges.length === 1 && (
        <input value={typeof first.label === "string" ? first.label : ""} placeholder="Label" onChange={(e) => onEdges(edgeIds, (edge) => (e.target.value ? { ...edge, label: e.target.value } : { ...edge, label: undefined }))} />
      )}
      <select value={first.type ?? "default"} onChange={(e) => onEdges(edgeIds, (edge) => ({ ...edge, type: e.target.value === "default" ? undefined : e.target.value }))}>
        {PATH_KINDS.map(([value, label]) => (
          <option key={value} value={value}>{label}</option>
        ))}
      </select>
      <label className="check">
        <input type="checkbox" checked={!!first.data?.dashed} onChange={(e) => onEdges(edgeIds, (edge) => ({ ...edge, data: patchData(edge.data, { dashed: e.target.checked ? true : undefined }) }))} />
        Dashed line
      </label>
      <label className="check">
        <input type="checkbox" checked={first.data?.arrow !== false} onChange={(e) => onEdges(edgeIds, (edge) => ({ ...edge, data: patchData(edge.data, { arrow: e.target.checked ? undefined : false }) }))} />
        Arrowhead
      </label>
      <Swatches value={first.data?.color} onPick={setEdgeColor} />
      <button onClick={onDelete}>Delete</button>
    </aside>
  );
}

function Editor() {
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);
  const [meta, setMeta] = useState({ flowId: null, mode: "light" });
  const { screenToFlowPosition, deleteElements } = useReactFlow();
  const dragging = useRef(false);
  const shown = useRef(null);
  const synced = useRef("");
  const timer = useRef(null);
  const pending = useRef(null);

  const nodesRef = useRef(nodes);
  nodesRef.current = nodes;
  const edgesRef = useRef(edges);
  edgesRef.current = edges;

  // Undo history. `base` is the last state on the timeline; an edit is recorded once it has been still for 350 ms,
  // so a drag, a resize or a burst of typing is a single step.
  const history = useRef(createHistory());
  const base = useRef("");
  const latest = useRef("");
  const before = useRef(null);
  const historyTimer = useRef(null);
  const [canHistory, setCanHistory] = useState({ undo: false, redo: false });
  const refreshHistory = useCallback(() => setCanHistory({ undo: history.current.canUndo, redo: history.current.canRedo }), []);

  const commitHistory = useCallback(() => {
    clearTimeout(historyTimer.current);
    historyTimer.current = null;
    if (before.current !== null && before.current !== latest.current) history.current.record(before.current);
    before.current = null;
    base.current = latest.current;
    refreshHistory();
  }, [refreshHistory]);

  const flush = useCallback(() => {
    clearTimeout(timer.current);
    timer.current = null;
    const edit = pending.current;
    if (!edit) return;
    pending.current = null;
    synced.current = edit.graph;
    post({ type: "changed", flowId: edit.flowId, graph: edit.graph });
  }, []);

  useEffect(() => {
    apply = (action) => {
      if (action.mode) return setMeta((m) => ({ ...m, mode: action.mode }));
      const { flowId, graph } = action.load;
      const loadedNodes = (graph?.nodes ?? []).map((n) => (n.type === "group" && n.zIndex === undefined ? { ...n, zIndex: -1 } : n));
      const loadedEdges = graph?.edges ?? [];
      const incoming = serialize(loadedNodes, loadedEdges);
      if (flowId === shown.current && (dragging.current || pending.current || incoming === synced.current)) return;
      if (flowId !== shown.current) flush();
      shown.current = flowId;
      synced.current = incoming;
      clearTimeout(historyTimer.current);
      historyTimer.current = null;
      before.current = null;
      base.current = incoming;
      latest.current = incoming;
      history.current.reset();
      refreshHistory();
      setNodes(loadedNodes);
      setEdges(loadedEdges);
      setMeta((m) => ({ ...m, flowId }));
    };
    queued.forEach(apply);
    queued = [];
    post({ type: "ready" });
    return () => {
      apply = null;
    };
  }, [setNodes, setEdges, flush, refreshHistory]);

  useEffect(() => {
    const flowId = shown.current;
    if (flowId == null) return;
    const graph = serialize(nodes, edges);
    latest.current = graph;
    if (graph !== base.current) {
      if (before.current === null) before.current = base.current;
      clearTimeout(historyTimer.current);
      historyTimer.current = setTimeout(commitHistory, 350);
    }
    if (graph === synced.current) return;
    pending.current = { flowId, graph };
    clearTimeout(timer.current);
    timer.current = setTimeout(flush, 400);
  }, [nodes, edges, flush, commitHistory]);

  const applyState = useCallback((state) => {
    const graph = JSON.parse(state);
    clearTimeout(historyTimer.current);
    historyTimer.current = null;
    before.current = null;
    base.current = state;
    latest.current = state;
    setNodes(graph.nodes);
    setEdges(graph.edges);
  }, [setNodes, setEdges]);

  const undo = useCallback(() => {
    commitHistory();
    const previous = history.current.undo(latest.current);
    if (previous !== null) applyState(previous);
    refreshHistory();
  }, [commitHistory, applyState, refreshHistory]);

  const redo = useCallback(() => {
    commitHistory();
    const next = history.current.redo(latest.current);
    if (next !== null) applyState(next);
    refreshHistory();
  }, [commitHistory, applyState, refreshHistory]);

  const addNode = useCallback((item, position) => {
    const at = position ?? screenToFlowPosition({ x: window.innerWidth / 2 - 100, y: window.innerHeight / 2 });
    const data = { label: item.label, ...(item.data ?? {}), ...(item.status ? { status: item.status } : {}) };
    const node = { id: newId("n"), type: item.type, position: at, data, selected: true, ...(item.style ? { style: item.style } : {}), ...(item.zIndex !== undefined ? { zIndex: item.zIndex } : {}) };
    setNodes((current) => [...current.map((n) => ({ ...n, selected: false })), node]);
  }, [screenToFlowPosition, setNodes]);

  useEffect(() => {
    window.sequenceAdd = (item) => addNode(item);
    return () => {
      delete window.sequenceAdd;
    };
  }, [addNode]);

  // Copy, cut, paste, duplicate and select all. The copy lives in this page and, best effort, in the system clipboard as text.
  const clip = useRef(null);
  const pastes = useRef(0);
  const insert = useCallback((payload, step) => {
    const out = pasteSelection(payload, newId, { x: 30 * step, y: 30 * step });
    setNodes((current) => [...current.map((n) => ({ ...n, selected: false })), ...out.nodes.map((n) => ({ ...n, selected: true }))]);
    setEdges((current) => [...current.map((e) => ({ ...e, selected: false })), ...out.edges]);
  }, [setNodes, setEdges]);

  const copy = useCallback(() => {
    const payload = copySelection(nodesRef.current, edgesRef.current);
    if (!payload) return false;
    clip.current = payload;
    pastes.current = 0;
    navigator.clipboard?.writeText(serializeClipboard(payload)).catch(() => {});
    return true;
  }, []);

  useEffect(() => {
    const typing = (target) => target instanceof Element && target.closest("[contenteditable], input, textarea, select");
    const onKey = (e) => {
      if (typing(e.target) || !(e.metaKey || e.ctrlKey)) return;
      const key = e.key.toLowerCase();
      if (key === "z") {
        e.preventDefault();
        if (e.shiftKey) redo();
        else undo();
      } else if (key === "y") {
        e.preventDefault();
        redo();
      } else if (key === "c") {
        if (copy()) e.preventDefault();
      } else if (key === "x") {
        if (copy()) {
          e.preventDefault();
          deleteElements({ nodes: nodesRef.current.filter((n) => n.selected), edges: edgesRef.current.filter((x) => x.selected) });
        }
      } else if (key === "v") {
        if (clip.current) {
          e.preventDefault();
          pastes.current += 1;
          insert(clip.current, pastes.current);
        }
      } else if (key === "d") {
        e.preventDefault();
        const payload = copySelection(nodesRef.current, edgesRef.current);
        if (payload) insert(payload, 1);
      } else if (key === "a") {
        e.preventDefault();
        setNodes((current) => current.map((n) => ({ ...n, selected: true })));
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [undo, redo, copy, insert, deleteElements, setNodes]);

  const onDrop = useCallback((event) => {
    event.preventDefault();
    const item = PALETTE.find((p) => p.key === event.dataTransfer.getData("application/sequence-flow"));
    if (item) addNode(item, screenToFlowPosition({ x: event.clientX, y: event.clientY }));
  }, [addNode, screenToFlowPosition]);

  const onDragOver = useCallback((event) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = "move";
  }, []);

  const onConnect = useCallback((connection) => setEdges((current) => addEdge({ ...connection, id: newId("e") }, current)), [setEdges]);
  const patchNodes = useCallback((ids, change) => setNodes((current) => current.map((n) => (ids.includes(n.id) ? omitUndefined(change(n)) : n))), [setNodes]);
  const patchEdges = useCallback((ids, change) => setEdges((current) => current.map((e) => (ids.includes(e.id) ? omitUndefined(change(e)) : e))), [setEdges]);
  const onNode = useCallback((id, patch) => patchNodes([id], (n) => ({ ...n, data: patchData(n.data, patch) })), [patchNodes]);
  const onDelete = useCallback(() => deleteElements({ nodes: nodes.filter((n) => n.selected), edges: edges.filter((e) => e.selected) }), [deleteElements, nodes, edges]);

  const onDragStart = useCallback(() => {
    dragging.current = true;
  }, []);
  const onDragStop = useCallback(() => {
    dragging.current = false;
  }, []);

  return (
    <div className={`editor ${meta.mode}`}>
      <div className="canvas" onDrop={onDrop} onDragOver={onDragOver}>
        <ReactFlow
          key={meta.flowId ?? "none"}
          nodes={nodes}
          edges={edges}
          nodeTypes={nodeTypes}
          edgeTypes={edgeTypes}
          defaultEdgeOptions={edgeOptions}
          className={meta.mode}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onNodeDragStart={onDragStart}
          onNodeDragStop={onDragStop}
          selectionOnDrag
          selectionMode={SelectionMode.Partial}
          panOnDrag={[1, 2]}
          panOnScroll
          zoomOnScroll={false}
          fitView
          fitViewOptions={{ padding: 0.2, maxZoom: 1.2 }}
          minZoom={0.1}
          proOptions={{ hideAttribution: true }}
        >
          <Background gap={20} />
          <Controls showInteractive={false}>
            <ControlButton onClick={undo} disabled={!canHistory.undo} title="Undo (⌘Z)" aria-label="Undo">
              <svg className="hist" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M9 14 4 9l5-5" /><path d="M4 9h10a6 6 0 0 1 0 12h-3" /></svg>
            </ControlButton>
            <ControlButton onClick={redo} disabled={!canHistory.redo} title="Redo (⇧⌘Z)" aria-label="Redo">
              <svg className="hist" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m15 14 5-5-5-5" /><path d="M20 9H10a6 6 0 0 0 0 12h3" /></svg>
            </ControlButton>
          </Controls>
        </ReactFlow>
      </div>
      <Palette />
      <Inspector nodes={nodes} edges={edges} onNode={onNode} onNodes={patchNodes} onEdges={patchEdges} onDelete={onDelete} />
    </div>
  );
}

createRoot(document.getElementById("root")).render(
  <ReactFlowProvider>
    <Editor />
  </ReactFlowProvider>,
);
