import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { openDb } from "../src/slackdb.ts";
import { upsertSlackTask, type UpsertInput } from "../src/slacktasks.ts";

const NOW = new Date("2026-11-15T10:00:00Z");
const BASE: UpsertInput = {
  tag: "todo",
  channel_id: "C07R08WFC81",
  message_ts: "1794536057.965929",
  permalink: "https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929",
  channel_name: "agent-network-eng",
  snippet: "Store internal_account_number from create product go-customer to poket_bank_accounts table.",
  replies: 0,
  last_reply: "1794536057.965929",
};
const ROOT_LINK = BASE.permalink;

async function fresh(): Promise<{ db: DatabaseSync; file: string }> {
  const file = join(await mkdtemp(join(tmpdir(), "slacktasks-")), "t.db");
  return { db: openDb(file), file };
}
const rows = (db: DatabaseSync) => db.prepare("SELECT * FROM tasks").all().map((r) => ({ ...r })) as Record<string, unknown>[];

test("creates a card", async () => {
  const { db } = await fresh();
  const r = upsertSlackTask(db, BASE, NOW);
  assert.equal(r.action, "created");
  const [row] = rows(db);
  assert.equal(row.thread_ts, "1794536057.965929");
  assert.equal(row.status, "Todo");
  assert.equal(row.tag, "todo");
  assert.equal(row.archived, 0);
  assert.equal(row.tagged, "2026-11-15");
  assert.equal(row.replies_at_tag, 0);
  assert.equal(row.last_reply, "2026-11-13T02:14:17Z");
  assert.ok(row.synced);
});

test("updates facts but keeps status and replies_at_tag", async () => {
  const { db, file } = await fresh();
  upsertSlackTask(db, BASE, NOW);
  const other = new DatabaseSync(file);
  other.exec("UPDATE tasks SET status = 'blocked'");
  other.close();
  const r = upsertSlackTask(db, { ...BASE, replies: 3 }, new Date("2026-11-16T10:00:00Z"));
  assert.equal(r.action, "updated");
  const [row] = rows(db);
  assert.equal(row.replies, 3);
  assert.equal(row.replies_at_tag, 0);
  assert.equal(row.status, "blocked");
  assert.equal(row.tagged, "2026-11-15");
});

test("skips archived rows", async () => {
  const { db } = await fresh();
  upsertSlackTask(db, BASE, NOW);
  db.exec("UPDATE tasks SET archived = 1");
  const r = upsertSlackTask(db, { ...BASE, replies: 9 }, NOW);
  assert.equal(r.action, "archived");
  assert.equal(rows(db)[0].replies, 0);
});

test("a reply hit keys to the thread root", async () => {
  const { db } = await fresh();
  upsertSlackTask(db, {
    ...BASE,
    message_ts: "1794540000.000100",
    permalink: "https://amartha.slack.com/archives/C07R08WFC81/p1794540000000100?thread_ts=1794536057.965929&cid=C07R08WFC81",
  }, NOW);
  const all = rows(db);
  assert.equal(all.length, 1);
  assert.equal(all[0].thread_ts, "1794536057.965929");
  assert.equal(all[0].permalink, ROOT_LINK);
});

test("an explicit thread_ts wins over the permalink query", async () => {
  const { db } = await fresh();
  upsertSlackTask(db, {
    ...BASE,
    message_ts: "1794540000.000100",
    thread_ts: "1794530000.000001",
    permalink: "https://amartha.slack.com/archives/C07R08WFC81/p1794540000000100?thread_ts=1794536057.965929",
  }, NOW);
  assert.equal(rows(db)[0].thread_ts, "1794530000.000001");
  assert.equal(rows(db)[0].permalink, "https://amartha.slack.com/archives/C07R08WFC81/p1794530000000001");
});

test("a board-added row keyed by a reply ts is re-keyed to the root", async () => {
  const { db } = await fresh();
  db.prepare("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged) VALUES ('todo',?,?,?,?)")
    .run("C07R08WFC81", "1794540000.000100", "https://amartha.slack.com/archives/C07R08WFC81/p1794540000000100", "2026-11-14");
  db.exec("UPDATE tasks SET status = 'inprogress'");
  upsertSlackTask(db, { ...BASE, message_ts: "1794540000.000100", thread_ts: "1794536057.965929", replies: 4 }, NOW);
  const all = rows(db);
  assert.equal(all.length, 1);
  assert.equal(all[0].thread_ts, "1794536057.965929");
  assert.equal(all[0].replies_at_tag, 4);
  assert.equal(all[0].status, "inprogress");
  assert.equal(all[0].tagged, "2026-11-14");
});

test("fills a NULL replies_at_tag on a root-keyed board-added row", async () => {
  const { db } = await fresh();
  db.prepare("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged) VALUES ('todo',?,?,?,?)")
    .run("C07R08WFC81", "1794536057.965929", ROOT_LINK, "2026-11-14");
  const r = upsertSlackTask(db, { ...BASE, replies: 2 }, NOW);
  assert.equal(r.action, "updated");
  assert.equal(rows(db)[0].replies_at_tag, 2);
});

test("rejects bad input and writes nothing", async () => {
  const { db } = await fresh();
  for (const bad of [{ replies: -1 }, { replies: 1.5 }, { channel_id: "" }, { last_reply: "garbage" }]) {
    assert.throws(() => upsertSlackTask(db, { ...BASE, ...bad }, NOW), Error);
  }
  assert.equal(rows(db).length, 0);
});

test("stores snippets verbatim", async () => {
  const { db } = await fresh();
  const snippet = "it's \"quoted\"; '); DROP TABLE tasks;-- 🚀";
  upsertSlackTask(db, { ...BASE, snippet }, NOW);
  assert.equal(rows(db)[0].snippet, snippet);
});

test("rejects malformed or empty thread and message timestamps and writes nothing", async () => {
  const { db } = await fresh();
  const bad: Partial<UpsertInput>[] = [
    { thread_ts: "" },
    { thread_ts: "abc" },
    { message_ts: "abc" },
    { permalink: "https://amartha.slack.com/archives/C07R08WFC81/p1794540000000100?thread_ts=junk" },
  ];
  for (const b of bad) assert.throws(() => upsertSlackTask(db, { ...BASE, ...b }, NOW), Error);
  assert.equal(rows(db).length, 0);
});

test("last_reply accepts a Slack ts, an integer ts and ISO with a zone, and rejects the rest", async () => {
  const lastReply = async (value: string) => {
    const { db } = await fresh();
    upsertSlackTask(db, { ...BASE, last_reply: value }, NOW);
    return rows(db)[0].last_reply;
  };
  assert.equal(await lastReply("1794536057"), "2026-11-13T02:14:17Z");
  assert.equal(await lastReply("2026-11-15T10:00:00+07:00"), "2026-11-15T03:00:00Z");
  assert.equal(await lastReply("2026-11-15T10:00:00Z"), "2026-11-15T10:00:00Z");
  const { db } = await fresh();
  for (const bad of ["5", "2026-11-15T10:00:00", "2026-11-15", "yesterday"]) {
    assert.throws(() => upsertSlackTask(db, { ...BASE, last_reply: bad }, NOW), Error, bad);
  }
  assert.equal(rows(db).length, 0);
});

const SUMMARY = { summary: "Vendor confirmed the retry window; fix in review.", next_action: "Check the fix PR and reply to Nafis" };

test("without a summary the result is stale", async () => {
  const { db } = await fresh();
  assert.equal(upsertSlackTask(db, BASE, NOW).summary_stale, true);
});

test("with a summary it is current and the row holds both texts", async () => {
  const { db } = await fresh();
  const r = upsertSlackTask(db, { ...BASE, ...SUMMARY }, NOW);
  assert.equal(r.summary_stale, false);
  const [row] = rows(db);
  assert.equal(row.summary, SUMMARY.summary);
  assert.equal(row.next_action, SUMMARY.next_action);
  assert.equal(row.summary_replies, 0);
});

test("new replies make it stale but keep the old text", async () => {
  const { db } = await fresh();
  upsertSlackTask(db, { ...BASE, ...SUMMARY }, NOW);
  const r = upsertSlackTask(db, { ...BASE, replies: 3 }, NOW);
  assert.equal(r.summary_stale, true);
  const [row] = rows(db);
  assert.equal(row.summary, SUMMARY.summary);
  assert.equal(row.summary_replies, 0);
});

test("a second call with the same replies stays current", async () => {
  const { db } = await fresh();
  upsertSlackTask(db, { ...BASE, ...SUMMARY }, NOW);
  assert.equal(upsertSlackTask(db, BASE, NOW).summary_stale, false);
});

test("a summary without a next action stores NULL for it", async () => {
  const { db } = await fresh();
  upsertSlackTask(db, { ...BASE, summary: "Done and dusted." }, NOW);
  assert.equal(rows(db)[0].next_action, null);
});

test("rejects a next action without a summary, over-long or empty texts, and writes nothing", async () => {
  const { db } = await fresh();
  const bad: Partial<UpsertInput>[] = [
    { next_action: "Do it" },
    { summary: "x".repeat(301) },
    { summary: "ok", next_action: "y".repeat(201) },
    { summary: "" },
    { summary: "ok", next_action: "" },
  ];
  for (const b of bad) assert.throws(() => upsertSlackTask(db, { ...BASE, ...b }, NOW), Error);
  assert.equal(rows(db).length, 0);
});

test("an archived row reports summary_stale false and writes nothing", async () => {
  const { db } = await fresh();
  upsertSlackTask(db, BASE, NOW);
  db.exec("UPDATE tasks SET archived = 1");
  const r = upsertSlackTask(db, { ...BASE, ...SUMMARY }, NOW);
  assert.equal(r.action, "archived");
  assert.equal(r.summary_stale, false);
  assert.equal(rows(db)[0].summary, null);
});

function addTag(db: DatabaseSync, id: string, kind: string, columns: string[], slackList = "none"): void {
  db.prepare("INSERT INTO tags (id, name, kind, slack_list, reactions, columns, position) VALUES (?,?,?,?,?,?,9)")
    .run(id, id, kind, slackList, "[]", JSON.stringify(columns));
}

test("the same thread under two tags is two independent cards", async () => {
  const { db } = await fresh();
  upsertSlackTask(db, BASE, NOW);
  upsertSlackTask(db, { ...BASE, tag: "saved" }, NOW);
  assert.equal(rows(db).length, 2);
  db.exec("UPDATE tasks SET status = 'Blocked' WHERE tag = 'todo'");
  db.exec("UPDATE tasks SET archived = 1 WHERE tag = 'saved'");
  assert.equal(upsertSlackTask(db, { ...BASE, replies: 4 }, NOW).action, "updated");
  assert.equal(upsertSlackTask(db, { ...BASE, tag: "saved", replies: 4 }, NOW).action, "archived");
  const byTag = Object.fromEntries(rows(db).map((r) => [r.tag as string, r]));
  assert.equal(byTag.todo.status, "Blocked");
  assert.equal(byTag.todo.replies, 4);
  assert.equal(byTag.saved.replies, 0);
});

test("an unknown tag throws and writes nothing", async () => {
  const { db } = await fresh();
  assert.throws(() => upsertSlackTask(db, { ...BASE, tag: "nope" }, NOW), /nope/);
  assert.equal(rows(db).length, 0);
});

test("a list tag stores NULL replies when omitted, an empty status, and is stale until summarized", async () => {
  const { db } = await fresh();
  const { replies: _omitted, ...noReplies } = BASE;
  const first = upsertSlackTask(db, { ...noReplies, tag: "saved" }, NOW);
  assert.equal(first.summary_stale, true);
  const [row] = rows(db);
  assert.equal(row.replies, null);
  assert.equal(row.replies_at_tag, null);
  assert.equal(row.status, "");
  const done = upsertSlackTask(db, { ...noReplies, tag: "saved", summary: "A saved note." }, NOW);
  assert.equal(done.summary_stale, false);
  assert.equal(upsertSlackTask(db, { ...noReplies, tag: "saved" }, NOW).summary_stale, false);
});

test("next_action on a list tag is rejected and writes nothing", async () => {
  const { db } = await fresh();
  assert.throws(() => upsertSlackTask(db, { ...BASE, tag: "saved", summary: "S", next_action: "N" }, NOW), /list/);
  assert.equal(rows(db).length, 0);
});

test("a board tag without replies is rejected", async () => {
  const { db } = await fresh();
  const { replies: _omitted, ...noReplies } = BASE;
  assert.throws(() => upsertSlackTask(db, noReplies, NOW), /replies/);
  assert.equal(rows(db).length, 0);
});

test("a new card takes the first column of a custom tag", async () => {
  const { db } = await fresh();
  addTag(db, "review", "board", ["Open", "Done"]);
  upsertSlackTask(db, { ...BASE, tag: "review" }, NOW);
  assert.equal(rows(db)[0].status, "Open");
});
