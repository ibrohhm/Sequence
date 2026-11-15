---
name: sync-slack-tasks
description: Sync Slack threads tagged with the :loading: reaction into the Sequence tasks database. Use when the user says "sync my slack tasks" or asks to refresh their Slack task list.
---

# Sync Slack tasks

Copies the Slack threads the user tagged with `:loading:` into the Sequence tasks database through the `upsert_slack_task` tool (MCP server `sequence-vaults`). Read-only on Slack.

## Rules

- Use only the Workbench tools (`mcp__workbench__execute_tools`). Never use the claude.ai Slack connector: it is signed in as a different person.
- Never write to Slack (no reactions, no messages).
- Never edit `status` or `archived`; the tool already keeps them.

## Steps

1. Call `slack_search_all` through `execute_tools` with `{"query": "hasmy::loading:", "count": 20}`. Follow `page` until every hit is read.
2. For each hit: `channel` = the hit's `channel.id`; `thread` = the `thread_ts` query parameter of the hit's `permalink` if present, otherwise the hit's `ts`. Call `slack_get_thread_replies` with `{"channel": <channel>, "threadTs": <thread>, "limit": 100}`. If `has_more` is true, raise `limit` until it is false.
3. From the result: `messages[0]` is the thread's first message. `replies` = `messages.length - 1`. `last_reply` = the `ts` of the last message. `snippet` = `messages[0].text`. `thread_ts` = `messages[0].ts`.
4. Make the first `upsert_slack_task` call for each thread with `channel_id`, `message_ts` (the hit's `ts`), `thread_ts`, `permalink` (the hit's), `channel_name` (the hit's `channel.name`), `snippet`, `replies`, `last_reply`.
5. If the result has `"summary_stale": true`, write from the thread text you already fetched: a `summary` of about 140 characters (where the thread stands now) and a `next_action` of about 100 characters (what the user should do or wait for; leave it out if there is nothing to do), in the thread's language. Call `upsert_slack_task` a second time with the same facts plus `summary` and `next_action`. If there is nothing to do, leave `next_action` out entirely; never send an empty string (the tool rejects it). Use the language of the most recent messages in the thread. Skip the second call when `summary_stale` is false or the action is `archived`.
6. Report how many threads were `created`, `updated`, `archived` (skipped because the user archived them) and `summarized`, and list the created ones by channel and summary.
