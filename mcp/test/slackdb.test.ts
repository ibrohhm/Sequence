import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SLACK_TASKS_DDL, dbPath, openDb } from "../src/slackdb.ts";

async function tmpFile(): Promise<string> {
  return join(await mkdtemp(join(tmpdir(), "slackdb-")), "nested", "deeper", "slack-tasks.db");
}

test("openDb creates the missing parent folder and the file", async () => {
  const file = await tmpFile();
  openDb(file).close();
  assert.ok((await stat(file)).isFile());
});

test("openDb sets user_version 2 and WAL mode", async () => {
  const db = openDb(await tmpFile());
  assert.equal((db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version, 2);
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

test("Swift and TypeScript DDL are identical", async () => {
  const swift = await readFile(join(import.meta.dirname, "..", "..", "Sources", "StudioCore", "SlackTaskStore.swift"), "utf8");
  const match = /static let ddl = """\n([\s\S]*?)"""/.exec(swift);
  assert.ok(match, "SlackTaskStore.swift must define static let ddl");
  const normalize = (text: string) => text.replace(/\s+/g, " ").trim();
  assert.equal(normalize(match[1]), normalize(SLACK_TASKS_DDL));
});

test("openDb upgrades a v1 database in place and keeps its rows", async () => {
  const file = await tmpFile();
  const { mkdirSync } = await import("node:fs");
  const { dirname } = await import("node:path");
  const { DatabaseSync } = await import("node:sqlite");
  mkdirSync(dirname(file), { recursive: true });
  const old = new DatabaseSync(file);
  old.exec(`CREATE TABLE tasks (
    channel_id TEXT NOT NULL, thread_ts TEXT NOT NULL, permalink TEXT NOT NULL, channel_name TEXT, snippet TEXT,
    replies INTEGER, replies_at_tag INTEGER, last_reply TEXT, tagged TEXT NOT NULL, synced TEXT,
    status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','inprogress','blocked','done')),
    archived INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel_id, thread_ts))`);
  old.exec("INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status) VALUES ('C','1.1','p','2026-11-15','blocked')");
  old.exec("PRAGMA user_version = 1");
  old.close();
  const db = openDb(file);
  const columns = (db.prepare("PRAGMA table_info(tasks)").all() as { name: string }[]).map((c) => c.name);
  for (const name of ["summary", "next_action", "summary_replies"]) assert.ok(columns.includes(name), name);
  assert.equal((db.prepare("SELECT status FROM tasks").get() as { status: string }).status, "blocked");
  assert.equal((db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version, 2);
  db.close();
  openDb(file).close();
});
