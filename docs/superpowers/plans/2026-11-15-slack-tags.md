# Slack Tags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tags with their own board or list page, fed by emoji reactions and Slack's To-dos and Saved lists, edited in an app window, synced per tag.

**Architecture:** Schema v3 (a `tags` table plus a `tasks` table keyed by tag) is created and upgraded identically by the Node tool and the Swift store. The Node tool gains `list_slack_tags` and a required `tag` on `upsert_slack_task`; the skill syncs all or named tags. The app shows one page per tag and edits tags in its own window. Tag settings are written only by the app.

**Tech Stack:** Node `node:sqlite` + TypeScript (`node --test`), Swift + system `SQLite3` (`./test.sh`), SwiftUI.

**Spec:** `docs/superpowers/specs/2026-11-15-slack-tags-design.md` (read it first; it builds on `2026-11-15-slack-tasks-design.md`).

## Global Constraints

- `PRAGMA user_version = 3`. Both programs create the same two tables and upgrade a v1, v2 or v3 file in place, inside `BEGIN IMMEDIATE`, safe to run twice or concurrently. Detect an old `tasks` table by `PRAGMA table_info(tasks)` lacking a `tag` column.
- Table `tags`: `id TEXT PRIMARY KEY`, `name TEXT NOT NULL`, `kind TEXT NOT NULL CHECK (kind IN ('board','list'))`, `slack_list TEXT NOT NULL CHECK (slack_list IN ('none','todo','saved'))`, `reactions TEXT NOT NULL` (JSON array of emoji names without colons), `columns TEXT NOT NULL` (JSON array of names; `[]` for list), `position INTEGER NOT NULL`, `builtin INTEGER NOT NULL DEFAULT 0`.
- Table `tasks`: the v2 columns plus `tag TEXT NOT NULL` first; `PRIMARY KEY (tag, channel_id, thread_ts)`; `status TEXT NOT NULL DEFAULT ''` with no CHECK (holds a column name; `''` for lists).
- Upgrade copies every old row into tag `todo`, rewriting status `todo`→`Todo`, `inprogress`→`In progress`, `blocked`→`Blocked`, `done`→`Done` (anything else unchanged). Seeds, only when `tags` is empty: `todo` ("To-do", builtin, `slack_list todo`, reactions `["loading","loading1"]`, board, columns `["Todo","In progress","Blocked","Done"]`, position 0) and `saved` ("Saved", builtin, `slack_list saved`, reactions `[]`, list, columns `[]`, position 1). Fresh databases get the same seeds.
- Columns: 1 to 8 per board tag, unique names, non-empty. Emoji names match `^[a-z0-9_+-]+$`. A tag id is a slug of its name made once (`[a-z0-9-]`), unique, a numeric suffix on collision, never changed on rename. Built-in tags cannot be deleted and keep their `slack_list` and `kind`; custom tags have `slack_list none`.
- The first column is where new cards land; the last column counts as done (no quiet warning); a card whose status matches no column is shown in the first column, stored status untouched. Renaming a column rewrites that tag's card statuses and deleting one moves its cards to the first column, in the same transaction as the tag edit.
- `upsert_slack_task`: required `tag` (unknown id = error, nothing written); for `list` tags `replies` is optional (NULL), `next_action` is rejected, and a card is stale only when `summary IS NULL`; for `board` tags `replies` stays required. New cards get `status` = first column (`''` for lists). The tool reads the tag inside its own `BEGIN IMMEDIATE`. Everything else about the tool (never touching `status`, `archived`, `tagged`; validation; re-key; `summary_stale`) is unchanged and scoped by tag.
- Sequence writes only: `tags` rows, `status`, `archived`, and new cards for pasted links. The sync tool never writes `tags`.
- DDL text for both tables is identical in `mcp/src/slackdb.ts` (`SLACK_TAGS_DDL`, `SLACK_TASKS_DDL`) and `SlackTaskStore.swift` (`static let tagsDDL`, `static let tasksDDL`); the parity test compares both.
- Project rules: logic in `StudioCore` with tests first, views not unit tested, theme colours from `Theme.swift`, no `.toolbar`, native windows or alerts (no in-window sheets), say what is unverified. No `VERSION` bump or commit steps (the commit would be `feat` and 1.23.0 to 1.24.0 when the user asks).

## Review Focus

- A v2 database with a card the user moved to Blocked upgrades with the card in tag `todo`, status `Blocked`; opening twice, or Node and Swift back to back, is safe (Tasks 1, 4).
- Two cards for one thread in two tags keep independent status and archived flags (Tasks 2, 4).
- Deleting a column moves its cards; renaming one rewrites their status; both in one transaction with the tag edit (Task 4).
- Deleting a custom tag hides its cards without deleting them, and a re-created tag with the same slug shows them again (Task 4).
- A list-tag upsert without `replies` works and is stale only without a summary; `next_action` is rejected for it; an unknown tag writes nothing (Task 2).
- Invalid emoji names, duplicate or empty columns, more than 8 columns, slug collisions (Task 3).

---

### Task 1: Node schema v3 and upgrade

**Files:**
- Modify: `mcp/src/slackdb.ts`
- Test: `mcp/test/slackdb.test.ts`

**Interfaces:**
- Produces: exported `SLACK_TAGS_DDL`, `SLACK_TASKS_DDL` (v3 text); `openDb` leaves `user_version = 3`, upgrades v1/v2 files, seeds tags; `type Status` is removed (status is a string).

- [ ] **Step 1: Write failing tests:** `user_version` is 3 and a fresh file has the two seeds (`todo` board with four columns and reactions `["loading","loading1"]`, `saved` list) in position order; `upgrades a v2 database with cards`: build a v2 file (the current tasks DDL with the three summary columns, `user_version 2`) holding two rows, statuses `blocked` and `done`, one with a summary: after `openDb` both rows have `tag 'todo'`, statuses `Blocked` and `Done`, the summary kept, tags seeded, version 3; `upgrades a v1 database` the same through v1 to v3 (existing v1 test fixture); a second `openDb` and two concurrent `openDb` calls on a v2 file succeed; inserting a `tasks` row with status `weird` now succeeds (no CHECK); a `tags` row with kind `x` or slack_list `x` is rejected. Update the existing tests that assert `user_version 2` or `status 'weird'` rejected.
- [ ] **Step 2: Run `cd mcp && npm test`.** Expected: new and changed tests FAIL.
- [ ] **Step 3: Implement** the two DDLs, the chained upgrade (v1→v2 columns as today, then the v3 rebuild: create `tasks_v3`, copy with the status CASE and `'todo'` tag, drop, rename; seed tags; skip the rebuild when `tasks` already has `tag`), version 3. Remove the old `Status` type and its uses.
- [ ] **Step 4: Run `npm test`.** Expected: PASS except the DDL parity test (fails until Task 4) and any upsert tests that need Task 2.

### Task 2: Node upsert with tags and `list_slack_tags`

**Files:**
- Create: `mcp/src/slacktags.ts`
- Modify: `mcp/src/slacktasks.ts`, `mcp/src/server.ts`
- Test: `mcp/test/slacktasks.test.ts`, `mcp/test/slacktags.test.ts`, `mcp/test/server.test.ts`

**Interfaces:**
- Consumes: Task 1 schema.
- Produces: `type TagRow = { id: string; name: string; kind: "board" | "list"; slack_list: "none" | "todo" | "saved"; reactions: string[]; columns: string[] }`; `listSlackTags(db: DatabaseSync): TagRow[]` ordered by `position`; `UpsertInput` gains `tag: string` and `replies?: number`; tool `list_slack_tags` (no input, returns the array as JSON); `upsert_slack_task` input gains required `tag`, optional `replies`.

- [ ] **Step 1: Write failing tests** (existing tests pass `tag: "todo"` and expect `status` `"Todo"` on creation): `listSlackTags` returns the two seeds in order with parsed arrays and reflects a tag added by raw SQL; upsert on `todo` creates the card with `tag 'todo'`, status `Todo`; the same thread under tag `saved` is a second independent row (setting one's status or archived does not touch the other); an unknown tag throws and writes nothing; a `saved` (list) upsert without `replies` stores NULL `replies` and `replies_at_tag`, `status ''`, and is `summary_stale true` until a summary is given and `false` after, regardless of replies; `next_action` on a list tag is rejected; a board tag without `replies` is rejected; the new card status follows a custom tag whose columns are `["Open","Done"]` (`Open`); the re-key and archived rules still work inside a tag; `server.test.ts`: ten tools become eleven (`list_slack_tags`), a round trip with `tag`.
- [ ] **Step 2: Run `npm test`.** Expected: FAIL.
- [ ] **Step 3: Implement** `slacktags.ts`, scope every query by `tag`, read the tag inside the existing `BEGIN IMMEDIATE`, make `replies` optional per the constraints, register the tools (zod `tag: z.string()`).
- [ ] **Step 4: Run `npm test`.** Expected: PASS except the parity test.

### Task 3: Swift core types and rules

**Files:**
- Create: `Sources/StudioCore/SlackTag.swift`
- Modify: `Sources/StudioCore/SlackTask.swift`
- Test: `Tests/StudioCoreTests/SlackTagTests.swift`, `Tests/StudioCoreTests/SlackTaskTests.swift`

**Interfaces:**
- Produces (public): `enum SlackTagKind: String { case board, list }`; `enum SlackList: String { case none, todo, saved }`; `struct SlackTag: Identifiable, Equatable { id, name: String; kind: SlackTagKind; slackList: SlackList; reactions: [String]; columns: [String]; position: Int; builtin: Bool }`; `enum SlackTagRules { static func slug(for name: String, existing: Set<String>) -> String; static func validate(name: String, kind: SlackTagKind, reactions: [String], columns: [String]) -> String? }` (an error message or nil); `SlackTask.status: String` (replaces `SlackStatus`, which is deleted), `SlackTask.tag: String`, `SlackTask.id = "\(tag)/\(channelID)/\(threadTS)"`, `isQuiet(now:days:doneColumn:)` and `quietDays(now:days:doneColumn:)` (false/nil when `status == doneColumn`; unchanged rules otherwise); `SlackBoard.groups(_ tasks: [SlackTask], for tag: SlackTag) -> [(name: String, tasks: [SlackTask])]`: board tags give one group per column in order (a card whose status matches no column goes to the first), list tags one group named `""`; archived tasks excluded; each group newest activity first.

- [ ] **Step 1: Write failing tests:** `slug("Code Review", existing: [])` is `code-review`; with `["code-review"]` it is `code-review-2`; `slug("🎫 !!", …)` falls back to `tag`; `validate` returns nil for a good input and a message for each of: empty name, a list with columns, a board with 0 columns, 9 columns, duplicate columns (case-insensitive), an empty column name, an emoji name `Bad Name`, `:ticket:`; `isQuiet` stays quiet for the same inputs as before but is false when `status == doneColumn`; `SlackBoard.groups` for a board tag places a card with status `Gone` in the first group, orders columns as given, drops archived; for a list tag returns one group. Rewrite the existing `SlackTaskTests` for string statuses and the new `id`.
- [ ] **Step 2: Run `./test.sh`.** Expected: FAIL (types missing; old tests no longer compile).
- [ ] **Step 3: Implement** the types and rules; delete `SlackStatus`.
- [ ] **Step 4: Run `./test.sh`.** Expected: the new tests PASS; `SlackTaskStoreTests` and app code still fail to compile until Task 4 (note it in the ledger; keep going).

### Task 4: Swift store v3, tag CRUD, DDL parity

**Files:**
- Modify: `Sources/StudioCore/SlackTaskStore.swift`, `Sources/StudioCore/SlackLink.swift` (no change expected), `mcp/test/slackdb.test.ts`
- Test: `Tests/StudioCoreTests/SlackTaskStoreTests.swift`

**Interfaces:**
- Consumes: Tasks 1 and 3.
- Produces: `static let tagsDDL`, `static let tasksDDL` (identical text to Node); `init` runs the same chained upgrade; `tags() throws -> [SlackTag]`; `tasks(tag: String, includeArchived: Bool) throws -> [SlackTask]`; `setStatus(_ status: String, for id: String)` and `setArchived(_:for:)` (id = `tag/channel/ts`); `add(_ link: SlackLink, tag: String, now: Date = Date())` (new card status = the tag's first column, `''` for lists; `.added/.restored/.exists`); `saveTag(_ tag: SlackTag, renames: [String: String] = [:]) throws` (insert or update; in one transaction applies column renames to that tag's card statuses and moves cards whose status is not in the new column list to the first column; position as given); `deleteTag(_ id: String) throws` (custom tags only; cards stay); `moveTag(_ id: String, to position: Int) throws`; the parity test compares both Swift DDLs (extract `static let tagsDDL = """…"""` and `static let tasksDDL = """…"""`) with the Node constants after whitespace collapsing.

- [ ] **Step 1: Write failing tests** (temp paths, a raw-SQL helper as in the current tests): upgrade a v2 file with rows (statuses `blocked`, `done`, one summary) gives tag `todo`, `Blocked`, `Done`, summary kept, version 3, seeds present; opening twice works; `add` puts a card in the tag's first column and a second `add` of the same link under another tag is a separate card; `setStatus`/`setArchived` affect only that tag's card; `saveTag` with a renamed column rewrites matching card statuses; `saveTag` with a removed column moves its cards to the first column; both happen together with the tag change (a forced failure inside leaves everything unchanged: test with an invalid column list, which must throw before touching cards); `deleteTag` on a custom tag removes the tag but the raw `tasks` rows remain, and `saveTag` of a tag with the same id shows them again; `deleteTag` on a built-in throws; `moveTag` reorders positions without gaps; `tasks(tag:includeArchived:)` filters by tag; `tags()` returns seeds first. Update `SlackTaskStoreTests` for the new API and the parity test for both tables.
- [ ] **Step 2: Run `./test.sh` and `cd mcp && npm test`.** Expected: FAIL.
- [ ] **Step 3: Implement** the store (same upgrade rules and statements as Node; bound parameters only; `saveTag` and `deleteTag` in `BEGIN IMMEDIATE`).
- [ ] **Step 4: Run `./test.sh`, `cd mcp && npm test`.** Expected: PASS for the StudioCore and mcp suites; app code may still fail to compile until Task 5.

### Task 5: Tag pages in the app

**Files:**
- Modify: `App/SlackTasksModel.swift`, `App/SlackTasksView.swift`

**Interfaces:**
- Consumes: Task 4 store and Task 3 rules.
- Produces: `SlackTasksModel` gains `@Published private(set) var tags: [SlackTag]`, `@Published var selectedTag: String`, `groups: [(name: String, tasks: [SlackTask])]` for the selected tag, `var currentTag: SlackTag?`, `func move(_ id: String, to column: String)`, `add(_ text: String)` adding to the selected tag; it reloads `tags` and tasks on the existing `data_version` poll. `SlackTasksView` header shows tab buttons for the tags (selected styling from `Theme`) and an "Edit tags…" button (opens the window from Task 6 via `openWindow(id: "slack-tags")`).

- [ ] **Step 1: Implement** the model changes and the view: a board tag shows its columns (existing look, titles from column names, drops call `move`); a list tag shows one list of cards (channel, summary or first message, time since the message, replies when present, the same click, archive and restore) with no drag; the last column of a board is the done column passed to `isQuiet`; empty-state text per tag; a note on the To-do page when the Slack To-dos list is not readable (shown until Task 7 records otherwise); the selected tag is remembered in `UserDefaults` key `slackTagSelected`. Keep colours in `Theme`.
- [ ] **Step 2: Run `swift build` then `./test.sh`.** Expected: build completes; all tests pass.

### Task 6: Tag editor window

**Files:**
- Create: `App/SlackTagsEditorView.swift`
- Modify: `App/SequenceApp.swift` (add `Window("Slack tags", id: "slack-tags") { SlackTagsEditorView() }` with a default size of about 640x460), `CLAUDE.md`

**Interfaces:**
- Consumes: `SlackTaskStore` tag CRUD and `SlackTagRules` (Task 3 and 4).

- [ ] **Step 1: Implement** `SlackTagsEditorView`: a left list of tags (position order) with move up/down and an add button; the right side edits the selected tag: name; kind (custom tags only); emoji names as a comma-separated field shown without colons; columns for board tags (add, rename, reorder, delete); built-in tags per the spec (name, emoji names and the To-do columns editable; kind, Slack list and delete locked). Save validates with `SlackTagRules.validate` and shows the message in a native alert on failure; applying column renames passes `renames` to `saveTag`. Delete uses a native confirmation alert and `deleteTag`. The editor opens its own `SlackTaskStore` and refreshes on the same poll.
- [ ] **Step 2: Run `swift build` then `./test.sh`.** Expected: build completes; all tests pass.
- [ ] **Step 3: Update `CLAUDE.md`:** the board section (tags, tag pages, editor window, `slackTagSelected`), schema v3 notes, and the `mcp/` line (`list_slack_tags`, required `tag`).

### Task 7: Skill, backup, migration check, spike

**Files:**
- Modify: `mcp/skills/sync-slack-tasks/SKILL.md`

- [ ] **Step 1: Update `SKILL.md`:** trigger phrases (all tags, or tags named: match case-insensitively against `id` or `name` from `list_slack_tags`; an unknown name makes the agent list the real tags and stop); per tag: reactions via `hasmy::<name>:` for each emoji, `slack_list saved` via `is:saved`, `slack_list todo` skipped with a note until the spike below shows it is readable; follow all pages; board tags fetch each thread as today, list tags do not fetch threads (use the hit's text, ts and permalink, `replies` omitted, `last_reply` = the hit's ts) and write no `next_action`; call `upsert_slack_task` with `tag`; collect stale threads across the synced tags first, then write at most 10 summaries in total, newest first, and report how many wait. Keep the existing rules (Workbench only, no Slack writes, language, omit an empty `next_action`).
- [ ] **Step 2: Back up the real database** (`sqlite3 … ".backup …slack-tasks.db.bak-v2-2026-11-15"`), confirm the row count, then run the upgrade on a **copy** with a one-off script and report: version 3, both cards in tag `todo` with statuses mapped, tags seeded. Do not open the real file with new code.
- [ ] **Step 3: Rebuild** (`cd mcp && npm test`, then `./build-app.sh`) and report; tell the user to restart Claude and reopen Sequence (the real database upgrades on first open).
- [ ] **Step 4: Spike for the To-dos list:** ask the user to add one message with "Add to-do" and a different one with "Add to saved"; then run `is:saved` through the Workbench and report whether the to-do appears and the total changed. Record the finding in the spec under "Sources and sync". If readable, change the skill to use that search for `slack_list todo` and drop the To-do page note; if not, leave both as they are. Report plainly what was and was not verified (the page look, the editor window and real agent output are unverified).

---

## Self-review notes

- Spec coverage: schema v3 and seeds (1, 4), tag CRUD and column rules (3, 4, 6), sources and list-tag behaviour (2, 7), per-tag sync and 10-summary cap (7), pages and tabs (5), editor window (6), deletion keeps cards (4), spike and fallback (5, 7).
- Interfaces match across tasks: `SlackTag`, `SlackTagRules`, `SlackBoard.groups`, `SlackTask.id`/`status`/`tag`, and the store methods are defined once and used with the same signatures. Tasks 3 to 5 leave the app target uncompiled in between; the ledger records it.
