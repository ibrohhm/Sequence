import SwiftUI
import AppKit

/// Where a hover label appears relative to its icon.
enum TipPlacement { case right, belowTrailing, aboveTrailing }

/// A square icon button with a hover highlight, a raised selected state and a hover label.
struct ChromeIconButton: View {
    @EnvironmentObject var model: AppModel
    let symbol: String
    let help: String
    var size: CGFloat = 36
    var glyph: CGFloat = 15
    var selected = false
    var tip: TipPlacement = .belowTrailing
    let action: () -> Void

    var body: some View {
        Button(action: action) { ChromeIcon(symbol: symbol, size: size, glyph: glyph, selected: selected, help: help, tip: tip) }
            .buttonStyle(.plain)
    }
}

struct TipInfo {
    let text: String
    let anchor: Anchor<CGRect>
    let placement: TipPlacement
}

struct TipKey: PreferenceKey {
    static var defaultValue: TipInfo?
    static func reduce(value: inout TipInfo?, nextValue: () -> TipInfo?) { value = nextValue() ?? value }
}

/// Draws the hover label of the icon being hovered above the whole window, so panels cannot clip it.
struct TipOverlay: View {
    @EnvironmentObject var model: AppModel
    let info: TipInfo?

    var body: some View {
        GeometryReader { proxy in
            if let info {
                let rect = proxy[info.anchor]
                Color.clear.frame(width: rect.width, height: rect.height)
                    .overlay(alignment: info.placement == .right ? .leading : (info.placement == .aboveTrailing ? .bottomTrailing : .topTrailing)) {
                        Text(info.text)
                            .font(.system(size: 12)).foregroundStyle(.primary).fixedSize()
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(model.theme.panelBackground))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.theme.border))
                            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                            .offset(x: info.placement == .right ? rect.width + 6 : 0,
                                    y: info.placement == .right ? 0 : (info.placement == .aboveTrailing ? -(rect.height + 4) : rect.height + 4))
                    }
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ChromeIcon: View {
    @EnvironmentObject var model: AppModel
    let symbol: String
    var size: CGFloat = 36
    var glyph: CGFloat = 15
    var selected = false
    var help: String?
    var tip: TipPlacement = .belowTrailing
    @State private var hovering = false
    @State private var showTip = false
    @State private var tipTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: glyph))
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
            .anchorPreference(key: TipKey.self, value: .bounds) { anchor in
                guard showTip, let help else { return nil }
                return TipInfo(text: help, anchor: anchor, placement: tip)
            }
    }
}

/// The narrow strip left of the panels: files, file search, the two playgrounds, the theme toggle and About.
struct IconRail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            ChromeIconButton(symbol: "folder", help: "Files (⌘⌃S)", selected: !model.inPlayground && !model.showTasks && model.showSidebar, tip: .right) { showFiles() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            ChromeIconButton(symbol: "magnifyingglass", help: "Search files", selected: model.searching && model.showSidebar && !model.inPlayground && !model.showTasks, tip: .right) {
                model.toggleSearch()
            }
            ChromeIconButton(symbol: "flowchart", help: "PlantUML playground (⌘⇧P)", selected: model.inPlayground && model.playgroundKind == .diagram, tip: .right) {
                model.openPlayground(kind: .diagram)
            }
            ChromeIconButton(symbol: "doc.text", help: "Markdown playground (⌘⇧M)", selected: model.inPlayground && model.playgroundKind == .markdown, tip: .right) {
                model.openPlayground(kind: .markdown)
            }
            ChromeIconButton(symbol: "checklist", help: "Slack tasks", selected: model.showTasks, tip: .right) {
                model.openTasks()
            }
            Spacer()
            ChromeIconButton(
                symbol: model.theme == .dark ? "sun.max" : "moon",
                help: model.theme == .dark ? "Switch to light theme" : "Switch to dark theme",
                tip: .right
            ) { model.theme = model.theme.toggled }
            SettingsLink { ChromeIcon(symbol: "gearshape", help: "Settings (⌘,)", tip: .right) }
                .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(width: 52)
    }

    private func showFiles() {
        if model.showTasks {
            model.showTasks = false
            model.showSidebar = true
        } else if model.inPlayground {
            model.closePlayground()
            model.showSidebar = true
        } else {
            model.showSidebar.toggle()
        }
    }
}
