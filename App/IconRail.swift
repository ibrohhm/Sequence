import SwiftUI

/// A square icon button with a hover highlight and a raised selected state.
struct ChromeIconButton: View {
    @EnvironmentObject var model: AppModel
    let symbol: String
    let help: String
    var size: CGFloat = 36
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { ChromeIcon(symbol: symbol, size: size, selected: selected) }
            .buttonStyle(.plain)
            .help(help)
    }
}

struct ChromeIcon: View {
    @EnvironmentObject var model: AppModel
    let symbol: String
    var size: CGFloat = 36
    var selected = false
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? model.theme.selectedRow : (hovering ? model.theme.hoverRow : Color.clear)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// The narrow strip at the window's left edge: files, the two playgrounds and settings.
struct IconRail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            ChromeIconButton(symbol: "folder", help: "Files (⌘⌃S)", selected: !model.inPlayground) { showFiles() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            ChromeIconButton(symbol: "flowchart", help: "PlantUML playground (⌘⇧P)", selected: model.inPlayground && model.playgroundKind == .diagram) {
                model.openPlayground(kind: .diagram)
            }
            ChromeIconButton(symbol: "doc.text", help: "Markdown playground (⌘⇧M)", selected: model.inPlayground && model.playgroundKind == .markdown) {
                model.openPlayground(kind: .markdown)
            }
            Spacer()
            SettingsLink { ChromeIcon(symbol: "gearshape") }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
        }
        .padding(.top, 6).padding(.bottom, 10)
        .frame(width: 56)
    }

    private func showFiles() {
        if model.inPlayground {
            model.closePlayground()
            model.showSidebar = true
        } else {
            model.showSidebar.toggle()
        }
    }
}
