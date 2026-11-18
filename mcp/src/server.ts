import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { findTopic, listProjects, readTopic, searchContent } from "./find.ts";
import { createProject, createTopic, editTopic, overwriteTopic } from "./write.ts";
import { loadVaults, pickVault, type Vault } from "./vaults.ts";
import { openDb } from "./slackdb.ts";
import { getSlackTask, upsertSlackTask } from "./slacktasks.ts";
import { listSlackTags } from "./slacktags.ts";
import { deleteFlow, getFlow, listFlows, upsertFlow } from "./flows.ts";

type Shape = Record<string, z.ZodType>;

export function buildServer(): McpServer {
  const server = new McpServer({ name: "sequence-vaults", version: "0.1.0" });

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  type Args = any;
  function tool(name: string, description: string, shape: Shape, run: (vaults: Vault[], args: Args) => Promise<unknown>, needsVaults = true): void {
    server.registerTool(name, { description, inputSchema: shape }, async (args: Args) => {
      try {
        const data = await run(needsVaults ? await loadVaults() : [], args);
        return { content: [{ type: "text" as const, text: typeof data === "string" ? data : JSON.stringify(data, null, 2) }] };
      } catch (e) {
        return { isError: true, content: [{ type: "text" as const, text: (e as Error).message }] };
      }
    });
  }

  const vault = z.string().optional().describe("Vault name; needed when more than one vault could match");
  const project = z.string().optional().describe("Project folder to search in");

  tool("list_vaults", "List the Sequence vaults (name and path).", {}, async (vaults) => vaults.map(({ name, path }) => ({ name, path })));
  tool("list_projects", "List the project folders in a vault.", { vault }, async (vaults, a) => listProjects(pickVault(vaults, a.vault)));
  tool("find_topic", "Find topic files by name (all words must match), optionally within one project or vault.", { query: z.string(), project, vault }, (vaults, a) => findTopic(vaults, a.query, a));
  tool("search_content", "Find files containing a text (case-insensitive) and show the first matching line.", { query: z.string(), project, vault }, (vaults, a) => searchContent(vaults, a.query, a));
  tool("read_topic", "Read a topic file by vault-relative path.", { path: z.string(), vault }, (vaults, a) => readTopic(vaults, a.path, a.vault));
  tool("create_project", "Create a new project folder in a vault.", { name: z.string(), vault }, (vaults, a) => createProject(vaults, a.name, a.vault));
  tool("create_topic", "Create a new topic file in an existing project; fails if it exists. The name needs an extension (.puml .plantuml .pu .wsd .md).", { project: z.string(), name: z.string(), content: z.string(), vault }, (vaults, a) => createTopic(vaults, a.project, a.name, a.content, a.vault));
  tool("edit_topic", "Replace one exact piece of text in a topic; fails unless old occurs exactly once. Commits the change.", { path: z.string(), old: z.string(), new: z.string(), vault }, (vaults, a) => editTopic(vaults, a.path, a.old, a.new, a.vault));
  tool("overwrite_topic", "Replace the whole content of an existing topic. Prefer edit_topic. Commits the change.", { path: z.string(), content: z.string(), vault }, (vaults, a) => overwriteTopic(vaults, a.path, a.content, a.vault));

  tool(
    "upsert_slack_task",
    "Create or update a Slack thread card in the Sequence tasks database. Keeps status and archived; skips archived threads. Pass the thread's first message as snippet and the reply count. The result has summary_stale: when true, call again with summary and next_action.",
    {
      tag: z.string().describe("Tag id from list_slack_tags"),
      channel_id: z.string(),
      message_ts: z.string().describe("ts of the message that was tagged"),
      thread_ts: z.string().optional().describe("ts of the thread's first message, if known"),
      permalink: z.string(),
      channel_name: z.string(),
      snippet: z.string(),
      replies: z.number().int().min(0).optional().describe("Reply count; required for board tags, omit for list tags"),
      last_reply: z.string().describe("Slack ts or ISO time of the last message in the thread"),
      summary: z.string().max(300).optional().describe("Where the thread stands now, about 140 characters; send only when summary_stale was true"),
      next_action: z.string().max(200).optional().describe("What the user should do or wait for, about 100 characters; needs summary"),
      reactions: z.array(z.string()).optional().describe("Emoji names (no colons) of the tag reactions the user put on this thread, such as [\"ticket\"]; omit to keep what is stored"),
    },
    async (_vaults, a) => {
      const db = openDb();
      try {
        return upsertSlackTask(db, a);
      } finally {
        db.close();
      }
    },
    false,
  );

  tool(
    "list_slack_tags",
    "List the Slack tags (id, name, kind board or list, slack_list none/todo/saved, reactions, columns) in the Sequence tasks database, in page order.",
    {},
    async () => {
      const db = openDb();
      try {
        return listSlackTags(db);
      } finally {
        db.close();
      }
    },
    false,
  );

  tool(
    "get_slack_task",
    "Get one Slack task by its number (the #12 shown on its card in Sequence): tag, status, summary, next action, replies, last activity and the Slack link.",
    { number: z.number().int().min(1).describe("The task number, without the #") },
    async (_vaults, a) => {
      const db = openDb();
      try {
        const task = getSlackTask(db, a.number);
        if (!task) throw new Error(`No task #${a.number}`);
        return task;
      } finally {
        db.close();
      }
    },
    false,
  );

  const node = z.looseObject({ id: z.string() });
  const edge = z.looseObject({ source: z.string(), target: z.string() });

  tool(
    "list_flows",
    "List the flows shown on the Flows page of Sequence (id and name), in page order.",
    {},
    async () => {
      const db = openDb();
      try {
        return listFlows(db);
      } finally {
        db.close();
      }
    },
    false,
  );

  tool(
    "get_flow",
    "Get one flow with its React Flow graph (nodes and edges), by id from list_flows or by name.",
    { id: z.number().int().optional(), name: z.string().optional() },
    async (_vaults, a) => {
      const db = openDb();
      try {
        const flow = getFlow(db, a);
        if (!flow) throw new Error("No such flow");
        return flow;
      } finally {
        db.close();
      }
    },
    false,
  );

  tool(
    "upsert_flow",
    "Create or replace a flow shown on the Flows page of Sequence. Nodes: {id, type?, data: {label, detail?, status?, tech?, method?}, position?: {x, y}}; a node without position keeps the one the user dragged it to, else goes on a grid. Node types: input (start), output (end), default (step), decision (diamond, branch with edge labels), service (microservice; data.tech like Go), database (cylinder), queue (topic or queue, monospace), api (endpoint; data.method GET/POST, label is the path), actor (person or system that starts the flow), external (third party, dashed), note (free text, no connections), group (dashed container; give style {width, height}, and set parentId on children, listed after it, with positions relative to the group). data.status is Todo, In progress, Blocked or Done and shows as a coloured chip. data.color (blue, green, amber, red, purple, gray) tints a node or a connector; connector data may also set dashed: true and arrow: false. Edges: {source, target, label?, type?: default|straight|step|smoothstep|simplebezier, animated?: true for async, sourceHandle?: \"r\", targetHandle?: \"l\"}; the default handles are bottom to top, use r and l for left to right layouts. Replaces the whole graph.",
    {
      name: z.string().describe("Flow name; the same name updates that flow"),
      nodes: z.array(node),
      edges: z.array(edge),
    },
    async (_vaults, a) => {
      const db = openDb();
      try {
        return upsertFlow(db, a);
      } finally {
        db.close();
      }
    },
    false,
  );

  tool(
    "delete_flow",
    "Permanently delete one flow from the Flows page of Sequence, by id from list_flows or by name. It cannot be undone and the graph is lost; ask the user to confirm the flow name first.",
    { id: z.number().int().optional(), name: z.string().optional() },
    async (_vaults, a) => {
      if (a.id === undefined && !a.name) throw new Error("Pass an id or a name");
      const db = openDb();
      try {
        return deleteFlow(db, a);
      } finally {
        db.close();
      }
    },
    false,
  );

  return server;
}
