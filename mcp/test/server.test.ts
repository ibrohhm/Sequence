import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { makeVault, vaultsFile } from "./helpers.ts";

const NAMES = ["create_project", "create_topic", "edit_topic", "find_topic", "list_projects", "list_vaults", "overwrite_topic", "read_topic", "search_content", "upsert_slack_task"];

async function connect(vaultsPath: string, slackDb?: string): Promise<Client> {
  const client = new Client({ name: "test", version: "0" });
  await client.connect(new StdioClientTransport({
    command: "node",
    args: [join(import.meta.dirname, "..", "dist", "index.js")],
    env: { ...process.env, SEQUENCE_VAULTS_FILE: vaultsPath, ...(slackDb ? { SEQUENCE_SLACK_DB: slackDb } : {}) } as Record<string, string>,
  }));
  return client;
}

const text = (r: unknown) => ((r as { content: { text: string }[] }).content[0].text);

test("server lists exactly the ten tools", async () => {
  const v = await makeVault({}, { git: true });
  const client = await connect(await vaultsFile([v]));
  try {
    const { tools } = await client.listTools();
    assert.deepEqual(tools.map((t) => t.name).sort(), NAMES);
  } finally {
    await client.close();
  }
});

test("find, create, read and edit round trip", async () => {
  const v = await makeVault({ "qris/qris-settlement-flow.puml": "@startuml\n@enduml" }, { git: true });
  const client = await connect(await vaultsFile([v]));
  try {
    const found = await client.callTool({ name: "find_topic", arguments: { query: "settlement" } });
    assert.match(text(found), /qris-settlement-flow\.puml/);
    await client.callTool({ name: "create_topic", arguments: { project: "qris", name: "notes.md", content: "hello" } });
    assert.equal(text(await client.callTool({ name: "read_topic", arguments: { path: "qris/notes.md" } })), "hello");
    const edit = await client.callTool({ name: "edit_topic", arguments: { path: "qris/notes.md", old: "hello", new: "bye" } });
    assert.notEqual((edit as { isError?: boolean }).isError, true);
    assert.equal(await readFile(join(v.path, "qris/notes.md"), "utf8"), "bye");
  } finally {
    await client.close();
  }
});

test("a bad vaults file returns an error result and the server stays alive", async () => {
  const client = await connect("/nonexistent/vaults.json");
  try {
    const first = await client.callTool({ name: "list_vaults", arguments: {} });
    assert.equal((first as { isError?: boolean }).isError, true);
    const second = await client.callTool({ name: "find_topic", arguments: { query: "x" } });
    assert.equal((second as { isError?: boolean }).isError, true);
  } finally {
    await client.close();
  }
});

const SLACK = {
  channel_id: "C07R08WFC81",
  message_ts: "1794536057.965929",
  permalink: "https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929",
  channel_name: "agent-network-eng",
  snippet: "Store internal_account_number",
  replies: 0,
  last_reply: "1794536057.965929",
};

test("upsert_slack_task round trip: created then updated", async () => {
  const db = join(await mkdtemp(join(tmpdir(), "srv-db-")), "slack-tasks.db");
  const client = await connect(await vaultsFile([]), db);
  try {
    const first = JSON.parse(text(await client.callTool({ name: "upsert_slack_task", arguments: SLACK })));
    assert.equal(first.action, "created");
    const second = JSON.parse(text(await client.callTool({ name: "upsert_slack_task", arguments: { ...SLACK, replies: 2 } })));
    assert.equal(second.action, "updated");
    assert.equal(second.thread_ts, "1794536057.965929");
  } finally {
    await client.close();
  }
});

test("upsert_slack_task with bad input returns an error and the server stays alive", async () => {
  const db = join(await mkdtemp(join(tmpdir(), "srv-db-")), "slack-tasks.db");
  const client = await connect(await vaultsFile([]), db);
  try {
    const bad = await client.callTool({ name: "upsert_slack_task", arguments: { ...SLACK, replies: -1 } });
    assert.equal((bad as { isError?: boolean }).isError, true);
    assert.match(text(bad), /replies/);
    const ok = await client.callTool({ name: "list_vaults", arguments: {} });
    assert.notEqual((ok as { isError?: boolean }).isError, true);
  } finally {
    await client.close();
  }
});
