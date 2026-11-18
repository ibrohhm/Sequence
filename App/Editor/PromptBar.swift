import SwiftUI
import StudioCore

/// The AI prompt at the bottom of the detail panel: describe a change and Claude rewrites the open document.
struct PromptBar: View {
    @EnvironmentObject var model: AppModel
    let kind: DocumentKind
    @State private var text = ""
    @FocusState private var focused: Bool

    private var placeholder: String {
        kind == .markdown ? "Describe a change to this document" : "Describe a change, e.g. add a retry loop after the payment call"
    }

    private var canSend: Bool { !model.isAIRunning && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.aiError {
                Text(error).font(.system(size: 12)).foregroundStyle(.red).lineLimit(2).textSelection(.enabled)
            }
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...5)
                    .focused($focused)
                    .disabled(model.isAIRunning)
                    .onSubmit(send)
                if model.aiUndoText != nil && !model.isAIRunning {
                    Button("Undo") { model.undoAIEdit() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .help("Restore the text from before the last AI change")
                }
                if model.isAIRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
                            .foregroundStyle(canSend ? model.theme.accent : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain).disabled(!canSend).help("Send (Return)")
                }
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(model.theme.panelBackground))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.theme.border))
        }
        .padding(12)
        .onChange(of: model.promptFocusTick) { _, _ in focused = true }
    }

    private func send() {
        guard canSend else { return }
        let prompt = text
        text = ""
        model.askAI(prompt)
    }
}
