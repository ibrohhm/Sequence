import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { dbPath, openDb } from "../src/slackdb.ts";

async function tmpFile(): Promise<string> {
  return join(await mkdtemp(join(tmpdir(), "slackdb-")), "nested", "deeper", "slack-tasks.db");
}

test("openDb creates the missing parent folder and the file", async () => {
  const file = await tmpFile();
  openDb(file).close();
  assert.ok((await stat(file)).isFile());
});

test("openDb sets user_version 1 and WAL mode", async () => {
  const db = openDb(await tmpFile());
  assert.equal((db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version, 1);
  assert.equal((db.prepare("PRAGMA journal_mode").get() as { journal_mode: string }).journal_mode, "wal");
  db.close();
});

test("opening the same file twice does not fail", async () => {
  const file = await tmpFile();
  openDb(file).close();
  openDb(file).close();
});

test("a status outside the four values is rejected", async () => {
  const db = openDb(await tmpFile());
  assert.throws(() => db.prepare("INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status) VALUES ('C','1.1','p','2026-11-15','weird')").run());
  db.close();
});

test("a minimal row defaults to todo and not archived", async () => {
  const db = openDb(await tmpFile());
  db.prepare("INSERT INTO tasks (channel_id, thread_ts, permalink, tagged) VALUES ('C','1.1','p','2026-11-15')").run();
  const row = db.prepare("SELECT status, archived FROM tasks").get() as { status: string; archived: number };
  assert.deepEqual({ ...row }, { status: "todo", archived: 0 });
  db.close();
});

test("dbPath honours SEQUENCE_SLACK_DB and has a default", () => {
  const saved = process.env.SEQUENCE_SLACK_DB;
  try {
    process.env.SEQUENCE_SLACK_DB = "/tmp/custom.db";
    assert.equal(dbPath(), "/tmp/custom.db");
    delete process.env.SEQUENCE_SLACK_DB;
    assert.ok(dbPath().endsWith("Application Support/Sequence/slack-tasks.db"));
  } finally {
    if (saved === undefined) delete process.env.SEQUENCE_SLACK_DB; else process.env.SEQUENCE_SLACK_DB = saved;
  }
});
