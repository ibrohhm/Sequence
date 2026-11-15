import type { DatabaseSync } from "node:sqlite";

export type UpsertInput = {
  channel_id: string;
  message_ts: string;
  thread_ts?: string;
  permalink: string;
  channel_name: string;
  snippet: string;
  replies: number;
  last_reply: string;
};

export type UpsertResult = { action: "created" | "updated" | "archived"; channel_id: string; thread_ts: string };

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
  for (const key of ["channel_id", "message_ts", "permalink", "channel_name"] as const) {
    if (typeof input[key] !== "string" || input[key].trim() === "") throw new Error(`${key} must be a non-empty string`);
  }
  if (!SLACK_TS.test(input.message_ts)) throw new Error(`message_ts must look like 1794536057.965929: ${input.message_ts}`);
  if (typeof input.snippet !== "string") throw new Error("snippet must be a string");
  if (!Number.isInteger(input.replies) || input.replies < 0) throw new Error("replies must be a non-negative integer");
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
  const result = (action: UpsertResult["action"], ts: string): UpsertResult => ({ action, channel_id: channel, thread_ts: ts });

  db.exec("BEGIN IMMEDIATE");
  try {
    const find = (ts: string) => db.prepare("SELECT archived FROM tasks WHERE channel_id = ? AND thread_ts = ?").get(channel, ts) as Row;
    let row = find(threadTs);
    if (!row && input.message_ts !== threadTs) {
      const alt = find(input.message_ts);
      if (alt?.archived) {
        db.exec("COMMIT");
        return result("archived", input.message_ts);
      }
      if (alt) {
        db.prepare("UPDATE tasks SET thread_ts = ? WHERE channel_id = ? AND thread_ts = ?").run(threadTs, channel, input.message_ts);
        row = alt;
      }
    }
    if (row?.archived) {
      db.exec("COMMIT");
      return result("archived", threadTs);
    }
    if (row) {
      db.prepare(`UPDATE tasks SET permalink = ?, channel_name = ?, snippet = ?, replies = ?, last_reply = ?, synced = ?,
                  replies_at_tag = COALESCE(replies_at_tag, ?) WHERE channel_id = ? AND thread_ts = ?`)
        .run(root, input.channel_name, input.snippet, input.replies, lastReply, synced, input.replies, channel, threadTs);
      db.exec("COMMIT");
      return result("updated", threadTs);
    }
    db.prepare(`INSERT INTO tasks (channel_id, thread_ts, permalink, channel_name, snippet, replies, replies_at_tag, last_reply, tagged, synced)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(channel, threadTs, root, input.channel_name, input.snippet, input.replies, input.replies, lastReply, iso(now).slice(0, 10), synced);
    db.exec("COMMIT");
    return result("created", threadTs);
  } catch (e) {
    db.exec("ROLLBACK");
    throw e;
  }
}
