# Sequence

Personal Mac app (SwiftUI, no Xcode) to browse, view and edit PlantUML and markdown files. Not signed or notarized.

## Layout

- `Sources/StudioCore`: UI-free engine (renderer, scanner, watcher, file ops, `DocumentSession`, `MarkdownPreparer`, `TextSearch`).
- `App/`: SwiftUI + AppKit views, `AppModel` (all app state). Each window owns an `AppModel` (`WindowRoot` in `SequenceApp.swift`); menu commands reach the focused window's model through `focusedSceneObject`, and Settings talks to windows by posting `.toolPathsChanged`. Only the first window restores the last folder (`AppModel.claimRestore`).
  - `RootView`: window root. Picks setup, choose-folder or the workspace: `IconRail` + a flush panel (`HSplitView` of sidebar and detail) next to it on the grey frame color; no rounded corners or border. Holds app-wide alerts.
  - `IconRail`: left strip. Files (toggles the sidebar, ⌘⌃S; leaves a playground), PlantUML and Markdown playgrounds, Settings. Also defines `ChromeIconButton`.
  - `TopBar`: bar above the detail pane. Breadcrumb (path relative to the opened folder, root name omitted; or Playground > language), find-in-file (⌘K: `AppModel.findQuery` sends a `FindRequest` that `CodeEditor` and `DiagramWebView` answer, using `TextSearch` in `StudioCore` for editors; Return jumps to the next match), theme toggle, mode switch and orange Save (Save to folder… in a playground). There is no native toolbar; do not add `.toolbar` items.
  - `SidebarView`: header (folder menu with New File, New Folder, Change Folder; file-name search icon, `AppModel.query`), "New file" row, right-click menu (copy name/path, rename, delete), top-level folders as collapsible sections (`SectionView`, open by default), nested folders collapsible.
  - `MainView`: detail pane for the open file. Owns the title, mode picker, Save button and the mode switch (view / edit / editPreview).
- Playground: scratch files live in Application Support (`Playground` in `StudioCore`), one for PlantUML and one for markdown. `AppModel.inPlayground` is true when the open session is one of them; it hides the sidebar (the rail's Files button calls `closePlayground()`), forces Edit with preview, autosaves on typing, and swaps the top bar controls for Save to folder. The two playgrounds are separate entries in the sidebar header menu and the File menu (⌘⇧P, ⌘⇧M), and the empty "Select a file" state (`PlaygroundChoices` in `RootView`: rows styled like sidebar rows, also on the choose-folder screen); there is no language switch.
- `DiagramWebView` backs both web views (`SVGView`, `MarkdownView`). A `contextmenu` script reports the SVG under the cursor; the native menu then shows only Copy Image (a WebKit snapshot of that SVG); WebKit's default items, such as Reload, are removed. Pinch zoom on diagrams is custom (`zoomsOnPinch`, sets `pageZoom` 0.2–4); WebKit's `allowsMagnification` snaps back to 1x.
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
- Theme (light/dark) is `AppModel.theme`, saved in UserDefaults, overrides macOS via `.preferredColorScheme`. All theme colors (frame, panel, border, orange accent, editor, sidebar rows, syntax, web CSS variables keyed by `data-theme`) live in `App/Theme.swift`. Dark follows VS Code "Dark Modern". Do not hardcode hex in `SVGView` or `MarkdownView`.
- `WindowConfigurator` makes the title bar transparent in the frame color and removes the full-size content view so content never slides under it when the window resizes or the sidebar toggles.
- Layout is a plain `HSplitView`, not `NavigationSplitView`: on macOS 26 the latter draws the sidebar as a floating glass panel that cannot be turned off. Sidebar is a custom tree, not `List`, so hover and selection styling stay controllable. Do not switch back.
- Can't screenshot the UI here. Say when UI changes are unverified.
- After every change, update this file if features, layout, commands or rules changed. Commit it with the change.

## Git

- Commit format `<type>(<scope>): <subject>`, lowercase imperative.
- Stage files by name. No `git add .` or `-A`. No `Co-Authored-By`.
- Commit only when asked.
