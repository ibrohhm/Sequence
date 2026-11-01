# PlantUML Studio

Mac app to browse, view and edit PlantUML diagrams and markdown files from a local folder. Built for reading and writing RFCs with many flows. Personal use, unsigned.

## Features

- Sidebar tree of the files in a root folder. Create, rename and delete (to Trash) from the tree. The tree updates when files change on disk.
- Click a file to see it rendered. Diagrams and markdown share three modes: View (rendered), Edit (code only) and Edit with preview (code on the left, live render on the right).
- Markdown files open in View mode.
- ```` ```plantuml ````, ```` ```puml ```` and ```` ```uml ```` blocks in markdown render as diagrams inline.
- Light and Dark themes, switched with the sun/moon button in the sidebar. The choice overrides macOS and is remembered. Dark follows the VS Code "Dark Modern" palette. Diagrams sit on a white card in Dark.
- Export a diagram as SVG or PNG.
- Asks before discarding unsaved changes, and when a file changes on disk while you have edits.

Supported files: `.puml`, `.plantuml`, `.pu`, `.wsd` and `.md`. Frontmatter is hidden in the markdown preview. `.mdx` is not supported.

## Requirements

- macOS 14 or later.
- Java. The app does not bundle it. On Homebrew: `brew install openjdk`. The app also finds it in `/opt/homebrew/opt/openjdk`, `/usr/local/opt/openjdk` and `/usr/local/bin`, or you can set the path in Settings.
- Graphviz is optional. Without it PlantUML uses its built-in layout, which handles class, component, use case, state and activity diagrams.
- Swift command line tools to build. Xcode is not needed.

## Build and run

```sh
./build-app.sh
open build/PlantUMLStudio.app
```

Quit the running app (⌘Q) before rebuilding, or reopening shows the old build.

On first launch choose a root folder. The app remembers it and the last open file.

## Test

```sh
./test.sh
```

This runs the Swift Testing suites against the Command Line Tools frameworks. Plain `swift test` does not work without Xcode.

## Notes

- Diagrams render through one long-lived `java -jar plantuml.jar -pipe` process. The jar is bundled in `App/Resources`.
- Remote includes and URLs in diagram source are blocked.
- Raw HTML in markdown is escaped in the preview.

## Layout

- `Sources/StudioCore`: engine with no UI (renderer, scanner, watcher, file operations, document sessions, markdown preparation).
- `App`: SwiftUI and AppKit views, and `AppModel`.
- `Tests/StudioCoreTests`: tests.
- `docs/superpowers`: design spec and implementation plan.
