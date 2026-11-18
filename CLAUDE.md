# Sequence

Personal Mac app (SwiftUI, no Xcode) to browse, view and edit PlantUML and markdown files. Not signed or notarized.

## Layout

- `Sources/StudioCore`: UI-free engine (renderer, scanner, watcher, file ops, `DocumentSession`, `MarkdownPreparer`, `TextSearch`).
- `App/`: SwiftUI + AppKit views, `AppModel` (all app state). Files are grouped by feature: `Model/` (`AppModel*`, `VaultStore`), `Shell/` (`RootView`, `ChromeButtons`, `PageHeader`, `WindowConfigurator`, `SetupMessageView`), `Sidebar/`, `Editor/` (`MainView`, `CodeEditor`, `PromptBar`, `PlaygroundView`), `Diagram/` (`DiagramWebView`, `SVGView`), `Markdown/` (`MarkdownPane`, `MarkdownView`), `SlackTasks/`, `Flows/`, `Settings/` (`SettingsView`, `VaultsView`, `AboutView`); `SequenceApp`, `Theme` and `AppResources` stay at the `App/` root. New code goes in its feature's folder. Find bundled files with `AppResources.url`/`.text`, never `#filePath`, which breaks when a file moves. `AppModel.swift` holds every stored property plus documents (open, render, save, export), find/format and page switching; features are extensions in their own files: `AppModel+Vaults` (vaults, open root, folder expansion, rescan), `AppModel+Files` (sidebar new/rename/move/delete, `perform`), `AppModel+Playground`, `AppModel+AI`. Stored properties must stay in `AppModel.swift` (extensions cannot hold them); members used across these files are internal, not `private`. Each window owns an `AppModel` (`WindowRoot` in `SequenceApp.swift`); menu commands reach the focused window's model through `focusedSceneObject`. Only the first window restores the last folder (`AppModel.claimRestore`).
- Feature details live in `docs/features/`. Read the feature's doc before changing it, and update it in the same commit:
  - `shell.md`: window root (`RootView`), `IconRail`, `PageHeader`, `MainView`
  - `sidebar.md`: file tree, new/rename/move/delete, folder expansion
  - `vaults.md`: vaults and the Settings window
  - `editor.md`: markdown formatting (⌘B/⌘I), AI prompt (`PromptBar`, `AIEditor`)
  - `playground.md`: scratch PlantUML and markdown files
  - `diagrams.md`: `DiagramWebView` (Copy Image, pinch zoom), markdown preview diagrams (expand overlay), `App/Resources`
  - `slack-tasks.md`: Slack tasks board, tags, sync, SQLite schema
  - `flows.md`: Flows page (React Flow)
  - `mcp.md`: stdio MCP server in `mcp/` (vault topics, Slack tasks, flows tools)
- `Tests/StudioCoreTests`: Swift Testing suites.
- `docs/superpowers/`: design spec and plan.

## Commands

- `./test.sh`: run tests. Only Command Line Tools are installed (macOS too old for Xcode), so tests use Swift Testing with CLT framework flags. Do not use `swift test` directly or XCTest.
- `./build-app.sh`: build `build/Sequence.app`. Quit the running app (⌘Q) first, or reopening shows the old build.
- After every app change: quit the running app (`osascript -e 'quit app "Sequence"'`, wait until it exits), run `./build-app.sh`, then `open build/Sequence.app`.
- Run `./test.sh` before every commit.
- Version: the `VERSION` file (semver `major.minor.patch`) is the single source; `build-app.sh` writes it into Info.plist and About shows it. Every commit that changes the app bumps it in that same commit, by commit type: `feat` = minor (patch resets to 0), `fix`/`refactor`/`perf` = patch, a breaking change (removed shortcut, changed file or settings format) = major (minor and patch reset). `docs`/`test`/`chore`/`build`/`ci` do not bump. Say the new version in the commit report.

## Rules

- Logic goes in `StudioCore` with a test written first. Views in `App/` are not unit tested.
- A trimmed Java runtime is bundled at `Contents/Resources/jre` (`build-app.sh` jlinks it from the installed JDK into `build/jre`, cached; delete `build/jre` to rebuild it) and `ToolLocator.bundledDirs` searches it first, then Homebrew and system dirs. It matches the build machine's architecture (this toolchain runs as x86_64 under Rosetta, so the app is x86_64; Apple Silicon Macs run it through Rosetta). The app is ad-hoc codesigned. Graphviz is not bundled and is optional: PlantUML falls back to Smetana.
- Renderer is one long-lived `java -pipe` process, serialized in the `PlantUMLRenderer` actor. Do not add concurrent renders on it.
- Remote includes and URLs are blocked in diagram source. Keep the `analyze` pre-scan and `PLANTUML_SECURITY_PROFILE=LEGACY` together.
- Markdown preview escapes raw HTML. Keep it that way; the page can read local files.
- Supported files: `.puml .plantuml .pu .wsd` (diagrams), `.md` (markdown). `.mdx` is out of scope. A folder shows in the tree when it holds supported files or is empty (so a new folder does not vanish); folders holding only other files are hidden.
- Theme (light/dark) is `AppModel.theme`, saved in UserDefaults, overrides macOS via `.preferredColorScheme`. All theme colors (frame, panel, border, orange accent, editor, sidebar rows, syntax, web CSS variables keyed by `data-theme`) live in `App/Theme.swift`. Dark follows VS Code "Dark Modern". Do not hardcode hex in `SVGView` or `MarkdownView`.
- `WindowConfigurator` makes the title bar transparent in the frame color and removes the full-size content view so content never slides under it when the window resizes or the sidebar toggles.
- Layout is plain stacks (`HStack` of fixed-width panels), not `NavigationSplitView`: on macOS 26 the latter draws the sidebar as a floating glass panel that cannot be turned off. Sidebar is a custom tree, not `List`, so hover and selection styling stay controllable. Do not switch back.
- Can't screenshot the UI here. Say when UI changes are unverified.
- After every change, update this file (layout, commands, rules) or the feature's doc in `docs/features/`. Commit it with the change.

## Git

- Commit format `<type>(<scope>): <subject>`, lowercase imperative.
- Stage files by name. No `git add .` or `-A`. No `Co-Authored-By`.
- Commit only when asked.
