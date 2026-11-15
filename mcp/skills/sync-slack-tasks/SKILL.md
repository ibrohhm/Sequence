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
4. Call `upsert_slack_task` once per thread with `channel_id`, `message_ts` (the hit's `ts`), `thread_ts`, `permalink` (the hit's), `channel_name` (the hit's `channel.name`), `snippet`, `replies`, `last_reply`.
5. Report how many threads were `created`, `updated` and `archived` (skipped because the user archived them), and list the created ones by channel and snippet.
