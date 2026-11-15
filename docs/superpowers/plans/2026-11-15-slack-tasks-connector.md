# Slack Tasks Connector (Stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new `upsert_slack_task` tool in the existing `mcp/` server that writes Slack thread facts into a SQLite database, plus the agent instructions that sync `:loading:`-tagged threads into it.

**Architecture:** `mcp/src/slackdb.ts` opens the database and owns the schema; `mcp/src/slacktasks.ts` holds the upsert logic as a plain function over an open database; `server.ts` exposes it as a tool and opens/closes the database per call. The sync itself is an agent skill that fetches through the Workbench and calls the tool.

**Tech Stack:** Node v24 built-in `node:sqlite` (`DatabaseSync`), TypeScript, `zod`, `node --test`, the existing MCP SDK.

**Spec:** `docs/superpowers/specs/2026-11-15-slack-tasks-design.md` (this plan is Stage 1 only; the Swift board is a separate plan).

## Global Constraints

- Database file: `~/Library/Application Support/Sequence/slack-tasks.db`; env `SEQUENCE_SLACK_DB` overrides it. WAL mode, busy timeout 5000 ms, `PRAGMA user_version = 1`, `CREATE TABLE IF NOT EXISTS` on every open.
- Table `tasks` columns: `channel_id TEXT NOT NULL`, `thread_ts TEXT NOT NULL` (primary key together), `permalink TEXT NOT NULL`, `channel_name TEXT`, `snippet TEXT`, `replies INTEGER`, `replies_at_tag INTEGER`, `last_reply TEXT`, `tagged TEXT NOT NULL`, `synced TEXT`, `status TEXT NOT NULL DEFAULT 'todo'` with a CHECK for `todo`, `inprogress`, `blocked`, `done`, `archived INTEGER NOT NULL DEFAULT 0`.
- Upsert never changes `status`, `archived` or `tagged` of an existing row, and never touches an archived row; `replies_at_tag` is set only while NULL.
- Created rows: `status = todo`, `archived = 0`, `tagged` = today (`YYYY-MM-DD`), `replies_at_tag = replies`.
- Times stored as UTC ISO strings (`2026-11-13T02:14:17Z`); a Slack ts (`1794536057.965929`) is converted by the tool.
- Thread root: explicit `thread_ts`, else the `thread_ts` query parameter of `permalink`, else `message_ts`. Stored `permalink` is the root's, with no query string.
- Never write to Slack; never use the claude.ai Slack connector (it is signed in as a different person); the Workbench token stays in the user's Claude config.
- No `VERSION` bump (the app is unchanged). No commit steps: the user commits only on request.

## Review Focus

- A reply hit: permalink with `?thread_ts=…` keys the card to the thread root and stores the root permalink without the query (Task 2).
- Sequence changing `status` through a second connection between two upserts: the status survives (Task 2).
- A board-added row (facts NULL, keyed by a reply ts) met by sync: re-keyed to the root, `replies_at_tag` filled once (Task 2).
- Bad input (negative or fractional `replies`, empty `channel_id`, unparseable `last_reply`) is rejected and writes nothing (Task 2).
- Snippets with quotes, SQL text and emoji are stored verbatim (Task 2).
- Opening a database whose parent folder does not exist creates the folder (Task 1).

---

### Task 1: Database module

**Files:**
- Create: `mcp/src/slackdb.ts`
- Test: `mcp/test/slackdb.test.ts`

**Interfaces:**
- Produces:
  - `dbPath(): string`: `process.env.SEQUENCE_SLACK_DB` or the default path.
  - `openDb(file?: string): DatabaseSync`: creates the parent folder, opens, sets `journal_mode=WAL` and `busy_timeout=5000`, runs the schema, sets `user_version = 1`.
  - `SLACK_TASKS_DDL: string` (the `CREATE TABLE IF NOT EXISTS` text).
  - `type Status = "todo" | "inprogress" | "blocked" | "done"`.

- [ ] **Step 1: Write failing tests** in `slackdb.test.ts` (temp dir under `os.tmpdir()`): `openDb` creates a missing parent folder and the file; `PRAGMA user_version` is `1` and `PRAGMA journal_mode` is `wal`; opening twice does not fail; inserting a row with `status = 'weird'` throws; a row inserted with only `channel_id`, `thread_ts`, `permalink`, `tagged` gets `status = 'todo'` and `archived = 0`; `dbPath()` returns the env value when `SEQUENCE_SLACK_DB` is set and ends with `Application Support/Sequence/slack-tasks.db` when it is not (restore the env after).
- [ ] **Step 2: Run `cd mcp && npm test`.** Expected: FAIL, `slackdb.ts` not found.
- [ ] **Step 3: Implement `slackdb.ts` to the signatures above.**
- [ ] **Step 4: Run `npm test`.** Expected: all PASS.

### Task 2: Upsert logic

**Files:**
- Create: `mcp/src/slacktasks.ts`
- Test: `mcp/test/slacktasks.test.ts`

**Interfaces:**
- Consumes: `openDb`, `Status` from Task 1.
- Produces:
  - `type UpsertInput = { channel_id: string; message_ts: string; thread_ts?: string; permalink: string; channel_name: string; snippet: string; replies: number; last_reply: string }`
  - `type UpsertResult = { action: "created" | "updated" | "archived"; channel_id: string; thread_ts: string }`
  - `upsertSlackTask(db: DatabaseSync, input: UpsertInput, now?: Date): UpsertResult`: validates input (non-empty ids and strings; `replies` a non-negative integer; `last_reply` either a Slack ts `^\d+\.\d+$` or a parseable ISO string, stored as UTC ISO without milliseconds); throws `Error` with a clear message on bad input before writing; runs inside a single transaction.

- [ ] **Step 1: Write failing tests** (each uses a fresh temp database from `openDb`), with these exact values: base input `channel_id "C07R08WFC81"`, `message_ts "1794536057.965929"`, `permalink "https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929"`, `channel_name "agent-network-eng"`, `snippet "Store internal_account_number from create product go-customer to poket_bank_accounts table."`, `replies 0`, `last_reply "1794536057.965929"`, `now = 2026-11-15`.
  - `creates a card`: result `created`; row has `thread_ts "1794536057.965929"`, `status "todo"`, `archived 0`, `tagged "2026-11-15"`, `replies_at_tag 0`, `last_reply "2026-11-13T02:14:17Z"`, `synced` not null.
  - `updates facts but keeps status and replies_at_tag`: after the first call set `status = 'blocked'` through a second `DatabaseSync` connection to the same file; second call with `replies 3` returns `updated`; row has `replies 3`, `replies_at_tag 0`, `status "blocked"`, `tagged` unchanged.
  - `skips archived rows`: set `archived = 1`, call with `replies 9`: result `archived`, `replies` still `0`.
  - `reply hit keys to the root`: `message_ts "1794540000.000100"`, `permalink "https://amartha.slack.com/archives/C07R08WFC81/p1794540000000100?thread_ts=1794536057.965929&cid=C07R08WFC81"`: one row, `thread_ts "1794536057.965929"`, `permalink "https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929"`.
  - `explicit thread_ts wins` over the permalink query.
  - `board-added row is re-keyed`: pre-insert `(C07R08WFC81, "1794540000.000100", permalink, tagged)` with facts NULL, then upsert with `message_ts "1794540000.000100"`, `thread_ts "1794536057.965929"`, `replies 4`: exactly one row, keyed `1794536057.965929`, `replies_at_tag 4`, `status` unchanged.
  - `fills a NULL replies_at_tag` on a root-keyed board-added row.
  - `rejects bad input and writes nothing`: `replies -1`, `replies 1.5`, empty `channel_id`, `last_reply "garbage"` each throw and the row count stays 0.
  - `stores snippets verbatim`: `"it's \"quoted\"; '); DROP TABLE tasks;-- 🚀"` round-trips and the table still exists.
- [ ] **Step 2: Run `npm test`.** Expected: FAIL, `slacktasks.ts` not found.
- [ ] **Step 3: Implement `upsertSlackTask`** with parameter binding only (never string-built SQL); derive the root permalink by taking the origin and `/archives/<channel_id>/p<digits-of-thread_ts>` from the given permalink.
- [ ] **Step 4: Run `npm test`.** Expected: all PASS.

### Task 3: MCP tool wiring

**Files:**
- Modify: `mcp/src/server.ts`, `mcp/test/server.test.ts`, `CLAUDE.md` (the `mcp/` line)

**Interfaces:**
- Consumes: `openDb`, `upsertSlackTask`.
- Produces: tool `upsert_slack_task` on the `sequence-vaults` server, zod input matching `UpsertInput` (all fields required except `thread_ts`; `replies` is `z.number().int().min(0)`); the result text is the JSON of `UpsertResult`; the database is opened and closed inside each call; errors come back as `isError` results like the other tools.

- [ ] **Step 1: Update `server.test.ts`:** the tool-name list expects ten names including `upsert_slack_task`; `connect` takes an optional `SEQUENCE_SLACK_DB` path; add `upsert_slack_task round trip`: first call returns `created`, second `updated`; add `upsert_slack_task with bad input returns an error and the server stays alive` (call with `replies: -1`, then `list_vaults` still answers).
- [ ] **Step 2: Run `npm test`.** Expected: the new tests FAIL (tool missing, name list of nine).
- [ ] **Step 3: Register the tool in `server.ts`** using the existing `tool()` helper pattern; its handler does not use `loadVaults`.
- [ ] **Step 4: Run `npm test`.** Expected: all PASS. The `node:sqlite` experimental warning goes to stderr only; the round-trip test proves stdout stays clean.
- [ ] **Step 5: Update the `mcp/` line in `CLAUDE.md`:** mention `upsert_slack_task` and the database path and override env.

### Task 4: Sync instructions and live acceptance

**Files:**
- Create: `mcp/skills/sync-slack-tasks/SKILL.md`

**Interfaces:**
- Consumes: the `upsert_slack_task` tool, the Workbench tools `slack_search_all` and `slack_get_thread_replies` via `mcp__workbench__execute_tools`.

- [ ] **Step 1: Write `SKILL.md`** (frontmatter `name: sync-slack-tasks`, a one-line `description` that triggers on "sync my slack tasks"). Steps it must give: (1) call `slack_search_all` with query `hasmy::loading:`, `count` 20, following pages; (2) for each hit call `slack_get_thread_replies` with `{channel: <channel.id>, threadTs: <hit permalink's thread_ts, else the hit's ts>, limit: 100}` and page if `has_more`; (3) `replies = messages.length - 1`, `last_reply` = the last message's `ts`, `snippet` = `messages[0].text`; (4) call `upsert_slack_task` once per thread with `channel_id`, `message_ts` = the hit's `ts`, `thread_ts` = `messages[0].ts`, `permalink`, `channel_name`, `snippet`, `replies`, `last_reply`; (5) report counts of created, updated and archived. State the rules: only the Workbench, never the claude.ai Slack connector; no Slack writes; do not edit `status` or `archived`.
- [ ] **Step 2: Live acceptance against a temporary database.** Run `slack_search_all` (`hasmy::loading:`) and `slack_get_thread_replies` for real through the Workbench (read-only), then feed the results through `upsertSlackTask` with `SEQUENCE_SLACK_DB` pointing to a temp file (a one-off script in the scratchpad, not committed). Expected: at least the known thread `C07R08WFC81` / `1794536057.965929` exists with `replies 0`, `channel_name "agent-network-eng"`, `status "todo"`; running the flow a second time reports `updated` for every row and changes no `status`. Report what was and was not verified.
- [ ] **Step 3: Ask the user before touching their setup, then do each approved item:** install the skill (link `~/.claude/skills/sync-slack-tasks` to `mcp/skills/sync-slack-tasks`), and rebuild `mcp/` so the registered server has the new tool (the user restarts their Claude session to load it). Do not run a sync into the real database until the user says so.

---

## Self-review notes

- Spec coverage: storage and schema (T1), upsert rules, root derivation, re-keying, archived skip, validation (T2), tool on the existing server (T3), sync instructions, `hasmy::loading:` search, thread replies counting, live check and approval gates (T4). The board, Swift wrapper and link parser are Stage 2.
- Types match across tasks: `Status`, `UpsertInput`, `UpsertResult`, `openDb`, `upsertSlackTask` are defined once and used with the same signatures.
