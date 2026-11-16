import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { openDb } from "../src/slackdb.ts";
import { listSlackTags } from "../src/slacktags.ts";

async function fresh() {
  return openDb(join(await mkdtemp(join(tmpdir(), "slacktags-")), "t.db"));
}

test("listSlackTags returns the two seeds in position order with parsed arrays", async () => {
  const db = await fresh();
  assert.deepEqual(listSlackTags(db), [
    { id: "todo", name: "To-do", kind: "board", slack_list: "todo", reactions: ["loading", "loading1"], columns: ["Todo", "In progress", "Blocked", "Done"] },
    { id: "saved", name: "Saved", kind: "list", slack_list: "saved", reactions: [], columns: [] },
  ]);
});

test("listSlackTags reflects a tag added by raw SQL and respects position", async () => {
  const db = await fresh();
  db.prepare("INSERT INTO tags (id, name, kind, slack_list, reactions, columns, position) VALUES ('ticket','Ticket','board','none','[\"ticket\"]','[\"Open\",\"Done\"]',-1)").run();
  const tags = listSlackTags(db);
  assert.deepEqual(tags.map((t) => t.id), ["ticket", "todo", "saved"]);
  assert.deepEqual(tags[0].reactions, ["ticket"]);
});
