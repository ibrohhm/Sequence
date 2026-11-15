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
  status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','inprogress','blocked','done')),
  archived INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (channel_id, thread_ts)
)`;

export function dbPath(): string {
  return process.env.SEQUENCE_SLACK_DB ?? join(homedir(), "Library", "Application Support", "Sequence", "slack-tasks.db");
}

export function openDb(file: string = dbPath()): DatabaseSync {
  mkdirSync(dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec("PRAGMA busy_timeout = 5000");
  db.exec("PRAGMA journal_mode = WAL");
  db.exec(SLACK_TASKS_DDL);
  db.exec("PRAGMA user_version = 1");
  return db;
}
