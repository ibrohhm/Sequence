import type { DatabaseSync } from "node:sqlite";
import { getSlackTag } from "./slacktags.ts";

export type UpsertInput = {
  tag: string;
  channel_id: string;
  message_ts: string;
  thread_ts?: string;
  permalink: string;
  channel_name: string;
  snippet: string;
  replies?: number;
  last_reply: string;
  summary?: string;
  next_action?: string;
};

export type UpsertResult = { action: "created" | "updated" | "archived"; channel_id: string; thread_ts: string; summary_stale: boolean; number: number | null };

type Row = { archived: number } | undefined;

function iso(date: Date): string {
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}

const SLACK_TS = /^\d+\.\d+$/;
const ISO_WITH_ZONE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/;

function lastReplyIso(value: string): string {
  let date: Date;
  if (/^\d{9,}(\.\d+)?$/.test(value)) date = new Date(Math.floor(Number(value)) * 1000);
  else if (ISO_WITH_ZONE.test(value)) date = new Date(value);
  else throw new Error(`last_reply must be a Slack ts or an ISO time with a zone: ${value}`);
  if (Number.isNaN(date.getTime())) throw new Error(`last_reply is not a valid time: ${value}`);
  return iso(date);
}

function validate(input: UpsertInput): URL {
  for (const key of ["tag", "channel_id", "message_ts", "permalink", "channel_name"] as const) {
    if (typeof input[key] !== "string" || input[key].trim() === "") throw new Error(`${key} must be a non-empty string`);
  }
  if (!SLACK_TS.test(input.message_ts)) throw new Error(`message_ts must look like 1794536057.965929: ${input.message_ts}`);
  if (typeof input.snippet !== "string") throw new Error("snippet must be a string");
  if (input.replies !== undefined && (!Number.isInteger(input.replies) || input.replies < 0)) throw new Error("replies must be a non-negative integer");
  if (input.summary !== undefined && (typeof input.summary !== "string" || input.summary.trim() === "" || input.summary.length > 300)) {
    throw new Error("summary must be a non-empty string of at most 300 characters");
  }
  if (input.next_action !== undefined) {
    if (input.summary === undefined) throw new Error("next_action needs a summary");
    if (typeof input.next_action !== "string" || input.next_action.trim() === "" || input.next_action.length > 200) {
      throw new Error("next_action must be a non-empty string of at most 200 characters");
    }
  }
  try {
    return new URL(input.permalink);
  } catch {
    throw new Error(`permalink is not a valid URL: ${input.permalink}`);
  }
}

export function upsertSlackTask(db: DatabaseSync, input: UpsertInput, now: Date = new Date()): UpsertResult {
  const link = validate(input);
  const lastReply = lastReplyIso(input.last_reply);
  const threadTs = input.thread_ts !== undefined ? input.thread_ts : (link.searchParams.get("thread_ts") ?? input.message_ts);
  if (!SLACK_TS.test(threadTs)) throw new Error(`thread_ts must look like 1794536057.965929: ${threadTs}`);
  const root = `${link.origin}/archives/${input.channel_id}/p${threadTs.replace(".", "")}`;
  const channel = input.channel_id;
  const synced = iso(now);
  const result = (action: UpsertResult["action"], ts: string, stale = false): UpsertResult => ({ action, channel_id: channel, thread_ts: ts, summary_stale: stale, number: numberOf(ts) });
  const numberOf = (ts: string): number | null =>
    ((db.prepare("SELECT number FROM tasks WHERE tag = ? AND channel_id = ? AND thread_ts = ?").get(tagId, channel, ts) as { number: number | null } | undefined)?.number) ?? null;
  const tagId = input.tag;
  const staleSql = (list: boolean) =>
    `SELECT (${list ? "summary IS NULL" : "summary IS NULL OR summary_replies IS NOT replies"}) AS stale FROM tasks WHERE tag = ? AND channel_id = ? AND thread_ts = ?`;

  db.exec("BEGIN IMMEDIATE");
  try {
    const tag = getSlackTag(db, tagId);
    if (!tag) throw new Error(`Unknown tag "${tagId}"`);
    const isList = tag.kind === "list";
    if (isList && input.next_action !== undefined) throw new Error("next_action is not used on list tags");
    if (!isList && input.replies === undefined) throw new Error("replies is required for a board tag");
    const replies = input.replies ?? null;
    const nextNumber = () => (db.prepare("SELECT COALESCE(MAX(number), 0) + 1 AS n FROM tasks").get() as { n: number }).n;
    const stale = (ts: string) => (db.prepare(staleSql(isList)).get(tagId, channel, ts) as { stale: number }).stale === 1;
    const find = (ts: string) => db.prepare("SELECT archived FROM tasks WHERE tag = ? AND channel_id = ? AND thread_ts = ?").get(tagId, channel, ts) as Row;
    let row = find(threadTs);
    if (!row && input.message_ts !== threadTs) {
      const alt = find(input.message_ts);
      if (alt?.archived) {
        db.exec("COMMIT");
        return result("archived", input.message_ts);
      }
      if (alt) {
        db.prepare("UPDATE tasks SET thread_ts = ? WHERE tag = ? AND channel_id = ? AND thread_ts = ?").run(threadTs, tagId, channel, input.message_ts);
        row = alt;
      }
    }
    if (row?.archived) {
      db.exec("COMMIT");
      return result("archived", threadTs);
    }
    if (row) {
      const withSummary = input.summary !== undefined;
      db.prepare(`UPDATE tasks SET permalink = ?, channel_name = ?, snippet = ?, replies = ?, last_reply = ?, synced = ?,
                  replies_at_tag = COALESCE(replies_at_tag, ?), number = COALESCE(number, ?)${withSummary ? ", summary = ?, next_action = ?, summary_replies = ?" : ""}
                  WHERE tag = ? AND channel_id = ? AND thread_ts = ?`)
        .run(root, input.channel_name, input.snippet, replies, lastReply, synced, replies, nextNumber(),
          ...(withSummary ? [input.summary!, input.next_action ?? null, replies] : []), tagId, channel, threadTs);
      const isStale = stale(threadTs);
      db.exec("COMMIT");
      return result("updated", threadTs, isStale);
    }
    db.prepare(`INSERT INTO tasks (tag, channel_id, thread_ts, permalink, channel_name, snippet, replies, replies_at_tag, last_reply, tagged, synced,
                                   summary, next_action, summary_replies, status, number)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(tagId, channel, threadTs, root, input.channel_name, input.snippet, replies, replies, lastReply, iso(now).slice(0, 10), synced,
        input.summary ?? null, input.summary !== undefined ? (input.next_action ?? null) : null, input.summary !== undefined ? replies : null,
        isList ? "" : (tag.columns[0] ?? ""), nextNumber());
    const isStale = stale(threadTs);
    db.exec("COMMIT");
    return result("created", threadTs, isStale);
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}

export type SlackTaskRow = {
  number: number;
  tag: string;
  tag_name: string | null;
  status: string;
  archived: boolean;
  channel_id: string;
  channel_name: string | null;
  thread_ts: string;
  permalink: string;
  snippet: string | null;
  summary: string | null;
  next_action: string | null;
  replies: number | null;
  replies_at_tag: number | null;
  last_reply: string | null;
  tagged: string;
  synced: string | null;
};

export function getSlackTask(db: DatabaseSync, number: number): SlackTaskRow | undefined {
  const row = db.prepare(`SELECT t.number, t.tag, tags.name AS tag_name, t.status, t.archived, t.channel_id, t.channel_name, t.thread_ts, t.permalink,
                                 t.snippet, t.summary, t.next_action, t.replies, t.replies_at_tag, t.last_reply, t.tagged, t.synced
                          FROM tasks t LEFT JOIN tags ON tags.id = t.tag WHERE t.number = ?`).get(number) as (Omit<SlackTaskRow, "archived"> & { archived: number }) | undefined;
  return row && { ...row, archived: row.archived !== 0 };
}
