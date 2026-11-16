# Slack tags: design

Builds on `docs/superpowers/specs/2026-11-15-slack-tasks-design.md` (board, SQLite database, sync tool, summaries), which is committed as `0529849` and `da734d9`. Read that first; this document only describes what changes.

## Intent

Today the board tracks one thing: threads the user reacted to with `:loading:`. The user wants **tags**: each tag has a name, ways a Slack message gets that tag, and its own page in Sequence. Examples from the user: a `ticket` tag fed by the 🎫 reaction; a `todo` tag fed by `:loading:` / `:loading1:`; a `bookmark` tag that shows a list of bookmarks. Slack's own To-dos and Saved lists get a tag each by default; every other tag is the user's to configure.

## Decisions made by the user

- **One page per tag.** Each tag has a kind: **board** (status columns) or **list** (no statuses; a bookmark is not a task).
- **Columns are configurable per board tag** (names, order, count).
- **Built-in tags:** Slack **To-dos** and Slack **Saved** each get a tag by default. All other tags are configurable.
- **Statuses become free text.** The Swift `SlackStatus` enum is replaced by per-tag column names; the existing `SlackBoard`, `SlackTask` and store tests are rewritten for it (no compatibility with the old enum is needed).
- **Saved items:** Slack's "Add to saved" (the Saved section of Home) is a bookmark with no status. Slack's "Add to-do" (the To-dos tab, formerly Later) is an actionable item with an optional due date. Slack shows no state field on a saved item through search, so every saved item is just a card the user arranges.
- **The first sync imports everything** a tag finds (the user has 50 saved items; all 50 come in). Summaries are written in batches: each sync run writes at most 10 (the newest stale ones) and the rest follow on later runs.
- **Edited in the app**, in a settings editor (approach A). Not by asking the agent and not in a hand-edited file.
- Everything from the earlier design still holds: sync is manual and run by an agent through the Workbench, Sequence has no Slack code or token, removing a card archives it, removing a reaction or unsaving does nothing, `summary` and `next_action` on cards.

## Goals

- A user can create, rename, reorder and delete tags in the app, set a tag's emoji reactions, and set a board tag's columns.
- "Sync my Slack tasks" fetches every tag's source and puts cards on the right pages.
- Existing cards are not lost and the existing database upgrades in place.
- The same thread tagged twice appears on both pages with its own status on each.
- **Sync can be limited to specific tags** ("sync my saved", "sync the ticket tag", "sync todo and saved"); with no tag named, it syncs every tag.

## Non-goals

- No tag editing by the agent, no hand-edited tag file.
- No card with several tags (a thread tagged twice is two cards).
- No automatic sync.
- No Slack writes (no reactions added or removed, nothing un-saved).
- No reading of a To-dos due date or completed state (Slack exposes none through search).

## Anti-goals

- A column rename or delete that strands cards in a status no column shows.
- Sync overwriting a status, `archived`, or tag of an existing card.
- Deleting a tag destroying its cards.
- The app and the Node tool disagreeing on the schema (parity test covers both tables).

## Approaches considered

- **A. Tags in the database, edited in the app (chosen).** Largest, but it is what the user asked for; the app is the one writer of tag settings, the sync tool only reads them.
- **B. Tags in the database, edited by asking the agent.** Smaller; rejected by the user.
- **C. A hand-edited JSON file.** Least work, no checking; rejected.

## The design

### Schema v3

Both programs (Swift `SlackTaskStore`, Node `openDb`) create and upgrade the same schema, with identical DDL text for **both** tables (the existing parity test is extended to compare both).

Table `tags` (written only by the app):

| column | type | meaning |
|---|---|---|
| `id` | TEXT primary key | slug of the name, unique, e.g. `ticket` |
| `name` | TEXT NOT NULL | shown on the page tab |
| `kind` | TEXT NOT NULL, `board` or `list` | |
| `slack_list` | TEXT NOT NULL, `none`, `todo` or `saved` | which of Slack's own lists also feeds this tag |
| `reactions` | TEXT NOT NULL, JSON array of emoji names without colons, e.g. `["loading","loading1"]` | any tag can have reactions, in addition to `slack_list` |
| `columns` | TEXT NOT NULL, JSON array of column names | board only; `[]` for a list; at least 1, unique, at most 8 |
| `position` | INTEGER NOT NULL | tab order |
| `builtin` | INTEGER NOT NULL DEFAULT 0 | 1 = cannot be deleted; its `slack_list` and `kind` cannot change |

Table `tasks` is rebuilt (inside `BEGIN IMMEDIATE`: create the new table, copy rows, drop the old, rename): it gains `tag TEXT NOT NULL`; the primary key becomes `(tag, channel_id, thread_ts)`; the `CHECK` on `status` is removed and `status` holds a **column name**; every other column is unchanged (including `summary`, `next_action`, `summary_replies`). `user_version` becomes 3. The upgrade must be safe if Node and Swift open the file at the same moment and safe to run twice.

Seeds written by the upgrade, only when `tags` is empty:
- `todo`: name "To-do", builtin, `slack_list` `todo`, reactions `["loading","loading1"]` (editable), kind `board`, columns `["Todo","In progress","Blocked","Done"]`, position 0. **My call, from the user's example** ("todo will have reaction :loading: and :loading1: or save it on my todo slacks"): the built-in To-do tag is fed by Slack To-dos **and** by those two reactions. All existing cards (they came from `:loading:`) move to this tag; their status values `todo`, `inprogress`, `blocked`, `done` are rewritten to `Todo`, `In progress`, `Blocked`, `Done`.
- `saved`: name "Saved", builtin, `slack_list` `saved`, reactions `[]` (editable), kind `list`, columns `[]`, position 1.

Fresh databases get the same two seeds. Custom tags always have `slack_list` `none`. A tag's `id` is a slug made once at creation and never changes on rename (cards reference it); a new tag whose slug equals a live tag's id gets a numeric suffix.

### Columns and statuses

- A board tag's columns are an ordered list of names. A card's `status` is one of them; a card whose status matches no column (e.g. after an edit elsewhere) is shown in the first column; the stored status is left alone (display-only fallback, no repair pass), and quiet suppression follows the column the card is shown in.
- The first column is where new cards land. The last column counts as "done": cards there get no quiet warning (**my call**).
- Renaming a column in the editor rewrites `status` for that tag's cards in the same transaction; deleting a column moves its cards to the first column in the same transaction.
- A list tag has no columns and no status; `status` is stored as an empty string and never shown.

### Sources and sync

- **Reactions:** for each emoji name of a tag, the search `hasmy::<name>:` (verified for the custom emoji `loading`).
- **`slack_list` `saved`:** the search `is:saved` (verified: returns the user's Saved items with channel and permalink; the user has 50).
- **`slack_list` `todo`:** **unverified.** Slack search has no modifier for the To-dos tab (`is:todo` and `is:later` only matched the words). The first build task is a spike that tests whether To-dos can be read (for example whether `is:saved` also returns items added with "Add to-do", by having the user add one and comparing counts); its result is recorded in this document. If they cannot be read, the To-do tag keeps working through its reactions, its page shows a note that the Slack To-dos list is not readable, and sync skips that source. No de-duplication between tags: a thread returned by sources of two tags is a card in each; within one tag, two sources returning the same thread are one card.
- A search may return many pages; the skill follows all pages.
- **Board tags** fetch each thread (`slack_get_thread_replies`) for replies, last activity and the first message. **List tags** do not fetch threads (so 50 saved items cost no thread calls): the card is the message the search returned, `snippet` is that message's text, `replies` is NULL, `last_reply` is that message's time, and the permalink is the search hit's.

### Sync tool changes (`mcp/`)

- **New read tool `list_slack_tags`**: returns every tag (`id`, `name`, `kind`, `slack_list`, `reactions`, `columns`), ordered by `position`.
- **`upsert_slack_task` gains required `tag`** (a tag id); an unknown tag id is an error and writes nothing. For a `list` tag `replies` may be omitted (stored NULL) and the card is stale only when it has no summary; for a `board` tag `replies` stays required. The tool reads the tag's columns inside its own `BEGIN IMMEDIATE`, so a concurrent column edit cannot leave a new card with an outdated first-column name. Identity becomes `(tag, channel_id, thread_ts)`; the re-key and archived rules apply within the tag. New cards get `status` = the tag's first column (`""` for a list). For a `list` tag, `next_action` is rejected (a list shows the summary only). Everything else about the tool (never touching `status`, `archived`, `tagged`; `summary_stale`; validation) is unchanged.
- **Skill:** the trigger phrases are "sync my Slack tasks" (all tags) and the same naming one or more tags. The agent calls `list_slack_tags`, keeps only the tags the user named (matched case-insensitively against `id` or `name`; if a named tag does not exist it says so, lists the real tags and stops without syncing anything), then for each kept tag run its source search (all pages), fetch each thread, call `upsert_slack_task` with the tag; collect the threads reported stale across the synced tags first, then write summaries for at most 10 of them in total (newest first), reporting how many are still waiting.

### App

- The rail's Slack tasks icon opens the board area; its header shows the tag tabs (in `position` order) and an "Edit tags…" button that opens the Slack tags editor window.
- A **board** tag shows its columns (existing board look). A **list** tag shows one list of cards (channel, summary, age, replies) with the same click, archive and restore actions and no drag between columns.
- Pasting a link adds the card to the page you are on.
- The existing empty state per tag: "No cards yet. Add the emoji … or tell Claude 'sync my Slack tasks' (or 'sync the <tag> tag')." Tag-specific text for the To-do tag when unreadable.
- **Editor: a separate native window "Slack tags"** (resizable, opened from the board header's "Edit tags…" button; not a Settings tab, because the Settings window is a fixed 480x440): a list of tags with move up/down and add; selecting one edits its name, kind (custom tags only), emoji names (text field of comma-separated names, validated `[a-z0-9_+-]+`, shown without colons) and its columns (add, rename, reorder, delete; board tags only). Built-in tags: name, emoji names and (To-do) columns are editable; kind, Slack list and deletion are not. Delete asks for confirmation; deleting a custom tag hides its cards but does not delete them (re-creating a tag with the same id shows them again). Dialogs are native alerts, never in-window sheets (project rule).
- Tag settings are written only by the app; the sync tool never writes `tags`.

## Constraints

- Project rules (`CLAUDE.md`): logic in `StudioCore` with tests first, views not unit tested, theme colours only from `Theme.swift`, no `.toolbar`, say when UI is unverified, version rule (`feat` = minor).
- The DDL of both tables must be identical in `mcp/src/slackdb.ts` and `Sources/StudioCore/SlackTaskStore.swift`.
- The user's real database (2 cards, v2 today) is backed up before the new code first opens it.

## Left to the builder

- Slug rules for tag ids; the editor layout; tab styling; maximum tag count.
- How the migration seeds interact with the parity test; helper structure in `StudioCore`.
- Whether the spike for the To-do source is done by the builder with the user's help or by asking the user for one action.
