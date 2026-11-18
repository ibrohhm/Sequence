import AppKit
import StudioCore
import UniformTypeIdentifiers

extension AppModel {
    var inPlayground: Bool {
        guard let session else { return false }
        return Playground.contains(session.url, in: playgroundDirectory)
    }

    /// Opens the scratch editor for `kind` (the last one used by default). Its text is kept between launches.
    func openPlayground(kind: DocumentKind? = nil) {
        showTasks = false
        showFlows = false
        guard let url = try? Playground.ensureFile(for: kind ?? playgroundKind, in: playgroundDirectory) else {
            notice = "Could not open the playground."
            return
        }
        select(url)
    }

    /// Leaves the playground and returns to the file list with nothing open.
    func closePlayground() {
        guard inPlayground else { return }
        if session?.isDirty == true { save() }
        session = nil
        selection = nil
        markdownPreview = nil
        lastSVG = nil
        if let saved = modeBeforePlayground { mode = saved; modeBeforePlayground = nil }
    }

    /// Writes the playground text to a file the user picks, then opens it from the library.
    func saveCopyOfPlayground() {
        guard let session, inPlayground else { return }
        let ext = playgroundKind == .markdown ? "md" : "puml"
        let panel = NSSavePanel()
        panel.directoryURL = rootFolder
        panel.nameFieldStringValue = "untitled.\(ext)"
        if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try session.text.write(to: url, atomically: true, encoding: .utf8)
            rescan()
            select(url)
        } catch { notice = "Save failed: \(error.localizedDescription)" }
    }
}
