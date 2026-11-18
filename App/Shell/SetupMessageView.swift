import SwiftUI
import StudioCore

struct SetupMessageView: View {
    let error: ToolError
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle)
            Text(error == .javaMissing ? "Java was not found" : "Graphviz was not found").font(.title2)
            Text(error == .javaMissing ? "PlantUML needs Java to render diagrams. Install it, then retry:" : "Install Graphviz, then retry:")
            Text(error == .javaMissing ? "brew install openjdk" : "brew install graphviz")
                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
            Button("Retry", action: retry)
        }
        .padding(32)
    }
}
