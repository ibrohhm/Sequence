import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";

export type Status = "todo" | "inprogress" | "blocked" | "done";

export const SLACK_TASKS_DDL = `CREATE TABLE IF NOT EXISTS tasks (
  channel_id TEXT NOT NULL,
  thread_ts TEXT NOT NULL,
  permalink TEXT NOT NULL,
  channel_name TEXT,
  snippet TEXT,
  replies INTEGER,
  replies_at_tag INTEGER,
  last_reply TEXT,
  tagged TEXT NOT NULL,
  synced TEXT,
  summary TEXT,
  next_action TEXT,
  summary_replies INTEGER,
  status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','inprogress','blocked','done')),
  archived INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (channel_id, thread_ts)
)`;

const SUMMARY_COLUMNS: [string, string][] = [["summary", "TEXT"], ["next_action", "TEXT"], ["summary_replies", "INTEGER"]];

function upgrade(db: DatabaseSync): void {
  const version = (db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
  if (version >= 2) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    const have = new Set((db.prepare("PRAGMA table_info(tasks)").all() as { name: string }[]).map((c) => c.name));
    for (const [name, type] of SUMMARY_COLUMNS) if (!have.has(name)) db.exec(`ALTER TABLE tasks ADD COLUMN ${name} ${type}`);
    db.exec("PRAGMA user_version = 2");
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

export function dbPath(): string {
  return process.env.SEQUENCE_SLACK_DB ?? join(homedir(), "Library", "Application Support", "Sequence", "slack-tasks.db");
}

export function openDb(file: string = dbPath()): DatabaseSync {
  mkdirSync(dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec("PRAGMA busy_timeout = 5000");
  db.exec("PRAGMA journal_mode = WAL");
  db.exec(SLACK_TASKS_DDL);
  upgrade(db);
  return db;
}
