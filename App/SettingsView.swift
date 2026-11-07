import SwiftUI

enum SettingsTab: String { case general, vaults, about }

/// The Settings window (⌘, and the rail gear): theme and AI editor, vaults, and app information.
struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = SettingsTab.general.rawValue
    @AppStorage("theme") private var theme = "light"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general.rawValue)
            VaultsView().tabItem { Label("Vaults", systemImage: "folder") }.tag(SettingsTab.vaults.rawValue)
            AboutView().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about.rawValue)
        }
        .frame(width: 480, height: 440)
        .preferredColorScheme((Theme(rawValue: theme) ?? .light).colorScheme)
    }
}

private struct GeneralSettings: View {
    @AppStorage("theme") private var theme = "light"
    @AppStorage("aiEditorEnabled") private var aiEnabled = true

    var body: some View {
        Form {
            LabeledContent("Theme") {
                HStack(spacing: 4) {
                    themeButton(.light, symbol: "sun.max")
                    themeButton(.dark, symbol: "moon")
                }
            }
            Section {
                Toggle("Show AI editor", isOn: $aiEnabled)
                Text("The prompt bar at the bottom of each file (⌘K focuses it). It sends the file's text to Claude Code to apply your change.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private func themeButton(_ option: Theme, symbol: String) -> some View {
        let selected = theme == option.rawValue
        let current = Theme(rawValue: theme) ?? .light
        return Button { theme = option.rawValue } label: {
            Image(systemName: symbol).font(.system(size: 14))
                .foregroundStyle(selected ? current.accent : Color.secondary)
                .frame(width: 32, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(selected ? current.selectedRow : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option == .dark ? "Dark" : "Light")
    }
}

extension OpenSettingsAction {
    /// Opens the Settings window on `tab`.
    func callAsFunction(tab: SettingsTab) {
        UserDefaults.standard.set(tab.rawValue, forKey: "settingsTab")
        self()
    }
}
