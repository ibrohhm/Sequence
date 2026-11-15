# Slack Tasks Board (Stage 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Slack tasks" board in Sequence that reads the SQLite database Stage 1 fills: four status columns, cards with "N new" and a quiet warning, drag to change status, click to open the thread, add by pasting a link, archive and restore.

**Architecture:** All logic lives in `StudioCore` with tests first: card model and derived flags, Slack link parser, and a SQLite store over the system `SQLite3` C API. `App/` holds a thin observable model that polls the store and a SwiftUI board; navigation reuses the rail and the detail panel.

**Tech Stack:** Swift 5.9 / SwiftUI, system `SQLite3` (no package), Swift Testing via `./test.sh`, `node --test` in `mcp/` for one schema-parity test.

**Spec:** `docs/superpowers/specs/2026-11-15-slack-tasks-design.md` (this is Stage 2; Stage 1, the `upsert_slack_task` tool, is committed as `0529849`).

## Global Constraints

- Database: `~/Library/Application Support/Sequence/slack-tasks.db`; env `SEQUENCE_SLACK_DB` overrides. WAL, busy timeout 5000 ms, `PRAGMA user_version = 1`, `CREATE TABLE IF NOT EXISTS` on open. The DDL text must equal `SLACK_TASKS_DDL` in `mcp/src/slackdb.ts` (a test in `mcp/` checks it).
- Sequence writes only `status` and `archived`, and inserts new rows for pasted links (`status todo`, `archived 0`, `tagged` = UTC date `YYYY-MM-DD`, facts NULL, keyed by the link's `thread_ts` if present, else its ts). It never writes facts columns of existing rows.
- Statuses: `todo`, `inprogress`, `blocked`, `done`. Board shows `archived = 0`; a "Show archived" toggle lists archived cards with Restore. Pasting a link for an archived thread restores it.
- "N new" = `replies - replies_at_tag` when both exist and the result is above 0. Quiet = status is not `done`, `last_reply` exists, and now minus the later of `last_reply` and the `tagged` date (00:00 UTC) is more than 5 days.
- Card click opens `permalink` with `NSWorkspace`. Board refreshes within a few seconds of the sync writing (poll `PRAGMA data_version`).
- Slack links accepted: `https://<name>.slack.com/archives/<channel id>/p<digits>` with optional `?thread_ts=<digits.digits>`; ts = digits with a dot before the last 6 digits.
- Project rules (`CLAUDE.md`): logic in `StudioCore` with tests first, views not unit tested, theme colours only from `Theme.swift`, no `.toolbar`, plain stacks layout, say when UI changes are unverified (no screenshots here).
- Version: this is a `feat`; `VERSION` goes 1.22.0 to 1.23.0 in the commit when the user asks for one. No commit steps in this plan.

## Review Focus

- Pasted text with surrounding whitespace or newlines, a non-Slack URL, other hosts, a too-short `p` number, `thread_ts=junk`: rejected or trimmed correctly (Task 1).
- A pasted card has NULL facts: shows the channel id and "Waiting for sync", no "N new", no quiet warning (Task 1 tests, Task 4 view).
- Status moved on the board while sync updates facts through another connection: both survive (Task 2).
- The database does not exist yet (never synced): the board shows an empty state, no crash (Task 2 test, Task 3).
- The database is locked or unreadable: the board keeps showing the last data and shows a notice (Task 3).
- Dropping a card on its own column does nothing and writes nothing (Task 3).
- Quiet boundary: exactly 5 days is not quiet; just over is (Task 1).

---

### Task 1: Card model, board grouping and link parser

**Files:**
- Create: `Sources/StudioCore/SlackTask.swift`, `Sources/StudioCore/SlackLink.swift`
- Test: `Tests/StudioCoreTests/SlackTaskTests.swift`, `Tests/StudioCoreTests/SlackLinkTests.swift`

**Interfaces:**
- Produces (all `public`):
  - `enum SlackStatus: String, CaseIterable, Sendable { case todo, inprogress, blocked, done; var title: String }` (titles `Todo`, `In progress`, `Blocked`, `Done`).
  - `struct SlackTask: Identifiable, Equatable, Sendable` with `channelID: String`, `threadTS: String`, `permalink: String`, `channelName: String?`, `snippet: String?`, `replies: Int?`, `repliesAtTag: Int?`, `lastReply: Date?`, `tagged: String`, `synced: String?`, `status: SlackStatus`, `archived: Bool`, a public memberwise `init`, `id: String` = `"\(channelID)/\(threadTS)"`, `newReplies: Int?`, `func isQuiet(now: Date, days: Int = 5) -> Bool`.
  - `enum SlackBoard { static func columns(_ tasks: [SlackTask]) -> [SlackStatus: [SlackTask]] }`: drops archived tasks, every status key present, each column sorted by activity (later of `lastReply` and the `tagged` date) newest first, ties by `id`.
  - `struct SlackLink: Equatable { host, channelID, ts: String; threadTS: String?; rootTS: String; permalink: String; static func parse(_ text: String) -> SlackLink? }`; `permalink` is the root's link without query.

- [ ] **Step 1: Write failing tests.**
  - `SlackLinkTests`: root link `https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929` gives host `amartha.slack.com`, channel `C07R08WFC81`, ts `1794536057.965929`, `threadTS` nil, `rootTS` = ts, `permalink` = the input; reply link `.../p1794540000000100?thread_ts=1794536057.965929&cid=C07R08WFC81` gives ts `1794540000.000100`, `threadTS` `1794536057.965929`, `rootTS` the thread's, `permalink` `https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929`; leading and trailing whitespace and newlines are trimmed; each of these returns nil: `hello`, `https://example.com/archives/C07R08WFC81/p1794536057965929`, `https://amartha.slack.com/archives/C07R08WFC81/1794536057965929`, `.../p12345`, `.../p1794536057965929?thread_ts=junk`, `https://amartha.slack.com/archives/c07-r/p1794536057965929`.
  - `SlackTaskTests`: `newReplies` is 2 for `replies 12, repliesAtTag 10`, nil when either is nil, nil when the difference is 0 or negative; `isQuiet` with `lastReply` = 5 days before `now` is false, 5 days plus 1 second is true; false for `done`; false when `lastReply` is nil; a `tagged` date later than `lastReply` is the reference; `SlackBoard.columns` puts tasks in their status column, drops archived, includes empty columns, and orders by activity newest first.
- [ ] **Step 2: Run `./test.sh`.** Expected: FAIL, types not found.
- [ ] **Step 3: Implement both files to the signatures above** (parse with `URLComponents`; `ts` and `thread_ts` checked with `^\d+\.\d+$`, digits with `^p\d{7,}$`, channel id `^[A-Z0-9]+$`, host suffix `.slack.com`).
- [ ] **Step 4: Run `./test.sh`.** Expected: all PASS.

### Task 2: SQLite store and schema parity

**Files:**
- Create: `Sources/StudioCore/SlackTaskStore.swift`
- Test: `Tests/StudioCoreTests/SlackTaskStoreTests.swift`; modify `mcp/test/slackdb.test.ts`

**Interfaces:**
- Consumes: `SlackTask`, `SlackStatus`, `SlackLink` from Task 1.
- Produces (`public`): `final class SlackTaskStore` with `static let ddl: String` (multi-line string `static let ddl = """ ... """`, same text as `SLACK_TASKS_DDL`), `static func defaultPath() -> String` (env `SEQUENCE_SLACK_DB`, else the default path), `init(path: String = defaultPath()) throws` (creates the parent folder, opens, sets busy timeout 5000, `journal_mode=WAL`, runs the DDL, `user_version = 1`), `func tasks(includeArchived: Bool) throws -> [SlackTask]`, `func setStatus(_ status: SlackStatus, for id: String) throws`, `func setArchived(_ archived: Bool, for id: String) throws`, `enum AddResult { case added, restored, exists }`, `func add(_ link: SlackLink, now: Date = Date()) throws -> AddResult`, `func dataVersion() throws -> Int`; `struct SlackStoreError: Error, LocalizedError` with a readable `errorDescription`. `id` is `"<channelID>/<threadTS>"` (split at the first `/`).

- [ ] **Step 1: Write failing tests** (temp directory path per test; a small test helper runs raw SQL on the same file through `import SQLite3` to play the part of the sync tool):
  - `init` creates a missing parent folder and file; a raw query shows `user_version` 1 and `journal_mode` `wal`; opening twice works.
  - `add` of the root link inserts one task: status `todo`, not archived, `tagged` `"2026-11-15"` for a fixed `now`, `permalink` equal to the link's, facts nil; `add` again returns `.exists`; after `setArchived(true, …)` `add` returns `.restored` and the task is active; `add` of the reply link from Task 1 keys the row to the thread root (`threadTS` `1794536057.965929`).
  - `setStatus(.blocked, …)` changes only `status`: every other field equals the value before.
  - `tasks(includeArchived: false)` hides archived rows; `true` shows them.
  - A row written by raw SQL the way sync writes it (all fact columns, `last_reply "2026-11-13T02:14:17Z"`) decodes with `replies`, `repliesAtTag`, `channelName`, and `lastReply` as the `Date` 2026-11-13 02:14:17 UTC.
  - After `setStatus(.inprogress, …)`, a raw sync-style `UPDATE tasks SET replies = 5, last_reply = …` leaves `status` `inprogress` and `tasks()` shows `replies 5`; the reverse order also keeps both.
  - `dataVersion()` changes after the raw connection writes.
  - `defaultPath()` returns the env value when `SEQUENCE_SLACK_DB` is set (restore it after) and ends with `Application Support/Sequence/slack-tasks.db` otherwise.
  - `mcp/test/slackdb.test.ts`: new test `Swift and TypeScript DDL are identical`: read `Sources/StudioCore/SlackTaskStore.swift` (path from `import.meta.dirname` plus `../../Sources/StudioCore/`), extract the text between `static let ddl = """` and the closing `"""`, and compare it with `SLACK_TASKS_DDL` after collapsing all whitespace runs to one space and trimming.
- [ ] **Step 2: Run `./test.sh`** (and `cd mcp && npm test`). Expected: store tests FAIL (type not found); the parity test FAILS (Swift file missing).
- [ ] **Step 3: Implement `SlackTaskStore`** over `SQLite3` with bound parameters only; finalize statements; close the connection in `deinit`; map `sqlite3_errmsg` into `SlackStoreError`.
- [ ] **Step 4: Run `./test.sh` and `cd mcp && npm test`.** Expected: all PASS in both.

### Task 3: Board model (app glue)

**Files:**
- Create: `App/SlackTasksModel.swift`

**Interfaces:**
- Consumes: `SlackTaskStore`, `SlackBoard`, `SlackLink`, `SlackTask`, `SlackStatus`.
- Produces: `@MainActor final class SlackTasksModel: ObservableObject` with `@Published private(set) var tasks: [SlackTask]`, `@Published var showArchived: Bool`, `@Published var notice: String?`, `var columns: [SlackStatus: [SlackTask]]` (from `SlackBoard.columns`), `var archivedTasks: [SlackTask]`, `func start()` (opens the store, loads, then polls `dataVersion()` every 3 s until `stop()`), `func stop()`, `func add(_ text: String)`, `func move(_ id: String, to status: SlackStatus)` (no store call when the task already has that status), `func archive(_ id: String)`, `func restore(_ id: String)`. Failures set `notice` to the error description and keep the previously loaded `tasks`. A pasted text that does not parse sets `notice` to `That is not a Slack message link.`; `.exists` sets `Already on the board.`; `.restored` sets `Restored from archive.` and the notice clears itself after 4 s.

- [ ] **Step 1: Implement the class to the interface above** (logic stays in `StudioCore`; this file only wires it). It is not unit tested (project rule); verification is the build.
- [ ] **Step 2: Run `swift build`.** Expected: `Build complete` with no warnings from this file.

### Task 4: Board view, navigation, docs

**Files:**
- Create: `App/SlackTasksView.swift`
- Modify: `App/AppModel.swift` (add `@Published var showTasks = false`, `func openTasks()` which calls `closePlayground()` when in a playground and sets `showTasks = true`; set `showTasks = false` at the top of the existing `select` method and of `openPlayground(kind:)`), `App/ChromeButtons.swift` (`IconRail`: a `checklist` icon, help `Slack tasks`, `selected: model.showTasks`, placed after the two playground icons; the Files icon's `selected` also requires `!model.showTasks`, and `showFiles()` clears `showTasks` and shows the sidebar), `App/RootView.swift` (hide the sidebar while `showTasks`; the detail panel shows `SlackTasksView()` instead of the file detail while `showTasks`), `CLAUDE.md`

- [ ] **Step 1: Build `SlackTasksView`:** a header with the title, a text field plus Add button (`model.add`, also on Return), a "Show archived" toggle and the `notice`; four equal-width columns titled with `SlackStatus.title` and the card count; each column accepts `String` drops (`.dropDestination(for: String.self)`) and calls `model.move(id, to:)`; each card is `.draggable(task.id)`. A card shows `#<channelName>` (or the channel id when nil), the time since last activity (`RelativeDateTimeFormatter`), the snippet on one collapsed line break-free block of up to 3 lines, `N replies`, a dot plus `N new` in `theme.accent` when `newReplies` is set, and a clock plus `quiet Nd` when `isQuiet`; a card with no facts shows `Waiting for sync` instead. Clicking opens `permalink` with `NSWorkspace.shared.open`; the context menu has Archive. With the toggle on, archived cards list below with a Restore button. An empty database shows a centred message: `No Slack tasks yet. Tag a thread with :loading: and tell Claude "sync my Slack tasks".` Colours come only from `Theme` (`model.theme`). Call `start()` in `.onAppear` and `stop()` in `.onDisappear` of a `@StateObject SlackTasksModel`.
- [ ] **Step 2: Wire navigation** in `AppModel`, `IconRail` and `RootView` as listed above.
- [ ] **Step 3: Run `swift build` then `./test.sh`.** Expected: build completes; all tests pass (123 existing plus the new ones).
- [ ] **Step 4: Update `CLAUDE.md`:** Layout section gets the Slack tasks board (rail icon, `SlackTasksView`/`SlackTasksModel`, `StudioCore` types and the DB path), the `StudioCore` list gains the new files, and the Rules gain "the board writes only `status`/`archived`; sync owns the facts".
- [ ] **Step 5: Run `./build-app.sh`** and report `build/Sequence.app` built. State plainly that the look, drag and drop, and click-through are unverified (no screenshots here) and list what the user should check after quitting (⌘Q) and reopening: the rail icon, empty state, the four columns, dragging a card, clicking a card, pasting a link, archive and restore, a new sync appearing within a few seconds. Do not bump `VERSION` or commit; tell the user the commit would be `feat(app)` and bump to 1.23.0.

---

## Self-review notes

- Spec coverage: columns, statuses, drag, click, add, archive and restore, "N new", quiet, refresh, empty state, pasted-link restore, schema parity (Tasks 1–4); sync owns facts (Task 2 test, Global Constraints).
- Types match across tasks: `SlackTask`, `SlackStatus`, `SlackLink`, `SlackBoard.columns`, `SlackTaskStore` method names and `AddResult` are defined once and used identically in Tasks 3 and 4.
