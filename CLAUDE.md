# Sequence

Personal Mac app (SwiftUI, no Xcode) to browse, view and edit PlantUML and markdown files. Not signed or notarized.

## Layout

- `Sources/StudioCore`: UI-free engine (renderer, scanner, watcher, file ops, `DocumentSession`, `MarkdownPreparer`, `TextSearch`).
- `App/`: SwiftUI + AppKit views, `AppModel` (all app state). Each window owns an `AppModel` (`WindowRoot` in `SequenceApp.swift`); menu commands reach the focused window's model through `focusedSceneObject`. Only the first window restores the last folder (`AppModel.claimRestore`).
  - `RootView`: window root. Picks setup, choose-folder or the workspace: the `IconRail` and two rounded, bordered panels (sidebar 180–480pt, default 236, drag the gap to resize (`SidebarResizer`, saved as `sidebarWidth`), detail) with an 8pt gap on the grey frame color. Layout follows the UI guideline from Pratik (see memory note `global/ui-guideline-from-pratik`). Holds app-wide alerts.
  - `IconRail` (in `ChromeButtons.swift`, with the shared `ChromeIconButton`): 52pt strip left of the panels. Files (toggles the sidebar, ⌘⌃S; leaves a playground), PlantUML and Markdown playgrounds, theme toggle and the gear (About Sequence: version, PlantUML, Java and Graphviz in use) at the bottom. There is no top bar.
  - `PageHeader`: header of the detail panel. File name (right-click: Copy Name / Copy Path) with the folder as a muted subtitle; find-in-file (⌘F via the Edit menu command that replaces the system Find group: `AppModel.findQuery` sends a `FindRequest` that `CodeEditor` and `DiagramWebView` answer, `TextSearch` in `StudioCore` for editors; Return jumps to the next match); mode switch icons (Save has no button: ⌘S or File > Save, and a dot beside the name marks unsaved edits; a playground shows Save to folder… instead). There is no native toolbar; do not add `.toolbar` items.
  - `SidebarView`: header (folder menu with New File, New Folder, Change Folder; file-name search icon, `AppModel.query`, hide-sidebar button), "New file" row, right-click menu (copy name/path, rename, delete), folders and files as one tree of `TreeRow`s: folder icon + chevron on folders (top-level folders start open), files indented to line up under their parent folder icon, guide line down each open folder.
  - `MainView`: detail pane for the open file. Owns the title, mode picker, Save button and the mode switch (view / edit / editPreview).
- Playground: scratch files live in Application Support (`Playground` in `StudioCore`), one for PlantUML and one for markdown. `AppModel.inPlayground` is true when the open session is one of them; it hides the sidebar (the rail's Files button calls `closePlayground()`), forces Edit with preview, autosaves on typing, and swaps the top bar controls for Save to folder. The two playgrounds are separate entries in the sidebar header menu and the File menu (⌘⇧P, ⌘⇧M), and the empty "Select a file" state (`PlaygroundChoices` in `RootView`: rows styled like sidebar rows, also on the choose-folder screen); there is no language switch.
- Markdown formatting: the Format menu (⌘B bold, ⌘I italic) calls `AppModel.format`, which sends a `MarkdownFormat` to `CodeEditor`; `MarkdownFormatter` (`StudioCore`) computes the edit (wrap, unwrap, bold+italic combos, spaces kept outside the markers) and the editor applies it through `shouldChangeText` so undo works. Only for markdown files with the editor visible.
- AI prompt: `PromptBar` (bottom of the detail panel) calls `AppModel.askAI`, which runs `AIEditor` (`StudioCore`) = `claude -p` with a fixed system prompt per `DocumentKind` (`AIEditor.systemPrompt`), the document and instruction on stdin, `--tools ""`, `--setting-sources ""`, `--disable-slash-commands`, `--no-session-persistence`, temp cwd and `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` so the user's hooks and CLAUDE.md cannot leak into the reply (`--bare` is not used: it blocks OAuth login). The reply replaces the whole text; the old text is kept for Undo, and a result is dropped if the file changed meanwhile. Claude is found via `ToolLocator.claude()` in `claudeDirs`. Edit the system prompts to change what Claude may do.
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
- A trimmed Java runtime is bundled at `Contents/Resources/jre` (`build-app.sh` jlinks it from the installed JDK into `build/jre`, cached; delete `build/jre` to rebuild it) and `ToolLocator.bundledDirs` searches it first, then Homebrew and system dirs. It matches the build machine's architecture (this toolchain runs as x86_64 under Rosetta, so the app is x86_64; Apple Silicon Macs run it through Rosetta). The app is ad-hoc codesigned. Graphviz is not bundled and is optional: PlantUML falls back to Smetana.
- Renderer is one long-lived `java -pipe` process, serialized in the `PlantUMLRenderer` actor. Do not add concurrent renders on it.
- Remote includes and URLs are blocked in diagram source. Keep the `analyze` pre-scan and `PLANTUML_SECURITY_PROFILE=LEGACY` together.
- Markdown preview escapes raw HTML. Keep it that way; the page can read local files.
- Supported files: `.puml .plantuml .pu .wsd` (diagrams), `.md` (markdown). `.mdx` is out of scope.
- Theme (light/dark) is `AppModel.theme`, saved in UserDefaults, overrides macOS via `.preferredColorScheme`. All theme colors (frame, panel, border, orange accent, editor, sidebar rows, syntax, web CSS variables keyed by `data-theme`) live in `App/Theme.swift`. Dark follows VS Code "Dark Modern". Do not hardcode hex in `SVGView` or `MarkdownView`.
- `WindowConfigurator` makes the title bar transparent in the frame color and removes the full-size content view so content never slides under it when the window resizes or the sidebar toggles.
- Layout is plain stacks (`HStack` of fixed-width panels), not `NavigationSplitView`: on macOS 26 the latter draws the sidebar as a floating glass panel that cannot be turned off. Sidebar is a custom tree, not `List`, so hover and selection styling stay controllable. Do not switch back.
- Can't screenshot the UI here. Say when UI changes are unverified.
- After every change, update this file if features, layout, commands or rules changed. Commit it with the change.

## Git

- Commit format `<type>(<scope>): <subject>`, lowercase imperative.
- Stage files by name. No `git add .` or `-A`. No `Co-Authored-By`.
- Commit only when asked.
