# Vault MCP server: design

## Intent

The user asks agents (Claude Code, Claude desktop) to create and edit files directly in their Sequence vaults. Today they copy a file path (the Copy path button in Sequence) and paste it to the agent. They want to say "update the settlement topic in qris-integration" and have the agent find and change the right file itself, safely, with a way to undo.

The existing `obsidian-vault` MCP (`@bitbonsai/mcpvault`, MIT) does this for markdown but its note tools refuse `.puml`, and most of the user's content is PlantUML. It also runs one server per vault and does not know Sequence's vault list. So: a small purpose-built MCP server.

## Vault model (user's words)

Folder per project, file name is the topic, the vault root is the workspace. Vaults are the ones Sequence already knows: `~/Library/Application Support/Sequence/vaults.json` (`{"vaults":[{"id","path","name"}]}`). Current vaults: `plantuml-flows` (`~/amartha-dock/plantuml-flows`) and `default` (`~/Documents/Sequence/default`). Neither is a git repo today.

## Goals

- "Project X, topic Y" resolves to one file without the user giving a path.
- Works for `.puml .plantuml .pu .wsd .md` (the types Sequence supports).
- Every agent write is undoable.
- Works in any MCP client that can start a local stdio server (Claude Code and Claude desktop at least).
- Reads `vaults.json` so vaults are configured once, in Sequence.

## Non-goals

- No delete, move or rename tools. The user does those in Sequence.
- No network transport, no auth, no remote access.
- Not an Obsidian feature clone: no frontmatter, tags or wiki-link tools.
- No fuzzy/semantic search. Name matching plus plain substring content search only.
- No change to the Sequence Swift app in v1.

## Anti-goals (a failure even if it works)

- Writing outside a vault, or to any file type outside the five above.
- Silently overwriting a file the user did not mention.
- Guessing between two matching files instead of asking.
- Committing the user's other files, or touching git config or remotes. (The only user work the server commits is the target file's own pending changes, as a snapshot before an agent edit.)

## Decisions made by the user

- Build a new server (not config-only, not a fork of mcpvault).
- Use git for undo; the server auto-commits after every agent write, and snapshots the target file's uncommitted changes first.
- Create fails if the file exists. Edits change one part of a file by default; a full overwrite is a separate, explicit tool.
- Local stdio only.

## Decisions made by me (the assistant); the user has not agreed to these

- **Stack:** TypeScript on Node (v24 is installed), official `@modelcontextprotocol/sdk` (MIT), `zod` for input schemas. Output compiled with `tsc` to `dist/`. Built output is what the MCP client runs: `node <path>/dist/index.js`.
- **Location:** `~/personal/sequence/mcp/`, next to the app, with its own `package.json`. Sequence `CLAUDE.md` Layout section gets one line describing it.
- **Tools** (all take an optional `vault` name; if omitted and more than one vault could match, return the candidates and do not act):
  - `list_vaults`
  - `list_projects(vault?)`: top-level folders in the vault.
  - `find_topic(query, project?, vault?)`: case-insensitive token match on file name (extension ignored), narrowed by project folder. Returns up to 10 `{vault, project, path}`, best first. One clear match is still returned as a list; the agent decides.
  - `search_content(query, project?, vault?)`: plain substring search, returns paths and the matching line.
  - `read_topic(path)`
  - `create_topic(vault, project, name, content)`: fails if the file exists or the project folder does not. A new project folder only via `create_project`.
  - `create_project(vault, name)`
  - `edit_topic(path, old, new)`: exact-string replace; `old` must occur exactly once or the call fails with the count. Same for markdown and PlantUML (no heading-aware editing in v1).
  - `overwrite_topic(path, content)`: full replace, separate tool on purpose.
- **Paths:** tools return and accept vault-relative paths plus the vault name; absolute paths are accepted only if they resolve inside a registered vault (so a path copied from Sequence still works).
- **Path safety:** `realpath` the target, require it inside the vault's real path, reject `..` escapes, symlink escapes and any path segment starting with `.`. Extension must be one of the five.
- **Git:** a write in a vault that is not a git repo is refused with an error telling the user to initialise it. The server never runs `git init`. Setup (one time, with the user's OK at that moment) is `git init` plus one baseline commit of the existing files in each vault. After each successful write the server runs `git add -- <file>` and `git commit -m "mcp: <create|edit|overwrite> <vault-relative path>" -- <file>`: only that file, plain message, no attribution trailer, no `--no-verify`, no remote. If the write succeeded but the commit failed, the tool reports both facts. A write that changes nothing makes no commit and is not an error.
- **Tests:** `node --test` with temp-directory vaults (real filesystem, real git). Written first for path safety, find ranking, create/edit/overwrite rules and commit behaviour.
- **Registration:** user-scope `claude mcp add` for Claude Code, and a snippet for Claude desktop config. The server reads `vaults.json` fresh on each call so vault changes in Sequence apply without restarting.

- **Reviewer follow-ups, my calls:** `read_topic`, `edit_topic` and `overwrite_topic` also take an optional `vault`; a vault-relative path that exists in more than one vault returns the candidates. Undo is manual (`git revert` / `git checkout` in the vault); there is no undo tool. `overwrite_topic` fails if the file does not exist. `create_topic` `name` must include one of the five extensions (no default). Writes are not size-limited beyond 1 MB. Baseline commit stages only the five supported file types; no `.gitignore`. A vault inside a parent git repo works: the server commits with the repo's toplevel and a pathspec for the one file. The concurrency with the Sequence app is documented, not mitigated.
- **Uncommitted changes (user decided):** before an agent write, if the target file has uncommitted changes, the server first commits that file as-is with the message `mcp: snapshot <vault-relative path> before edit`, then applies the agent's change and commits it. Only the target file is committed, never other files with pending changes. This is the one case where the server commits the user's own work; it exists so the agent's change can be undone without losing the user's edits. An untracked target file (new, never committed) that the agent edits gets the same snapshot.

## Constraints

- Sequence has a file watcher; the server only writes files, so edits should appear in the app. Verifying the app's behaviour when a file with unsaved edits is changed on disk is left to the builder (read `FileWatcher` and `DocumentSession`); the server does not try to coordinate.
- Unsigned, personal tool: no packaging beyond `npm run build`.
- The user's global rule: no commits made by the assistant without an explicit request. This applies to this repo's work; the server's auto-commit happens inside vaults at runtime and is separate.

## Left to the builder

- Exact error message wording and result JSON shapes.
- Ranking details for `find_topic` beyond "all query tokens must appear, more or earlier matches first".
- Whether `vaults.json` parse errors fall back to an env var (`SEQUENCE_VAULTS`) for testing.
