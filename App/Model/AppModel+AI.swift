import Foundation
import StudioCore

extension AppModel {
    /// Rewrites the open document from a plain-language instruction using the Claude CLI; the previous text stays available to undo.
    func askAI(_ instruction: String) {
        let prompt = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !isAIRunning, !prompt.isEmpty else { return }
        guard let claude = try? ToolLocator(searchDirs: ToolLocator.claudeDirs).claude() else {
            aiError = "Claude Code was not found. Install it and sign in, then try again."
            return
        }
        let before = session.text
        let kind = DocumentKind(url: session.url)
        isAIRunning = true
        aiError = nil
        Task {
            defer { isAIRunning = false }
            do {
                let result = try await AIEditor(claude: claude).edit(before, instruction: prompt, kind: kind)
                guard self.session === session, session.text == before else {
                    aiError = "The file changed while Claude was working, so its result was discarded."
                    return
                }
                aiUndoText = before
                session.text = result
                if inPlayground { try? session.save() }
                scheduleRender(debounce: false)
            } catch AIEditError.failed(let message) {
                aiError = message.components(separatedBy: "\n").first ?? message
            } catch AIEditError.timedOut {
                aiError = "Claude took too long. Try a smaller change."
            } catch AIEditError.emptyResponse {
                aiError = "Claude returned nothing."
            } catch {
                aiError = error.localizedDescription
            }
        }
    }

    func undoAIEdit() {
        guard let session, let text = aiUndoText else { return }
        session.text = text
        aiUndoText = nil
        if inPlayground { try? session.save() }
        scheduleRender(debounce: false)
    }
}
