# Tasks Page With Tag Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One "Tasks" page where every board tag is a collapsible section (or all merged, by a setting) with the same four fixed columns; Saved and other list tags stay separate pages.

**Architecture:** Fixed columns live in one constant per language; schema v5 normalises existing statuses and board-tag columns in both programs; `SlackBoard` gains `sections` and `merged`; the board model loads all board-tag cards for the Tasks page; the view renders sections or a merged board; the tag editor loses its column editor; a Settings toggle chooses split or merged.

**Tech Stack:** Node `node:sqlite` + TypeScript (`node --test`), Swift + system SQLite3 (`./test.sh`), SwiftUI.

**Spec:** `docs/superpowers/specs/2026-11-16-tasks-sections-design.md` (read it and `2026-11-15-slack-tags-design.md` first).

## Global Constraints

- Standard columns, exactly: `Todo`, `In progress`, `Blocked`, `Done` (JSON text `["Todo","In progress","Blocked","Done"]`). The last counts as done (no quiet warning). A board card whose status matches none shows in Todo (display only).
- Schema v5, no DDL change, `user_version = 5`. In one `BEGIN IMMEDIATE`, in both Node `openDb` and Swift `SlackTaskStore.init`: set `columns` of every `kind = 'board'` tag to the standard JSON; for every card of a board tag normalise `status`: lowercase it, remove spaces and hyphens, compare with `todo`, `inprogress`, `blocked`, `done`, rewrite to the canonical name, anything else (including `''`) becomes `Todo`. List-tag cards untouched. Safe to run twice and concurrently.
- Node sync: new board cards start in `Todo` (a constant), not `tag.columns[0]`; list-tag cards keep `''`. Nothing else about the sync tool changes.
- A board tag's columns are never an input: `saveTag` stores the standard four for board tags and `[]` for list tags; the column rename/remove logic and the `renames` parameter are deleted; `SlackTagRules.validate` takes no columns.
- Sections are board tags only, sorted by name with case-insensitive comparison; merged mode lists all board-tag cards in the four columns, newest activity first. Archived cards are excluded from sections and merged; one "Archived" list at the bottom of the Tasks page covers all board tags with each row showing its tag.
- Pages: "Tasks" plus each list tag in `position` order. UserDefaults: `slackTagSelected` (`tasks` or a list tag id; any other stored value, including a board tag id, becomes `tasks`), `slackTagsCollapsed` (array of tag ids), `groupTasksByTag` (Bool, default true), `slackAddTag` (tag id for the paste picker, default `todo`).
- Drop rules: split mode: a card can only be dropped on a column of its own tag's section; merged mode: any column. A drop only changes `status`.
- Every card shows its tag name as a chip. Title text on the page is "Tasks".
- Project rules: logic in `StudioCore` with tests first, views not unit tested, colours from `Theme`, no `.toolbar`, native alerts, no animation, say what is unverified. No commit steps (the user commits on request; it would be `feat`, 1.25.1 to 1.26.0).

## Review Focus

- Status variants `Inprogress`, `in-progress`, `IN PROGRESS`, `DONE`, `weird`, `''` on a board tag all become one of the four; a list-tag card's `''` stays (Tasks 1, 3).
- Two programs opening a v4 file together, and a second open, do nothing extra (Tasks 1, 3).
- Sections order: `Ticket Oncall` before `To-do` (Ti < To), ignoring case; list tags never appear as sections (Task 2).
- A collapsed tag that is later deleted does not break the page; the collapsed set is only read for existing tags (Task 4).
- An old `slackTagSelected` of `todo` opens the Tasks page; a list tag id opens that list (Task 4).
- Dropping on another section's column does nothing in split mode (Task 4).

---

### Task 1: Node schema v5 and sync default

**Files:**
- Modify: `mcp/src/slackdb.ts`, `mcp/src/slacktasks.ts`
- Test: `mcp/test/slackdb.test.ts`, `mcp/test/slacktasks.test.ts`, `mcp/test/server.test.ts`

**Interfaces:**
- Produces: `export const STANDARD_COLUMNS = ["Todo", "In progress", "Blocked", "Done"]`; `openDb` leaves `user_version = 5` and applies the Global Constraints migration.

- [ ] **Step 1: Write failing tests.** `slackdb`: `user_version` expectations become 5 (every existing assertion of 4); `upgrades a v4 database: board columns and statuses are normalised`: build a v4 file (current DDL, `user_version 4`) with tags `todo` (board, standard columns), `saved` (list), `ticket-oncall` (board, columns `["Todo","Inprogress","Blocked","Done"]`) and cards: ticket-oncall `Inprogress`; todo `in-progress`, `IN PROGRESS`, `DONE`, `weird`, `''`, `Blocked`; saved `''`: after `openDb` the statuses are `In progress`, `In progress`, `In progress`, `Done`, `Todo`, `Todo`, `Blocked` and the saved card is still `''`, both board tags have the standard columns JSON, the list tag's columns are `[]`, version 5; a second `openDb` changes nothing; two opens on one v4 file both succeed; a test that reads `Sources/StudioCore/SlackTaskStore.swift` and compares its `static let all = [...]` literal inside `enum SlackColumns` with `STANDARD_COLUMNS`. `slacktasks`: `a new card takes the first column of a custom tag` becomes `a new board card starts in Todo whatever the tag's columns`. `server.test.ts`: any expectation of per-tag columns follows (the seeded `todo` columns are still the standard four).
- [ ] **Step 2: Run `cd mcp && npm test`.** Expected: the new and changed tests FAIL.
- [ ] **Step 3: Implement** the migration step (JS normalise function, `UPDATE tasks SET status = ? WHERE rowid = ?` per changed row, `UPDATE tags SET columns = ?` for board tags) inside the existing `upgrade`, guard `version >= 5`; in `upsertSlackTask` use `STANDARD_COLUMNS[0]` for new board cards.
- [ ] **Step 4: Run `npm test`.** Expected: PASS except the new parity test (needs Task 2's Swift constant).

### Task 2: Swift columns, sections and rules

**Files:**
- Create: `Sources/StudioCore/SlackColumns.swift`
- Modify: `Sources/StudioCore/SlackTask.swift` (`SlackBoard`), `Sources/StudioCore/SlackTag.swift`
- Test: `Tests/StudioCoreTests/SlackTagTests.swift`, `Tests/StudioCoreTests/SlackTaskTests.swift`

**Interfaces:**
- Produces (public): `enum SlackColumns { static let all: [String]` (`["Todo", "In progress", "Blocked", "Done"]`), `static let done: String`, `static func canonical(_ status: String) -> String?` (the normalise rule from Global Constraints, nil when nothing matches) `}`; `SlackBoard.sections(_ tasks: [SlackTask], tags: [SlackTag]) -> [(tag: SlackTag, columns: [(name: String, tasks: [SlackTask])])]`; `SlackBoard.merged(_ tasks: [SlackTask], tags: [SlackTag]) -> [(name: String, tasks: [SlackTask])]`; `SlackBoard.groups(_:for:)` keeps working for list tags and uses `SlackColumns.all` for a board tag; `SlackTagRules.validate(name:kind:reactions:) -> String?` (no columns).

- [ ] **Step 1: Write failing tests:** `canonical` maps `Inprogress`, `in-progress`, `IN PROGRESS`, `in progress` to `In progress`, `DONE` to `Done`, `weird` and `""` to nil; `sections` returns board tags only, sorted case-insensitively (`To-do` and `Ticket Oncall` give `Ticket Oncall` first; names `b` and `A` give `A` first), each with the four column groups in order, an unknown status in Todo, archived excluded, newest activity first, a tag with no cards still present; list tags absent; `merged` returns four groups holding cards of all board tags newest first and no list-tag cards; `validate` no longer mentions columns (remove the column cases from `SlackTagTests`; keep name and emoji cases); a list tag's `groups` is unchanged. Update tests that built board tags with custom columns.
- [ ] **Step 2: Run `./test.sh`.** Expected: FAIL (types missing; changed signatures).
- [ ] **Step 3: Implement** to the signatures above.
- [ ] **Step 4: Run `./test.sh`.** Expected: the new tests PASS; the store tests and the app may not compile until Tasks 3 and 4 (note in the ledger).

### Task 3: Swift store v5

**Files:**
- Modify: `Sources/StudioCore/SlackTaskStore.swift`
- Test: `Tests/StudioCoreTests/SlackTaskStoreTests.swift`

**Interfaces:**
- Consumes: `SlackColumns`, `SlackTagRules`.
- Produces: `init` applies the v5 migration (same rule as Node); `saveTag(_ tag: SlackTag) throws` (no `renames`; board tags always get `SlackColumns.all`, list tags `[]`; kind stays fixed for existing tags, built-ins keep kind and slack list); `tasks(tags: [String], includeArchived: Bool) throws -> [SlackTask]` (all given tags in one call).

- [ ] **Step 1: Write failing tests:** the `user_version` expectations become `"5"`; `upgradesAV4DatabaseNormalisingBoardStatusesAndColumns` mirrors the Node test (tags `todo`, `saved`, `ticket-oncall` with `Inprogress`, the same status variants, list card `''` untouched, columns rewritten, version 5, second open and re-open fine); `saveTagStoresTheStandardColumnsForABoardAndNoneForAList`; `tasksForSeveralTagsReturnsAllOfThem` (three tags, includeArchived both ways); delete the column rename/remove tests and the `renames` call sites.
- [ ] **Step 2: Run `./test.sh` and `cd mcp && npm test`.** Expected: FAIL.
- [ ] **Step 3: Implement** the migration (same statements and canonical rule as Task 1, using `SlackColumns.canonical`), the new `saveTag`, and `tasks(tags:includeArchived:)`.
- [ ] **Step 4: Run `./test.sh` and `cd mcp && npm test`.** Expected: Swift store tests PASS and the Node parity test PASSES; the app target may still not compile until Task 4.

### Task 4: App pages, sections, settings, editor

**Files:**
- Modify: `App/SlackTasksModel.swift`, `App/SlackTasksView.swift`, `App/SlackTagsEditorView.swift`, `App/SettingsView.swift`, `CLAUDE.md`, `mcp/skills/sync-slack-tasks/SKILL.md`

**Interfaces:**
- Consumes: `SlackBoard.sections/merged/groups`, `SlackColumns`, store `tasks(tags:includeArchived:)`, `saveTag(_:)`.
- Produces: `SlackTasksModel` with `pages: [(id: String, title: String)]` (`tasks` first, then list tags), `selectedPage`, `sections`, `mergedColumns`, `listGroups`, `archivedTasks` (across board tags on the Tasks page, else the list tag's), `collapsed: Set<String>` with `toggleCollapsed(_ tagID: String)`, `boardTags`, `addTag` (picker value) and `move(_ id: String, to column: String, inSection tag: String?)` (ignores the drop when `tag` is given and differs from the card's tag).

- [ ] **Step 1: Implement the model:** load every board tag's cards for the Tasks page (one `tasks(tags:…)` call), a list tag's cards for a list page; persist `slackTagSelected` (migrating old values), `slackTagsCollapsed` (pruned to existing tags on read), `slackAddTag` (falls back to `todo`, then the first board tag, when the stored tag no longer exists); `add(_ text:)` adds to `addTag` on the Tasks page or to the list tag on its page.
- [ ] **Step 2: Implement the view:** title "Tasks" for the Tasks page (list pages keep their tag name); tabs: Tasks plus list tags; split mode: per section a header row (chevron, tag name, card count, tap toggles, no animation) and, when expanded, the four column panels with their headers (existing panel look), merged mode: one set of four columns; every card shows a tag chip (neutral `Chip`); the picker (a `Menu` next to the paste field, board tags only on the Tasks page); the Archived list shows the tag on each row; empty state when no board tag has a card; drop rules per Global Constraints; keep Open in Slack, number, chips, drag.
- [ ] **Step 3: Settings and editor:** `SettingsView` General: a new `Section("Tasks")` with `Toggle("Group tasks by tag", isOn: $groupTasksByTag)` (`@AppStorage("groupTasksByTag")`, default true) and a one-line note "Off shows every tag's cards together in one set of columns."; `SlackTagsEditorView`: remove the columns section, the column draft state and `renames`; board tags show a note "Columns: Todo, In progress, Blocked, Done" instead.
- [ ] **Step 4: Run `swift build` then `./test.sh` and `cd mcp && npm test`.** Expected: build completes; all tests pass.
- [ ] **Step 5: Update docs:** `CLAUDE.md` (the Slack tasks paragraph: Tasks page with tag sections, fixed columns, the setting, pages, schema v5, UserDefaults keys) and `SKILL.md` (drop per-tag columns wording; new board cards start in Todo).

### Task 5: Backup, migration check, rebuild

- [ ] **Step 1:** back up the real database (`sqlite3 … ".backup …slack-tasks.db.bak-v4-2026-11-16"`), check the row counts, then run the upgrade on a **copy** with a one-off script and report: version 5, the Ticket Oncall card is `In progress`, board tags have the standard columns, the 43 Saved cards untouched. Do not open the real file with new code.
- [ ] **Step 2:** `cd mcp && npm test`, then `./build-app.sh`; report what is and is not verified (page look, section collapse, the Settings window's fit at 480x440, drag rules, the picker are all unverified UI). Tell the user to quit and reopen Sequence and to start a new Claude session before syncing.

---

## Self-review notes

- Coverage: one Tasks page, shared fixed columns, sections alphabetical and collapsible with persistence, tag on cards, split/merged setting, Saved separate, migration of the Ticket Oncall spelling, editor without columns, docs (Tasks 1 to 5).
- Interfaces match across tasks: `SlackColumns`, `SlackBoard.sections/merged/groups`, `saveTag(_:)`, `tasks(tags:includeArchived:)` are defined in Tasks 2 and 3 and used in Task 4. Tasks 2 and 3 leave the app target uncompiled; the ledger records it.
- Ruling vs spec: the setting is a Bool `groupTasksByTag` rather than `slackTasksGrouping` = `split`/`merged` (a Toggle needs a Bool); recorded in the ledger.
