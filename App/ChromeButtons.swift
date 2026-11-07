import SwiftUI
import AppKit

/// Where a hover label appears relative to its icon.
enum TipPlacement { case right, belowTrailing }

/// A square icon button with a hover highlight, a raised selected state and a hover label.
struct ChromeIconButton: View {
    @EnvironmentObject var model: AppModel
    let symbol: String
    let help: String
    var size: CGFloat = 36
    var selected = false
    var tip: TipPlacement = .belowTrailing
    let action: () -> Void

    var body: some View {
        Button(action: action) { ChromeIcon(symbol: symbol, size: size, selected: selected, help: help, tip: tip) }
            .buttonStyle(.plain)
    }
}

struct ChromeIcon: View {
    @EnvironmentObject var model: AppModel
    let symbol: String
    var size: CGFloat = 36
    var selected = false
    var help: String?
    var tip: TipPlacement = .belowTrailing
    @State private var hovering = false
    @State private var showTip = false
    @State private var tipTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? model.theme.selectedRow : (hovering ? model.theme.hoverRow : Color.clear)))
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                tipTask?.cancel()
                showTip = false
                guard inside, help != nil else { return }
                tipTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if !Task.isCancelled { showTip = true }
                }
            }
            .overlay(alignment: tip == .right ? .leading : .topTrailing) {
                if showTip, let help {
                    Text(help)
                        .font(.system(size: 12)).foregroundStyle(.primary).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(model.theme.panelBackground))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.theme.border))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                        .offset(x: tip == .right ? size + 6 : 0, y: tip == .right ? 0 : size + 4)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(showTip ? 1 : 0)
    }
}

/// The narrow strip left of the panels: files, the two playgrounds, the theme toggle and About.
struct IconRail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            ChromeIconButton(symbol: "folder", help: "Files (⌘⌃S)", selected: !model.inPlayground && model.showSidebar, tip: .right) { showFiles() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            ChromeIconButton(symbol: "flowchart", help: "PlantUML playground (⌘⇧P)", selected: model.inPlayground && model.playgroundKind == .diagram, tip: .right) {
                model.openPlayground(kind: .diagram)
            }
            ChromeIconButton(symbol: "doc.text", help: "Markdown playground (⌘⇧M)", selected: model.inPlayground && model.playgroundKind == .markdown, tip: .right) {
                model.openPlayground(kind: .markdown)
            }
            Spacer()
            ChromeIconButton(
                symbol: model.theme == .dark ? "sun.max" : "moon",
                help: model.theme == .dark ? "Switch to light theme" : "Switch to dark theme",
                tip: .right
            ) { model.theme = model.theme.toggled }
            SettingsLink { ChromeIcon(symbol: "gearshape", help: "About Sequence (⌘,)", tip: .right) }
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(width: 52)
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
