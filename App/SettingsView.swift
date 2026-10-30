import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("javaPath") private var javaPath = ""
    @AppStorage("dotPath") private var dotPath = ""

    var body: some View {
        Form {
            TextField("Java path (blank = auto)", text: $javaPath)
            TextField("Graphviz dot path (blank = auto)", text: $dotPath)
            Button("Apply") { model.resolveTools() }
        }
        .padding(20)
        .frame(width: 460)
    }
}
