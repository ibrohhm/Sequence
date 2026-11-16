import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync } from "node:fs";
import { mkdtemp, readFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { SLACK_NUMBER_INDEX, SLACK_TAGS_DDL, SLACK_TASKS_DDL, dbPath, openDb } from "../src/slackdb.ts";

async function tmpFile(): Promise<string> {
  return join(await mkdtemp(join(tmpdir(), "slackdb-")), "nested", "deeper", "slack-tasks.db");
}

const version = (db: DatabaseSync) => (db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
const columns = (db: DatabaseSync) => (db.prepare("PRAGMA table_info(tasks)").all() as { name: string }[]).map((c) => c.name);

const V1_DDL = `CREATE TABLE tasks (
  channel_id TEXT NOT NULL, thread_ts TEXT NOT NULL, permalink TEXT NOT NULL, channel_name TEXT, snippet TEXT,
  replies INTEGER, replies_at_tag INTEGER, last_reply TEXT, tagged TEXT NOT NULL, synced TEXT,
  status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','inprogress','blocked','done')),
  archived INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel_id, thread_ts))`;
const V3_DDL = `CREATE TABLE tasks (
  tag TEXT NOT NULL, channel_id TEXT NOT NULL, thread_ts TEXT NOT NULL, permalink TEXT NOT NULL, channel_name TEXT, snippet TEXT,
  replies INTEGER, replies_at_tag INTEGER, last_reply TEXT, tagged TEXT NOT NULL, synced TEXT, summary TEXT, next_action TEXT, summary_replies INTEGER,
  status TEXT NOT NULL DEFAULT '', archived INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (tag, channel_id, thread_ts))`;
const V2_DDL = V1_DDL.replace("synced TEXT,", "synced TEXT, summary TEXT, next_action TEXT, summary_replies INTEGER,");

function oldFile(file: string, ddl: string, userVersion: number, rows: string[]): void {
  mkdirSync(dirname(file), { recursive: true });
  const old = new DatabaseSync(file);
  old.exec(ddl);
  for (const row of rows) old.exec(row);
  old.exec(`PRAGMA user_version = ${userVersion}`);
  old.close();
}

test("openDb creates the missing parent folder and the file", async () => {
  const file = await tmpFile();
  openDb(file).close();
  assert.ok((await stat(file)).isFile());
});

test("openDb sets user_version 4 and WAL mode", async () => {
  const db = openDb(await tmpFile());
  assert.equal(version(db), 4);
  assert.equal((db.prepare("PRAGMA journal_mode").get() as { journal_mode: string }).journal_mode, "wal");
  db.close();
});

test("a fresh database has the two seeded tags", async () => {
  const db = openDb(await tmpFile());
  const tags = db.prepare("SELECT * FROM tags ORDER BY position").all().map((t) => ({ ...t }));
  assert.deepEqual(tags, [
    { id: "todo", name: "To-do", kind: "board", slack_list: "todo", reactions: '["loading","loading1"]', columns: '["Todo","In progress","Blocked","Done"]', position: 0, builtin: 1 },
    { id: "saved", name: "Saved", kind: "list", slack_list: "saved", reactions: "[]", columns: "[]", position: 1, builtin: 1 },
  ]);
  db.close();
});

test("opening the same file twice does not fail or duplicate the seeds", async () => {
  const file = await tmpFile();
  openDb(file).close();
  const db = openDb(file);
  assert.equal((db.prepare("SELECT COUNT(*) n FROM tags").get() as { n: number }).n, 2);
  db.close();
});

test("a tag with a kind or slack_list outside the allowed values is rejected", async () => {
  const db = openDb(await tmpFile());
  assert.throws(() => db.prepare("INSERT INTO tags (id, name, kind, position) VALUES ('x','X','weird',9)").run());
  assert.throws(() => db.prepare("INSERT INTO tags (id, name, kind, slack_list, position) VALUES ('x','X','board','weird',9)").run());
  db.close();
});

test("task status is free text and a minimal row defaults to an empty status and not archived", async () => {
  const db = openDb(await tmpFile());
  db.prepare("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged) VALUES ('todo','C','1.1','p','2026-11-15')").run();
  db.prepare("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged, status) VALUES ('todo','C','2.2','p','2026-11-15','Waiting on vendor')").run();
  const rows = db.prepare("SELECT status, archived FROM tasks ORDER BY thread_ts").all().map((r) => ({ ...r }));
  assert.deepEqual(rows, [{ status: "", archived: 0 }, { status: "Waiting on vendor", archived: 0 }]);
  db.close();
});

test("the same thread can exist once per tag", async () => {
  const db = openDb(await tmpFile());
  const insert = db.prepare("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged) VALUES (?,?,?,?,?)");
  insert.run("todo", "C", "1.1", "p", "2026-11-15");
  insert.run("saved", "C", "1.1", "p", "2026-11-15");
  assert.throws(() => insert.run("todo", "C", "1.1", "p", "2026-11-15"));
  db.close();
});

test("openDb upgrades a v2 database with cards into the todo tag", async () => {
  const file = await tmpFile();
  oldFile(file, V2_DDL, 2, [
    "INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status, summary, summary_replies, replies) VALUES ('C','1.1','p','2026-11-15','blocked','Waiting on vendor.',2,2)",
    "INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status, archived) VALUES ('C','2.2','p','2026-11-15','done',1)",
    "INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status) VALUES ('C','3.3','p','2026-11-15','inprogress')",
  ]);
  const db = openDb(file);
  const rows = db.prepare("SELECT tag, thread_ts, status, archived, summary FROM tasks ORDER BY thread_ts").all().map((r) => ({ ...r }));
  assert.deepEqual(rows, [
    { tag: "todo", thread_ts: "1.1", status: "Blocked", archived: 0, summary: "Waiting on vendor." },
    { tag: "todo", thread_ts: "2.2", status: "Done", archived: 1, summary: null },
    { tag: "todo", thread_ts: "3.3", status: "In progress", archived: 0, summary: null },
  ]);
  assert.equal(version(db), 4);
  assert.equal((db.prepare("SELECT COUNT(*) n FROM tags").get() as { n: number }).n, 2);
  db.close();
});

test("openDb upgrades a v1 database through v2 to v3 and keeps its rows", async () => {
  const file = await tmpFile();
  oldFile(file, V1_DDL, 1, ["INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status) VALUES ('C','1.1','p','2026-11-15','blocked')"]);
  const db = openDb(file);
  for (const name of ["tag", "summary", "next_action", "summary_replies"]) assert.ok(columns(db).includes(name), name);
  const row = db.prepare("SELECT tag, status FROM tasks").get() as { tag: string; status: string };
  assert.deepEqual({ ...row }, { tag: "todo", status: "Blocked" });
  assert.equal(version(db), 4);
  db.close();
  openDb(file).close();
});

test("two opens on one old file at the same time both succeed", async () => {
  const file = await tmpFile();
  oldFile(file, V2_DDL, 2, ["INSERT INTO tasks (channel_id, thread_ts, permalink, tagged) VALUES ('C','1.1','p','2026-11-15')"]);
  const a = openDb(file);
  const b = openDb(file);
  assert.equal((a.prepare("SELECT COUNT(*) n FROM tasks").get() as { n: number }).n, 1);
  assert.equal(version(b), 4);
  a.close();
  b.close();
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

test("Swift and TypeScript DDL are identical for both tables", async () => {
  const swift = await readFile(join(import.meta.dirname, "..", "..", "Sources", "StudioCore", "SlackTaskStore.swift"), "utf8");
  const normalize = (text: string) => text.replace(/\s+/g, " ").trim();
  for (const [name, ts] of [["tagsDDL", SLACK_TAGS_DDL], ["tasksDDL", SLACK_TASKS_DDL]] as const) {
    const match = new RegExp(`static let ${name} = """\\n([\\s\\S]*?)"""`).exec(swift);
    assert.ok(match, `SlackTaskStore.swift must define static let ${name}`);
    assert.equal(normalize(match[1]), normalize(ts), name);
  }
});

test("a fresh database has a number column and a unique index on it", async () => {
  const db = openDb(await tmpFile());
  assert.ok(columns(db).includes("number"));
  const insert = db.prepare("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged, number) VALUES ('todo','C',?,'p','2026-11-15',?)");
  insert.run("1.1", 7);
  assert.throws(() => insert.run("2.2", 7));
  insert.run("3.3", null);
  insert.run("4.4", null);
  db.close();
});

test("openDb upgrades a v3 database and numbers the cards by tagged date then row order", async () => {
  const file = await tmpFile();
  oldFile(file, V3_DDL, 3, [
    "INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged, status) VALUES ('todo','C','3.3','p','2026-11-16','Blocked')",
    "INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged, status) VALUES ('todo','C','1.1','p','2026-11-14','Done')",
    "INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged, status) VALUES ('saved','C','1.1','p','2026-11-14','')",
  ]);
  const db = openDb(file);
  const rows = db.prepare("SELECT tag, thread_ts, status, number FROM tasks ORDER BY number").all().map((r) => ({ ...r }));
  assert.deepEqual(rows, [
    { tag: "todo", thread_ts: "1.1", status: "Done", number: 1 },
    { tag: "saved", thread_ts: "1.1", status: "", number: 2 },
    { tag: "todo", thread_ts: "3.3", status: "Blocked", number: 3 },
  ]);
  assert.equal(version(db), 4);
  db.close();
  openDb(file).close();
});

test("the number index DDL matches the Swift text", async () => {
  const swift = await readFile(join(import.meta.dirname, "..", "..", "Sources", "StudioCore", "SlackTaskStore.swift"), "utf8");
  const match = /static let numberIndexDDL = """\n([\s\S]*?)"""/.exec(swift);
  assert.ok(match, "SlackTaskStore.swift must define static let numberIndexDDL");
  assert.equal(match[1].replace(/\s+/g, " ").trim(), SLACK_NUMBER_INDEX.replace(/\s+/g, " ").trim());
});

test("openDb numbers cards an older build left without a number, after the highest existing one", async () => {
  const file = await tmpFile();
  openDb(file).close();
  const raw = new DatabaseSync(file);
  raw.exec("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged) VALUES ('todo','C','1.1','p','2026-11-15')");
  raw.exec("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged, number) VALUES ('todo','C','2.2','p','2026-11-15', 7)");
  raw.close();
  const db = openDb(file);
  const rows = db.prepare("SELECT thread_ts, number FROM tasks ORDER BY thread_ts").all().map((r) => ({ ...r }));
  assert.deepEqual(rows, [{ thread_ts: "1.1", number: 8 }, { thread_ts: "2.2", number: 7 }]);
  db.close();
});
