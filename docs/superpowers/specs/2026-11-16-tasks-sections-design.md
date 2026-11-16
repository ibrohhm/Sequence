# Tasks page with tag sections: design

Builds on `2026-11-15-slack-tags-design.md` and `2026-11-15-slack-tasks-design.md` (tags, board, database, sync tool). Read those first; this document only describes what changes. Current state: commit `ed051de`, database schema v4, `VERSION` 1.25.1.

## Intent

Today every board tag (To-do, Ticket Oncall, any new one) has its own page with its own columns. The user wants all of them on one page called **Tasks**, with the same four columns everywhere, each tag as a collapsible section, and a setting to show the sections split or merged into one board. Saved (a list tag) stays its own page.

## Decisions made by the user

- **One page, "Tasks"**, replaces the per-tag board pages. Every tag of kind `board` (To-do, Ticket Oncall, and tags added later) appears on it. The page title is "Tasks" (it was "Slack tasks").
- **Saved stays separate**: list tags keep their own tab and plain list.
- **All tags share the same four columns:** Todo, In progress, Blocked, Done.
- **Layout (the user's sketch):** each tag is a section with its own header; inside every section the four column headers are repeated, then the cards:
  ```
  ▾ Ticket Oncall
  Todo     In progress   Blocked    Done
  [card]

  ▾ To-do
  Todo     In progress   Blocked    Done
  [card]
  ```
- **Sections are collapsible and ordered alphabetically** by tag name. A collapsed section stays collapsed (remembered across launches).
- **Each task shows its tag.**
- **A setting** chooses whether tags are split into sections or merged into one board.

## Decisions made by me (for the user to check)

- **Columns are fixed**, not editable (the user described them as "same column"; I asked and they answered with the layout only). The per-tag column editor in the Slack tags window goes away.
- **Default is split** (sections). The setting is "Group tasks by tag" in the Settings window, General tab, stored in UserDefaults `slackTasksGrouping` (`split` or `merged`).
- **Dragging a card changes its status only, never its tag:** in split mode a drop works only inside the card's own section; in merged mode a drop works on any column.
- **The tag is shown as a chip on every card in both modes** (it is redundant in split mode but the user asked for it on the task).
- **Pasting a link adds a card to the tag chosen in a small picker next to the field**, default To-do, last choice remembered; on a list tag's page it adds to that list.
- **Alphabetical** means case-insensitive comparison of the tag name; it replaces `position` for sections (position still orders the list-tag tabs).
- **Merged mode** shows one set of four column headers; cards from all tags are sorted by latest activity, newest first; the tag chip tells them apart.
- **A tag with no cards** still shows its section (header and empty columns), so the structure stays visible.
- **Archived cards:** one "Archived" list at the bottom of the Tasks page covers every board tag, each row showing its tag; the "Archived" toggle stays in the page header; Restore works as today. A list tag's page keeps its own archived list.
- **A tag's kind is fixed once it is created** (the Slack tags window already disables the kind picker for existing tags), so no card is ever switched between board and list and no status rewrite is needed on a kind change.
- **Collapse state** is stored in UserDefaults `slackTagsCollapsed` (array of tag ids).
- **Page selection:** the pages are "Tasks" followed by each list tag in `position` order. The remembered page (`slackTagSelected`) becomes `tasks` or a list tag id; an old value that is a board tag id becomes `tasks`.

## Goals

- All board-tag cards appear on one Tasks page in the four shared columns; Saved is unchanged.
- Existing cards keep their meaning: statuses are normalised to the four columns (see Migration).
- Collapse state and the split/merged choice survive restarts.
- The sync tool keeps working unchanged for the agent, and new board cards start in Todo.

## Non-goals

- No per-tag columns, no editable shared columns.
- No moving a card to another tag by dragging.
- No change to list tags, the sync flow, ticket numbers or summaries.
- No setting for the sort order of sections.

## Anti-goals

- Any card disappearing because its stored status matches none of the four columns (it must be migrated, and any leftover unknown status shows in Todo as before).
- A collapsed section re-expanding on its own after a sync or a refresh.
- The sync tool and the app disagreeing on what a board tag's columns are.

## The design

### Fixed columns

One constant list in `StudioCore`: `SlackColumns.all = ["Todo", "In progress", "Blocked", "Done"]`; the last ("Done") counts as done (no quiet warning). `SlackBoard` groups cards by these names; a card whose status is not one of them shows in "Todo" (display only), as today.

### Migration (schema v5, both programs)

No DDL change. `user_version` becomes 5. In one `BEGIN IMMEDIATE`, in both the Node `openDb` and the Swift store (same rule in both, tested in both):
- For every board tag set `columns` to the standard four (JSON text identical in both languages).
- For every card of a board tag, normalise `status`: compare case-insensitively with spaces and hyphens removed against `todo`, `inprogress`, `blocked`, `done` and rewrite to the canonical name; anything else (including `''`) becomes `Todo`. Cards of list tags are left alone.
The user's real database (user_version 4) has one board card with status `Inprogress` (tag Ticket Oncall, columns `["Todo","Inprogress","Blocked","Done"]`) and two `Todo` cards in To-do; the migration must fix the first. The real database is backed up before the new code first opens it.

### Node sync tool

- New board cards get status `Todo` (a constant), not `tag.columns[0]`.
- `list_slack_tags` keeps returning `columns`; for board tags it is always the standard four. Everything else is unchanged.

### Swift store and rules

- `saveTag` for a board tag always stores the standard four columns and ignores any other list passed in; the column rename/remove logic is deleted. `SlackTagRules.validate` no longer validates columns (a board's columns are not an input).
- New: `SlackBoard.sections(_ tasks: [SlackTask], tags: [SlackTag]) -> [(tag: SlackTag, columns: [(name: String, tasks: [SlackTask])])]`: board tags only, sorted by name case-insensitively, each with the four column groups (archived cards excluded, newest activity first, unknown status in Todo); and `SlackBoard.merged(_ tasks:, tags:) -> [(name: String, tasks: [SlackTask])]` for merged mode.
- `SlackTaskStore` gains `tasks(tags: [String], includeArchived: Bool)` (cards of several tags in one query, or the existing method called per tag; builder's choice).

### App

- The page tabs: "Tasks" plus each list tag. The header title reads "Tasks" on that page. The "Edit tags…" button and the paste field stay; the paste field gets the tag picker (board tags only on the Tasks page).
- Split mode: for each section in alphabetical order, a header row (chevron, tag name, card count; click toggles) and, when expanded, the four column panels with their headers (status icon and count). Merged mode: one set of columns.
- Cards: as now, plus a tag chip (neutral chip with the tag name).
- Drop rules as above; the existing hover/targeted styling is kept; no animation.
- Settings window, General tab: a toggle "Group tasks by tag" with a one-line explanation. The settings window stays 480x440.
- Slack tags window: remove the columns editor; keep name, kind (custom tags), emoji names, order, delete.
- Empty state for the Tasks page when no board tag has any card.

## Constraints

- `mcp/skills/sync-slack-tasks/SKILL.md` and `CLAUDE.md` mention per-tag columns and the old page structure; both are updated as part of the change.
- Project rules (`CLAUDE.md`): logic in `StudioCore` with tests first, views not unit tested, colours from `Theme`, no `.toolbar`, native alerts, say what is unverified, `feat` bumps the minor version.
- Both programs implement the v5 migration identically; both back it with tests. The user's real database is backed up first and checked on a copy.
- `PRODUCT.md` principles (calm, status never by colour alone, no required motion) apply to the new section headers and chips.

## Left to the builder

- Exact section header styling, chevron icon and spacing; how the picker looks; the wording of the setting's help text.
- Whether the Swift store loads all board cards with one query or one per tag.
- How the page selection migration from the old `slackTagSelected` value is written.
