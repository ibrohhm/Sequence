import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { findTopic, listProjects, readTopic, searchContent } from "./find.ts";
import { createProject, createTopic, editTopic, overwriteTopic } from "./write.ts";
import { loadVaults, pickVault, type Vault } from "./vaults.ts";
import { openDb } from "./slackdb.ts";
import { upsertSlackTask } from "./slacktasks.ts";

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
      channel_id: z.string(),
      message_ts: z.string().describe("ts of the message that was tagged"),
      thread_ts: z.string().optional().describe("ts of the thread's first message, if known"),
      permalink: z.string(),
      channel_name: z.string(),
      snippet: z.string(),
      replies: z.number().int().min(0),
      last_reply: z.string().describe("Slack ts or ISO time of the last message in the thread"),
      summary: z.string().max(300).optional().describe("Where the thread stands now, about 140 characters; send only when summary_stale was true"),
      next_action: z.string().max(200).optional().describe("What the user should do or wait for, about 100 characters; needs summary"),
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

  return server;
}
