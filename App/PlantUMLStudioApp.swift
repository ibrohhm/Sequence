import SwiftUI

@main
struct PlantUMLStudioApp: App {
    @StateObject private var model = AppModel()

    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") { model.chooseRoot() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }.keyboardShortcut("s").disabled(model.session == nil)
                Divider()
                Button("Export SVG…") { model.exportSVG() }.disabled(model.lastSVG == nil)
                Button("Export PNG…") { model.exportPNG() }.disabled(model.session == nil)
            }
        }
        Settings { SettingsView().environmentObject(model) }
    }
}
