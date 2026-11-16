---
name: sync-slack-tasks
description: Sync Slack threads into the Sequence tasks database, for all tags or only the ones named (reactions, Slack Saved). Use when the user says "sync my slack tasks", "sync my saved", "sync the <tag> tag", or asks to refresh their Slack task list or one task by number ("sync task #12").
---

# Sync Slack tasks

Copies Slack threads into the Sequence tasks database through the `sequence-vaults` MCP tools `list_slack_tags` and `upsert_slack_task`. Read-only on Slack.

## Rules

- Use only the Workbench tools (`mcp__workbench__execute_tools`). Never use the claude.ai Slack connector: it is signed in as a different person.
- Never write to Slack (no reactions, no messages).
- Never edit `status` or `archived`; the tool already keeps them. Never create or change tags; the app owns them.

## Steps

1. Call `list_slack_tags`. If the user named tags ("sync my saved", "sync the ticket tag", "sync todo and saved"), keep only those, matching what they said case-insensitively against each tag's `id` or `name`. If a name matches nothing, list the real tags, say so and stop without syncing anything. With no tag named, keep every tag.
2. For each kept tag, find its messages with `slack_search_all` (through `execute_tools`, `count` 20, following `page` until every hit is read):
   - each emoji in `reactions`: query `hasmy::<emoji>:` (for example `hasmy::loading:`);
   - `slack_list` `saved`: query `is:saved`;
   - `slack_list` `todo`: skip it and say it was skipped (Slack's To-dos list is not known to be readable yet). The tag's emoji reactions still sync.
   A thread found by several searches of the same tag is one card.
3. For a **board** tag, for each hit: `channel` = the hit's `channel.id`; `thread` = the `thread_ts` query parameter of the hit's `permalink` if present, otherwise the hit's `ts`. Call `slack_get_thread_replies` with `{"channel": <channel>, "threadTs": <thread>, "limit": 100}` and raise `limit` until `has_more` is false. `messages[0]` is the thread's first message: `thread_ts` = `messages[0].ts`, `snippet` = `messages[0].text`, `replies` = `messages.length - 1`, `last_reply` = the `ts` of the last message.
   For a **list** tag do not fetch the thread: use the hit itself: `thread_ts` = the `thread_ts` query parameter of its `permalink` if present, otherwise its `ts`; `snippet` = its `text`; `last_reply` = its `ts`; leave `replies` out.
4. Make the first `upsert_slack_task` call for each thread with `tag` (the tag's `id`), `channel_id`, `message_ts` (the hit's `ts`), `thread_ts`, `permalink` (the hit's), `channel_name` (the hit's `channel.name`; if there is none, such as in a DM, use the channel id), `snippet`, `last_reply` and, for board tags, `replies`.
5. Collect every result with `"summary_stale": true` (skip `archived` results) across all the tags synced. Take the 10 newest by `last_reply` and write, from the thread text you already have: a `summary` of about 140 characters (where it stands now) and, for **board** tags only, a `next_action` of about 100 characters (what the user should do or wait for; leave it out entirely if there is nothing to do, never send an empty string), in the language of the most recent messages. Call `upsert_slack_task` a second time for each with the same fields plus `summary` (and `next_action`). Leave the rest for the next sync.
6. Report, per tag, how many threads were `created`, `updated` and `archived` (skipped because the user archived them), how many were summarized, how many stale ones still wait, and which sources were skipped. List the created ones by their number (the `number` in the result, shown as #12 in Sequence), channel and summary.

## Single task mode

When asked to refresh one task by number ("sync task #12"), do not run the steps above for any tag. Instead:

1. Call `get_slack_task` with the number. If there is no such task, say so and stop. If it is archived, say so and stop.
2. Call `slack_get_thread_replies` with `{"channel": <channel_id>, "threadTs": <thread_ts>, "limit": 100}`, raising `limit` until `has_more` is false. `messages[0]` is the first message: `snippet` = `messages[0].text`, `last_reply` = the `ts` of the last message, and, for a **board** tag, `replies` = `messages.length - 1` (leave `replies` out for a list tag).
3. Call `upsert_slack_task` with the task's `tag`, `channel_id`, `message_ts` = `thread_ts`, `thread_ts`, `permalink`, `channel_name` (the task's, or the channel id if none), `snippet`, `last_reply` and `replies`.
4. If the result has `"summary_stale": true`, call it again with a `summary` (and, for a board tag, a `next_action`) as in step 5 above.
5. Report in one line: the number, the tag, whether it was updated, and the new summary.
