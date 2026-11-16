import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";

export const SLACK_TAGS_DDL = `CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('board','list')),
  slack_list TEXT NOT NULL DEFAULT 'none' CHECK (slack_list IN ('none','todo','saved')),
  reactions TEXT NOT NULL DEFAULT '[]',
  columns TEXT NOT NULL DEFAULT '[]',
  position INTEGER NOT NULL,
  builtin INTEGER NOT NULL DEFAULT 0
)`;

export const SLACK_TASKS_DDL = `CREATE TABLE IF NOT EXISTS tasks (
  tag TEXT NOT NULL,
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
  status TEXT NOT NULL DEFAULT '',
  archived INTEGER NOT NULL DEFAULT 0,
  number INTEGER,
  PRIMARY KEY (tag, channel_id, thread_ts)
)`;

export const SLACK_NUMBER_INDEX = `CREATE UNIQUE INDEX IF NOT EXISTS tasks_number ON tasks(number)`;

/** The columns every board tag shares; the last one counts as done. */
export const STANDARD_COLUMNS = ["Todo", "In progress", "Blocked", "Done"];

const CANONICAL: Record<string, string> = { todo: "Todo", inprogress: "In progress", blocked: "Blocked", done: "Done" };

function canonicalStatus(status: string): string {
  return CANONICAL[status.toLowerCase().replace(/[\s-]/g, "")] ?? STANDARD_COLUMNS[0];
}

const SUMMARY_COLUMNS: [string, string][] = [["summary", "TEXT"], ["next_action", "TEXT"], ["summary_replies", "INTEGER"]];
const COPIED = "channel_id, thread_ts, permalink, channel_name, snippet, replies, replies_at_tag, last_reply, tagged, synced, summary, next_action, summary_replies, archived";

/** Gives every card without a number the next one, oldest tagged first. Call inside a transaction. */
function assignMissingNumbers(db: DatabaseSync): void {
  const unnumbered = db.prepare("SELECT rowid AS id FROM tasks WHERE number IS NULL ORDER BY tagged, rowid").all() as { id: number }[];
  let next = (db.prepare("SELECT COALESCE(MAX(number), 0) AS n FROM tasks").get() as { n: number }).n;
  for (const { id } of unnumbered) db.prepare("UPDATE tasks SET number = ? WHERE rowid = ?").run(++next, id);
}

/** Cards written by an older build or an older running server have no number; number them on every open. */
function ensureNumbers(db: DatabaseSync): void {
  if (!db.prepare("SELECT 1 AS x FROM tasks WHERE number IS NULL LIMIT 1").get()) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    assignMissingNumbers(db);
    db.exec("COMMIT");
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

function upgrade(db: DatabaseSync): void {
  const version = (db.prepare("PRAGMA user_version").get() as { user_version: number }).user_version;
  if (version >= 5) return;
  db.exec("BEGIN IMMEDIATE");
  try {
    const names = () => new Set((db.prepare("PRAGMA table_info(tasks)").all() as { name: string }[]).map((c) => c.name));
    if (!names().has("tag")) {
      for (const [name, type] of SUMMARY_COLUMNS) if (!names().has(name)) db.exec(`ALTER TABLE tasks ADD COLUMN ${name} ${type}`);
      db.exec(SLACK_TASKS_DDL.replace("EXISTS tasks (", "EXISTS tasks_v3 ("));
      db.exec(`INSERT INTO tasks_v3 (tag, ${COPIED}, status)
               SELECT 'todo', ${COPIED},
                      CASE status WHEN 'todo' THEN 'Todo' WHEN 'inprogress' THEN 'In progress' WHEN 'blocked' THEN 'Blocked' WHEN 'done' THEN 'Done' ELSE status END
               FROM tasks`);
      db.exec("DROP TABLE tasks");
      db.exec("ALTER TABLE tasks_v3 RENAME TO tasks");
    } else if (!names().has("number")) {
      db.exec("ALTER TABLE tasks ADD COLUMN number INTEGER");
    }
    if ((db.prepare("SELECT COUNT(*) AS n FROM tags").get() as { n: number }).n === 0) {
      db.exec(`INSERT INTO tags (id, name, kind, slack_list, reactions, columns, position, builtin) VALUES
        ('todo', 'To-do', 'board', 'todo', '["loading","loading1"]', '["Todo","In progress","Blocked","Done"]', 0, 1),
        ('saved', 'Saved', 'list', 'saved', '[]', '[]', 1, 1)`);
    }
    assignMissingNumbers(db);
    db.exec(SLACK_NUMBER_INDEX);
    const standard = JSON.stringify(STANDARD_COLUMNS);
    for (const { id } of db.prepare("SELECT id FROM tags WHERE kind = 'board'").all() as { id: string }[]) {
      db.prepare("UPDATE tags SET columns = ? WHERE id = ?").run(standard, id);
      for (const card of db.prepare("SELECT rowid AS rid, status FROM tasks WHERE tag = ?").all(id) as { rid: number; status: string }[]) {
        const next = canonicalStatus(card.status);
        if (next !== card.status) db.prepare("UPDATE tasks SET status = ? WHERE rowid = ?").run(next, card.rid);
      }
    }
    db.exec("PRAGMA user_version = 5");
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
  db.exec(SLACK_TAGS_DDL);
  db.exec(SLACK_TASKS_DDL);
  upgrade(db);
  ensureNumbers(db);
  return db;
}
