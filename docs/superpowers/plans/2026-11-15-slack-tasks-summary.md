# Slack Tasks Summary and Next Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cards show an agent-written summary and next action; the sync tool stores them and says when a summary is stale.

**Architecture:** Schema v2 adds three columns with an in-place upgrade in both the Node tool and the Swift store; `upsert_slack_task` accepts the new fields and returns `summary_stale`; the skill tells the agent when to write them; the board reads them.

**Tech Stack:** Node `node:sqlite` + TypeScript (`node --test`), Swift + system `SQLite3` (`./test.sh`).

**Spec:** `docs/superpowers/specs/2026-11-15-slack-tasks-design.md` (section "Addendum: summary and next action").

## Global Constraints

- New columns, in this order in the fresh-database DDL after `synced`: `summary TEXT`, `next_action TEXT`, `summary_replies INTEGER`; `PRAGMA user_version = 2`. The DDL text in `mcp/src/slackdb.ts` and `Sources/StudioCore/SlackTaskStore.swift` stays identical (the parity test in `mcp/test/slackdb.test.ts` checks it).
- Upgrade of a v1 file: inside `BEGIN IMMEDIATE`, for each of the three columns missing from `PRAGMA table_info(tasks)` run `ALTER TABLE tasks ADD COLUMN <name> <type>`, then `PRAGMA user_version = 2`; existing rows are untouched; running it twice or from two programs at once is safe.
- `summary`: non-empty string, at most 300 characters. `next_action`: non-empty string, at most 200 characters, accepted only together with `summary`.
- Writing a summary sets `summary`, `next_action` (NULL if omitted) and `summary_replies = replies`. Without `summary` the summary columns are never touched. `summary_stale` = `summary IS NULL OR summary_replies IS NOT replies` after the write; archived rows report false and write nothing.
- Sequence (Swift) never writes the summary columns. Status, archived, tagged behave as before.
- No `VERSION` bump or commit in this plan (the board work is uncommitted; the user commits on request).

## Review Focus

- A v1 database with rows and a status the user set is upgraded without losing either; opening it twice, or Node and Swift opening it back to back, does not fail (Tasks 1, 2).
- Replies grow after a summary exists: summary is kept, `summary_stale` is true (Task 1).
- Next action without summary, over-long text, empty strings: rejected and nothing written (Task 1).
- A card with a summary but no next action shows no empty arrow line (Task 2 view note).
- The real database is backed up before the new code first opens it (Task 3).

---

### Task 1: Node schema v2, upgrade and upsert

**Files:**
- Modify: `mcp/src/slackdb.ts`, `mcp/src/slacktasks.ts`, `mcp/src/server.ts`
- Test: `mcp/test/slackdb.test.ts`, `mcp/test/slacktasks.test.ts`, `mcp/test/server.test.ts`

**Interfaces:**
- Produces: `SLACK_TASKS_DDL` with the three new columns; `openDb` upgrades a v1 file and leaves `user_version = 2`; `UpsertInput` gains `summary?: string`, `next_action?: string`; `UpsertResult` gains `summary_stale: boolean`; tool schema gains optional `summary` (max 300) and `next_action` (max 200).

- [ ] **Step 1: Write failing tests.**
  - `slackdb.test.ts`: change the `user_version` expectation to 2; new `upgrades a v1 database in place`: create a file with the old v1 DDL (without the three columns), `user_version = 1`, one row with `status 'blocked'`; `openDb(file)` then the row still has `status 'blocked'`, the three columns exist, `user_version` is 2; opening again works.
  - `slacktasks.test.ts` (reuse `BASE`, `NOW`, `fresh`): `without a summary the result is stale`: result `summary_stale true`; `with a summary it is current`: input `summary "Vendor confirmed the retry window; fix in review."`, `next_action "Check the fix PR and reply to Nafis"` gives `summary_stale false` and the row has both texts and `summary_replies 0`; `new replies make it stale but keep the text`: summarize at `replies 0`, then upsert `replies 3` with no summary: `summary_stale true`, `summary` unchanged, `summary_replies 0`; `a second call with the same replies stays current`; `next_action without summary is rejected`; `summary over 300 characters and next_action over 200 are rejected`; `empty summary or empty next_action is rejected`; `an archived row reports summary_stale false and writes nothing` (even when a summary is passed).
  - `server.test.ts`: `upsert_slack_task reports summary_stale then accepts a summary`: first call returns `summary_stale true`, the second (same facts plus `summary`, `next_action`) returns `summary_stale false`.
- [ ] **Step 2: Run `cd mcp && npm test`.** Expected: the new and changed tests FAIL (columns and fields missing).
- [ ] **Step 3: Implement** the DDL change, the upgrade step in `openDb` (run only when `user_version < 2`, inside `BEGIN IMMEDIATE`, re-checking `table_info` inside the transaction), the validation, the summary write on both the insert and update paths, and `summary_stale` in every result; extend the zod schema in `server.ts`.
- [ ] **Step 4: Run `npm test`.** Expected: all PASS except the DDL parity test, which FAILS until Task 2 changes the Swift DDL.

### Task 2: Swift schema v2, store and board

**Files:**
- Modify: `Sources/StudioCore/SlackTask.swift`, `Sources/StudioCore/SlackTaskStore.swift`, `App/SlackTasksView.swift`, `CLAUDE.md`
- Test: `Tests/StudioCoreTests/SlackTaskStoreTests.swift`

**Interfaces:**
- Consumes: the Task 1 DDL text (copy it verbatim).
- Produces: `SlackTask` gains `summary: String?`, `nextAction: String?`, `summaryReplies: Int?` (last parameters of the public memberwise `init`, defaulting to `nil` so existing callers compile); `SlackTaskStore.ddl` equals the Node DDL; the store upgrades a v1 file and sets `user_version = 2`; `tasks()` fills the new fields.

- [ ] **Step 1: Write failing tests** in `SlackTaskStoreTests`: update the `user_version` expectation to `"2"`; `upgrades a v1 database in place`: create the file with raw SQL using the v1 DDL, `user_version = 1` and a row with `status 'blocked'`, open `SlackTaskStore(path:)`: `tasks()` returns the row with status `.blocked` and nil summary fields, `user_version` is 2, and a raw `UPDATE tasks SET summary = 'S', next_action = 'N', summary_replies = 3` then decodes as `summary "S"`, `nextAction "N"`, `summaryReplies 3`; opening a second time works.
- [ ] **Step 2: Run `./test.sh` and `cd mcp && npm test`.** Expected: the new Swift tests FAIL; the parity test still FAILS.
- [ ] **Step 3: Implement** the DDL text, the upgrade (same rule as Global Constraints), the fields and decoding. In `TaskCard`: show `task.summary ?? snippet` (up to 3 lines) and, only when `nextAction` is non-empty, a line `→ <next action>` in 12 pt medium secondary text; the archived list keeps using the first message. Update the `CLAUDE.md` board bullet with the summary and next-action lines.
- [ ] **Step 4: Run `./test.sh`, `cd mcp && npm test`, `swift build`.** Expected: all PASS (including the parity test), build completes.

### Task 3: Skill, backup, migration check, live check

**Files:**
- Modify: `mcp/skills/sync-slack-tasks/SKILL.md`

- [ ] **Step 1: Update `SKILL.md`:** after step 4 add: if the result has `"summary_stale": true`, read the whole thread text already fetched and write a summary (about 140 characters, where the thread stands now, in the thread's language) and a next action (about 100 characters: what the user should do or wait for; omit it if there is nothing to do), then call `upsert_slack_task` again with the same facts plus `summary` and `next_action`. The report gains "summarized N".
- [ ] **Step 2: Back up the real database** without opening it with new code: `sqlite3 ~/Library/Application\ Support/Sequence/slack-tasks.db ".backup ~/Library/Application\ Support/Sequence/slack-tasks.db.bak-2026-11-15"`; confirm the backup file exists and has the same row count.
- [ ] **Step 3: Migration check on a copy:** copy the backup to the scratchpad and run `openDb` from a one-off script on the copy; expected: columns present, row preserved, `user_version` 2. Do not open the real file with new code.
- [ ] **Step 4: Rebuild** `mcp/dist` (`npm test` does it) and `./build-app.sh`; report. Tell the user: restart the Claude session (new tool schema) and reopen Sequence; the real database is upgraded on the first open by either; then run "sync my Slack tasks" to see summaries. State that the card look and the agent's summary quality are unverified.
