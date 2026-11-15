# Slack tasks: design

## Intent

The user loses track of Slack threads and forgets follow-ups. They want a section in Sequence that tracks their tasks from Slack: when they add the `:loading:` reaction to a thread, it appears in Sequence as a card with a quick overview, and clicking the card opens that Slack thread. They can also add and remove cards and move each between four statuses (todo, in progress, blocked, done) by hand.

The card must help them decide whether a thread needs them now: channel, the first-message snippet, reply count, last activity, how many replies arrived since they tagged it, and a warning when the thread has gone quiet.

## Decisions made by the user

- **Data source:** the Amartha Workbench (`https://workbench-uat.amartha.id/mcp`, already registered as the `workbench` MCP server in Claude Code), signed in as the user (`syarif.ibrohim@amartha.com`). Verified: `slack_search_all` with query `hasmy::loading:` returns the tagged thread with channel, text and permalink. The Slack connector attached to claude.ai is signed in as a different person and must not be used.
- **Sequence has no Slack code and no Slack or Workbench token.** An agent fetches from Slack; a tool in the existing `mcp/` server writes to storage; Sequence reads the storage and shows the board.
- **Storage is one SQLite database file**, not vault files and not JSON. (The user asked why a vault is needed; the vault idea was dropped.)
- **Card content (option B):** channel, snippet, reply count, last activity, "N new replies since you tagged it", and a quiet warning. No AI summary.
- **Statuses:** `todo`, `inprogress`, `blocked`, `done`, moved manually in Sequence.
- **Click** opens the Slack thread.
- **Add and remove cards** in Sequence.
- **Sync trigger:** manual only. The user tells an agent "sync my Slack tasks". No background job in this version.
- **Remove = archive:** a removed card is flagged archived; sync never brings an archived thread back, and the user can restore it. Removing does not touch Slack.

## Goals

- A thread tagged `:loading:` becomes a card in Todo after the next sync.
- Re-running sync never duplicates a card and never changes `status` or `archived`.
- The user sees at a glance which threads have new replies or have gone quiet.
- Sequence and the sync tool can write the same database at the same time without corrupting it or losing each other's columns.

## Non-goals

- No automatic or scheduled sync, no notifications.
- No AI summaries of threads.
- No writes to Slack (no removing the emoji, no replies).
- No emoji other than `:loading:` (the exact name is a constant that can change), no multi-user board.
- Sequence never calls Slack or the Workbench.
- No git history or markdown view of cards.

## Anti-goals (a failure even if it technically works)

- Sync overwriting a status or archived flag the user set.
- Duplicate cards for one thread, or an archived thread coming back.
- Any Slack write, or any use of the claude.ai Slack connector (a different person's account).
- Sequence or the tool leaving the database locked or corrupted when both run at once.

## Approaches considered

1. **Sequence talks to Slack itself** with its own Slack app and token. Needs a Slack app (possible admin approval) and token and network code in Swift.
2. **Claude as a background syncer** via the claude.ai Slack connector. Blocked by the connector being another person's account; costs tokens.
3. **Manual links only.** Does not solve discovery.
4. **Sequence calls the Workbench itself.** Puts a Workbench token and network code in the app; token lifetime unknown.
5. **Cards as markdown files in a vault, agent fetches, MCP tool writes.** Dropped by the user: it needed a vault choice, two YAML parsers, a file-naming scheme and an archive folder.
6. **Chosen: an agent fetches through the Workbench, a tool in the `mcp/` server writes to a SQLite database, Sequence is the board over it.** SQLite is built for two programs writing one file, so each side updates only its own columns. The user chose this over two JSON files (also considered: it needs one file per writer to avoid conflicts).

## The design

### Storage

`~/Library/Application Support/Sequence/slack-tasks.db`, next to `vaults.json`; env `SEQUENCE_SLACK_DB` overrides the path (tests). SQLite in WAL mode with a busy timeout (my call: 5 s). Both programs open it, run the same `CREATE TABLE IF NOT EXISTS` and set `PRAGMA user_version = 1`.

Table `tasks`:

| column | type | owner | meaning |
|---|---|---|---|
| `channel_id` | TEXT | sync / board | with `thread_ts`, the primary key |
| `thread_ts` | TEXT | sync / board | Slack ts of the thread's first message, e.g. `1794536057.965929` |
| `permalink` | TEXT | sync / board | link to the thread root, no query string |
| `channel_name` | TEXT, nullable | sync | blank until first sync for board-added cards |
| `snippet` | TEXT, nullable | sync | root message text |
| `replies` | INTEGER, nullable | sync | reply count at last sync |
| `replies_at_tag` | INTEGER, nullable | sync | reply count at first sync that had facts; never changed afterwards |
| `last_reply` | TEXT, nullable | sync | ISO time of the last message (root time if no replies) |
| `tagged` | TEXT | sync / board | ISO date the card was created |
| `synced` | TEXT, nullable | sync | ISO time of last sync |
| `status` | TEXT, default `todo`, one of the four statuses | Sequence | |
| `archived` | INTEGER, default 0 | Sequence | 1 = removed from the board |

"N new" = `replies - replies_at_tag` when both exist. Quiet = status is not `done` and now minus the later of `last_reply` and `tagged` is more than N days (my call: N = 5) and both facts exist.

### Stage 1: connector (build first)

**New tool `upsert_slack_task`** in `mcp/` (the existing `sequence-vaults` server; my call: same server so there is one registration). Input: `channel_id`, `message_ts` (required: the tagged message), optional `thread_ts` (the thread's first message; if absent it is taken from the permalink's `thread_ts` query, else `message_ts`), `permalink`, `channel_name`, `snippet`, `replies`, `last_reply`. Both timestamps must look like `1794536057.965929`; `last_reply` is a Slack ts (integer or fractional) or an ISO time with a zone. Behaviour:
- Find the row by `(channel_id, thread_ts)`; if none and `message_ts` is given, find by `(channel_id, message_ts)` (a card the board created from a reply link) and re-key it to `thread_ts`.
- Archived row: change nothing, report `archived`.
- Existing row: set `permalink`, `channel_name`, `snippet`, `replies`, `last_reply`, `synced`; set `replies_at_tag` only if it is NULL. Never touch `status`, `archived`, `tagged`. Report `updated`.
- No row: insert with `status = todo`, `archived = 0`, `tagged` = today, `replies_at_tag = replies`. Report `created`.
- Uses `node:sqlite` (built in; prints an experimental warning to stderr, which must not disturb the stdio protocol). If it breaks in a later Node version the fallback is `better-sqlite3`.

**Sync instructions.** The agent runs, through the Workbench `execute_tools`: `slack_search_all` with `hasmy::loading:` (hits carry `channel.id`, `channel.name`, `ts`, `text`, `permalink`); then for each hit `slack_get_thread_replies` with `{channel, threadTs, limit}` (verified: returns `{ok, messages[], has_more}`, `messages[0]` is the root, there is no reply-count field), so `replies = messages.length - 1`, `last_reply` = last message `ts`, snippet = `messages[0].text`; page or raise `limit` if `has_more`. A hit that is a reply gives `thread_ts` from the reply's thread info (the root's ts) and `message_ts` = the hit's `ts`. Then it calls `upsert_slack_task`. Where these instructions live (a skill or a Claude config note) is left to the builder; adding anything to the user's Claude config needs the user's approval at that time.

### Stage 2: board in Sequence

- `StudioCore/SlackTaskStore.swift`: a small wrapper over the C `SQLite3` API (no package) with `all(includeArchived:)`, `setStatus`, `archive`/`restore`, `add(link:)`; tests first against a temp database. `StudioCore/SlackLink.swift`: parses a Slack message link (`https://<host>/archives/<channel>/p<digits>[?thread_ts=...]`) into host, channel id, ts and optional thread ts (`p1794536057965929` → `1794536057.965929`).
- A new rail icon opens "Slack tasks": four columns of cards for `archived = 0`. A card shows channel name (or the channel id when blank), snippet, replies, last activity, a dot with "N new", and a warning when quiet.
- Dragging a card to another column sets `status` for that one row. Clicking opens `permalink` in the default handler. Add: paste a Slack link, which inserts a row (status `todo`, ids and permalink from the link, facts blank, keyed by `thread_ts` from the link if present, otherwise the link's ts). Remove sets `archived = 1`. A "Show archived" toggle lists archived cards with a Restore button.
- The board shows new data within a few seconds without restarting (mechanism, for example polling `PRAGMA data_version`, left to the builder).
- Views are not unit tested (project rule); the user cannot be shown a screenshot from here, so look and feel is reported as unverified.

## Details settled after review (my calls, for the user to check)

- **"I tagged it":** `hasmy::loading:` is a Slack search modifier meaning "messages I reacted to with this emoji". Verified through the Workbench (signed in as the user): it returned the one thread the user had tagged, and that thread's reaction was by the user's id. Other people's `:loading:` reactions are not matched.
- **Removing the emoji in Slack does nothing.** The card stays until the user moves it to Done or archives it. Retiring cards when the reaction disappears is out of scope (it would need a new column and a sync rule).
- **Quiet counts any reply.** `last_reply` is the last message by anyone, including the user, so the warning means "this thread has been silent for N days", which covers both "needs me" and "waiting on others". There is no user-identity concept in the schema.
- **Thread root for a reply hit:** take `thread_ts` from the hit's `permalink` query string; if there is none, the hit's `ts` is the root. If a hit carries neither, the agent calls `slack_get_thread_replies` on its `ts` and uses the root from the result. The same parsing rule is used for pasted board links.
- **Board link with no `thread_ts`** is treated as a root message. Real Slack permalinks for replies carry `thread_ts`, so a stray orphan is only possible for a hand-edited link; accepted.
- **Accepted gap:** if the board holds a row keyed by a reply ts (a hand-edited link without `thread_ts`) and sync has already created the root row, sync does not merge the two; the user archives the stray card. Needs a hand-edited link to happen.
- **`tagged` is the UTC date** (a card created 00:00 to 07:00 in Jakarta gets the previous day). The board's add must use the same convention.
- **Pasting a link for an already archived thread restores it** (the user is adding it on purpose).
- **Schema parity:** two copies of the DDL (one in `mcp/`, one in `StudioCore`), with a test in `mcp/` that reads the Swift file and compares the DDL text.
- **Stage 1 includes a live acceptance step:** after the tool tests pass, run the sync flow once against the real Workbench (read-only Slack calls) into a temporary database, check the rows, and only then point it at the real database. This needs the user's go-ahead at that time.
- **Versions:** the Stage 1 `mcp/` commit does not bump `VERSION` (the app is unchanged). The Stage 2 board is a `feat` and bumps the minor version.

## Verified in this session

`import SQLite3` works in Swift with the installed Command Line Tools; `node:sqlite` works on Node v24.8.0; Node wrote a row, Swift updated it, and Node read the update back, in one WAL database file.

## Constraints

- Sequence rules (`CLAUDE.md`): logic in `StudioCore` with tests first, no `.toolbar`, plain stacks layout, theme colours only from `Theme.swift`, version bump rule (`feat` = minor).
- `mcp/` code stays TypeScript with `node --test`; the new tool needs tests against a temp database.
- The Workbench URL is the UAT one; its token stays in the user's Claude Code config and is never copied into Sequence or this repo.

## Left to the builder

- Exact DDL text and index choices; keeping the Swift and TypeScript DDL identical (a test in each suite that checks the schema).
- Timestamp formats, the `quiet` threshold constant, and the board's look (card size, column widths, drag mechanics; the sidebar already uses `.draggable` / `.dropDestination`).
- How the board refreshes, and where the sync instructions live.
