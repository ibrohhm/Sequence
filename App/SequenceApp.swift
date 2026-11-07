import SwiftUI

/// One window: its own model, so each window can show a different folder.
private struct WindowRoot: View {
    @StateObject private var model = AppModel(restoreSession: AppModel.claimRestore())

    var body: some View {
        RootView()
            .environmentObject(model)
            .focusedSceneObject(model)
            .background(WindowActivation { model.becameActive() })
    }
}

private struct SequenceCommands: Commands {
    @FocusedObject private var model: AppModel?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Folder as Vault…") { model?.chooseRoot() }.keyboardShortcut("o").disabled(model == nil)
            Button("Manage Vaults…") { openWindow(id: "vaults") }
            Divider()
            Button("PlantUML Playground") { model?.openPlayground(kind: .diagram) }.keyboardShortcut("p", modifiers: [.command, .shift]).disabled(model == nil)
            Button("Markdown Playground") { model?.openPlayground(kind: .markdown) }.keyboardShortcut("m", modifiers: [.command, .shift]).disabled(model == nil)
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find in File") { model?.focusFind() }.keyboardShortcut("f").disabled(model?.session == nil)
        }
        CommandMenu("Ask") {
            Button("Ask AI") { model?.focusPrompt() }.keyboardShortcut("k").disabled(model?.session == nil)
        }
        CommandMenu("Format") {
            Button("Bold") { model?.format(.bold) }.keyboardShortcut("b").disabled(!(model?.canFormatMarkdown ?? false))
            Button("Italic") { model?.format(.italic) }.keyboardShortcut("i").disabled(!(model?.canFormatMarkdown ?? false))
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { model?.save() }.keyboardShortcut("s").disabled(model?.session == nil)
            Divider()
            Button("Export SVG…") { model?.exportSVG() }.disabled(model?.lastSVG == nil)
            Button("Export PNG…") { model?.exportPNG() }.disabled(model?.session == nil)
        }
    }
}

@main
struct SequenceApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        WindowGroup("Sequence") { WindowRoot() }
            .commands { SequenceCommands() }
        Window("Vaults", id: "vaults") { VaultsView() }
            .windowResizability(.contentSize)
        Settings { AboutView() }
    }
}
