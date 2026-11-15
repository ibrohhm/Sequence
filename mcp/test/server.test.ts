import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { makeVault, vaultsFile } from "./helpers.ts";

const NAMES = ["create_project", "create_topic", "edit_topic", "find_topic", "list_projects", "list_vaults", "overwrite_topic", "read_topic", "search_content"];

async function connect(vaultsPath: string): Promise<Client> {
  const client = new Client({ name: "test", version: "0" });
  await client.connect(new StdioClientTransport({
    command: "node",
    args: [join(import.meta.dirname, "..", "dist", "index.js")],
    env: { ...process.env, SEQUENCE_VAULTS_FILE: vaultsPath } as Record<string, string>,
  }));
  return client;
}

const text = (r: unknown) => ((r as { content: { text: string }[] }).content[0].text);

test("server lists exactly the nine tools", async () => {
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
