# Sequence

Personal Mac app (SwiftUI, no Xcode) to browse, view and edit PlantUML and markdown files. Not signed or notarized.

## Layout

- `Sources/StudioCore`: UI-free engine (renderer, scanner, watcher, file ops, `DocumentSession`, `MarkdownPreparer`).
- `App/`: SwiftUI + AppKit views, `AppModel` (all app state).
  - `RootView`: window root. Picks setup, choose-folder or the sidebar + detail `HSplitView`, and holds app-wide alerts.
  - `SidebarView`: header (folder menu, search, theme), "New file" row, top-level folders as sections, nested folders collapsible.
  - `MainView`: detail pane for the open file. Owns the title, mode picker, Save button and the mode switch (view / edit / editPreview).
- `App/Resources`: `plantuml.jar` (bundled), `marked.min.js` (markdown parser), `AppIcon.icns`, `PLANTUML_VERSION`.
- `Tests/StudioCoreTests`: Swift Testing suites.
- `docs/superpowers/`: design spec and plan.

## Commands

- `./test.sh`: run tests. Only Command Line Tools are installed (macOS too old for Xcode), so tests use Swift Testing with CLT framework flags. Do not use `swift test` directly or XCTest.
- `./build-app.sh`: build `build/Sequence.app`. Quit the running app (⌘Q) first, or reopening shows the old build.
- Run `./test.sh` before every commit.

## Rules

- Logic goes in `StudioCore` with a test written first. Views in `App/` are not unit tested.
- Java is not bundled. It is found via `ToolLocator` (brew `openjdk` is keg-only). Graphviz is optional: PlantUML falls back to Smetana.
- Renderer is one long-lived `java -pipe` process, serialized in the `PlantUMLRenderer` actor. Do not add concurrent renders on it.
- Remote includes and URLs are blocked in diagram source. Keep the `analyze` pre-scan and `PLANTUML_SECURITY_PROFILE=LEGACY` together.
- Markdown preview escapes raw HTML. Keep it that way; the page can read local files.
- Supported files: `.puml .plantuml .pu .wsd` (diagrams), `.md` (markdown). `.mdx` is out of scope.
- Theme (light/dark) is `AppModel.theme`, saved in UserDefaults, overrides macOS via `.preferredColorScheme`. All theme colors (editor, sidebar rows, syntax, web CSS variables keyed by `data-theme`) live in `App/Theme.swift`. Dark follows VS Code "Dark Modern". Do not hardcode hex in `SVGView` or `MarkdownView`.
- Layout is a plain `HSplitView`, not `NavigationSplitView`: on macOS 26 the latter draws the sidebar as a floating glass panel that cannot be turned off. Sidebar is a custom tree, not `List`, so hover and selection styling stay controllable. Do not switch back.
- Can't screenshot the UI here. Say when UI changes are unverified.
- After every change, update `README.md` and this file if features, layout, commands or rules changed. Commit them with the change.

## Git

- Commit format `<type>(<scope>): <subject>`, lowercase imperative.
- Stage files by name. No `git add .` or `-A`. No `Co-Authored-By`.
- Commit only when asked.
