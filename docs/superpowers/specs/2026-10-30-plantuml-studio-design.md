# PlantUML Studio — Design

Date: 2026-10-30

## Intent and why

The user is a backend engineer who writes RFCs for a project with many flows. To propose changes they must first understand the existing flows. Those flows exist as PlantUML diagrams, mostly in Confluence. They want the diagrams on their own machine, browsable like a library and editable with a live preview, so they can read existing flows and draft new or changed ones for RFCs.

PlantUML Studio is a native macOS app: a local library of `.puml` files plus a live-preview editor.

## Goals

- Browse a folder of `.puml` files in a sidebar tree.
- Click a file to see its rendered diagram.
- Edit a diagram in a playground: code on the left, live render on the right.
- Work fully offline. Diagram content never leaves the machine.
- Files stay plain `.puml` on disk, so Finder and git keep working on them.

## Non-goals (v1)

- Confluence import or sync. The user copies diagrams into `.puml` files by hand.
- Cross-platform support. macOS only.
- Collaboration, cloud storage, accounts.
- Bundling Java.
- Running the rendering engine as a network server.

## Anti-goals

- Anything that sends diagram content to a remote service (for example the public PlantUML server).
- A proprietary file format or hidden database. If the app disappears, the files must still be ordinary `.puml` files in a normal folder.
- A blank pane when the code has a syntax error. The user must always see why the render failed.

## Decided by the user

- Platform: Mac only.
- Three features: sidebar tree of PlantUML files, click-to-view rendered result, playground with code left and result right.
- Confluence import is not needed in v1.
- Project location: `~/personal/plantuml-studio/`.
- Distribution: personal use only, on the user's own Mac. No App Store, no sandbox, no code signing or notarization. The PlantUML jar is bundled in the app so it works offline from first launch.

## Builder's calls (not yet confirmed by the user)

These are decisions made on the user's behalf. They are marked so the user can check them.

- **Language/UI:** Swift and SwiftUI. The code editor pane wraps `NSTextView` (or a library) because SwiftUI's built-in text editor is too weak for a code editor.
- **Rendering:** run the PlantUML jar locally via the Java CLI. The app requires Java to be installed and shows a clear message if it is missing. Java is not bundled.
- **Library root:** the user picks a root folder (for example `~/rfc-diagrams`). The sidebar mirrors that folder.
- **Sidebar operations:** create, rename and delete files and folders from the sidebar. Deleting asks for confirmation.
- **Viewer:** zoom and scroll, plus export to PNG and SVG.
- **Playground:** re-render after a short pause once typing stops. Syntax and render errors show inline. Saving writes back to the `.puml` file.
- **App name:** "PlantUML Studio" is a placeholder.
- **Render process:** a long-lived local `java -jar plantuml.jar -pipe` child process, reused across renders, so live preview is fast. No network server. A stale render is cancelled when new input arrives. Target: under about 500 ms per render after the first.
- **Includes:** relative `!include` works, resolved against the open file's folder. Remote includes (`!includeurl`, `!include http...`) are blocked, to honor the anti-goal on remote services.
- **Sidebar scope:** shows `.puml`, `.plantuml`, `.pu` and `.wsd` files, and folders that contain them. The tree watches the folder, so changes from git or Finder appear. If a file changes on disk while the playground has unsaved edits, the app keeps the user's edits and asks whether to reload or keep them.
- **Save:** explicit save with Cmd+S and a dirty indicator. No autosave, so half-typed code never reaches disk or git. The viewer and playground are two modes of one view for the selected file.
- **Build:** Xcode project, macOS 14 minimum.
- **Viewer output:** render SVG and display it in a `WKWebView`, so zoom stays sharp. PNG and SVG export come from the renderer.
- **Java and Graphviz lookup:** Finder-launched apps don't inherit the shell PATH, so the app probes `/opt/homebrew/bin`, `/usr/local/bin` and `/usr/bin`, with a path override in settings. If Java or `dot` is missing, the app shows a message naming the missing tool and the install command.

## Constraints

- macOS only. The minimum macOS version is left to the builder.
- The renderer depends on a local Java runtime and the PlantUML jar. Rendering PlantUML diagrams that use Graphviz layouts may also need Graphviz (`dot`) installed.
- The user's primary stack is Go. Nothing in the app needs Go, and no Go code is expected.

## Left to the builder

- Minimum macOS version, project structure, and how the app finds Java and Graphviz.
- How the PlantUML jar is obtained and where it lives (bundled in the app versus downloaded on first run).
- Whether to use a text-editor library or a custom `NSTextView` wrapper, and the level of PlantUML syntax highlighting.
- Debounce interval and the render cancellation strategy.
- How to remember the last-opened root folder and file.
- Testing approach.
