import SwiftUI
import AppKit
import StudioCore

enum ViewMode: String { case view, edit, editPreview }

@MainActor final class AppModel: ObservableObject {
    @Published var rootFolder: URL?
    @Published var tree: [FileNode] = []
    @Published var selection: URL?
    @Published var session: DocumentSession?
    @Published var mode: ViewMode = .view
    @Published var showSidebar = true
    @Published var theme: Theme = .light {
        didSet { defaults.set(theme.rawValue, forKey: "theme") }
    }
    @Published var lastSVG: Data?
    @Published var markdownPreview: MarkdownPreview?
    @Published var renderError: String?
    @Published var isRendering = false
    @Published var setupError: ToolError?
    @Published var notice: String?
    @Published var showConflict = false
    @Published var pendingSelection: URL?

    private var renderer: PlantUMLRenderer?
    private var javaURL: URL?
    private var dotURL: URL?
    private var renderTask: Task<Void, Never>?
    private var watcher: FolderWatcher?
    private let defaults = UserDefaults.standard

    private var jarURL: URL {
        Bundle.main.url(forResource: "plantuml", withExtension: "jar")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/plantuml.jar")
    }

    init() {
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .light
        resolveTools()
        if let path = defaults.string(forKey: "rootFolder"), FileManager.default.fileExists(atPath: path) {
            openRoot(URL(fileURLWithPath: path))
            if let file = defaults.string(forKey: "lastFile"), FileManager.default.fileExists(atPath: file) {
                select(URL(fileURLWithPath: file))
            }
        }
    }

    func resolveTools() {
        var overrides: [String: URL] = [:]
        for name in ["java", "dot"] {
            if let path = defaults.string(forKey: "\(name)Path"), !path.isEmpty { overrides[name] = URL(fileURLWithPath: path) }
        }
        let locator = ToolLocator(overrides: overrides)
        dotURL = try? locator.dot()
        do {
            let java = try locator.java()
            javaURL = java
            renderer = PlantUMLRenderer(javaURL: java, jarURL: jarURL, dotURL: dotURL)
            setupError = nil
            scheduleRender(debounce: false)
        } catch {
            setupError = error as? ToolError
            renderer = nil
        }
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Folder"
        if panel.runModal() == .OK, let url = panel.url { openRoot(url) }
    }

    func openRoot(_ url: URL) {
        if session?.isDirty == true {
            notice = "Save or discard your changes before switching folders."
            return
        }
        rootFolder = url
        defaults.set(url.path, forKey: "rootFolder")
        session = nil
        selection = nil
        rescan()
        watcher?.stop()
        watcher = FolderWatcher(root: url) { [weak self] in
            Task { @MainActor in self?.folderChanged() }
        }
    }

    func rescan() {
        guard let rootFolder else { tree = []; return }
        tree = (try? LibraryScanner.scan(rootFolder)) ?? []
    }

    private func folderChanged() {
        rescan()
        guard let session else { return }
        switch session.diskDidChange() {
        case .none: break
        case .reloaded: scheduleRender(debounce: false)
        case .conflict: showConflict = true
        case .fileMissing: notice = "\(session.url.lastPathComponent) was deleted or moved. Your text is still in the editor; Save writes it back."
        }
    }

    func select(_ url: URL?) {
        guard let url, LibraryScanner.extensions.contains(url.pathExtension.lowercased()) else { return }
        if let current = session, current.isDirty, current.url != url {
            pendingSelection = url
            return
        }
        open(url)
    }

    /// Resolves the unsaved-changes prompt: save then switch, discard then switch.
    func resolvePendingSelection(save shouldSave: Bool) {
        guard let target = pendingSelection else { return }
        pendingSelection = nil
        if shouldSave {
            save()
            if session?.isDirty == true { return }
        }
        open(target)
    }

    func cancelPendingSelection() { pendingSelection = nil }

    private func open(_ url: URL) {
        do {
            session = try DocumentSession(url: url)
            selection = url
            notice = nil
            lastSVG = nil
            markdownPreview = nil
            renderError = nil
            if DocumentKind(url: url) == .markdown { mode = .view }
            defaults.set(url.path, forKey: "lastFile")
            scheduleRender(debounce: false)
        } catch {
            notice = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func scheduleRender(debounce: Bool) {
        renderTask?.cancel()
        guard let session else { return }
        let source = session.text
        let base = session.url.deletingLastPathComponent()
        if DocumentKind(url: session.url) == .markdown {
            renderMarkdown(source, base: base, renderer: renderer, debounce: debounce)
            return
        }
        guard let renderer else { return }
        renderTask = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            if Task.isCancelled { return }
            self?.isRendering = true
            let result = await renderer.render(source, baseDirectory: base)
            guard let self, !Task.isCancelled else { return }
            isRendering = false
            switch result {
            case .svg(let data): lastSVG = data; renderError = nil
            case .failure(let message): renderError = message
            case .superseded: break
            }
        }
    }

    private func renderMarkdown(_ source: String, base: URL, renderer: PlantUMLRenderer?, debounce: Bool) {
        let prepared = MarkdownPreparer.prepare(source)
        let previous = markdownPreview?.diagrams ?? []
        var diagrams = prepared.diagrams.indices.map { $0 < previous.count ? previous[$0] : MarkdownDiagram() }
        markdownPreview = MarkdownPreview(markdown: prepared.markdown, diagrams: diagrams)
        renderTask = Task { [weak self] in
            if debounce && !prepared.diagrams.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            for (index, diagram) in prepared.diagrams.enumerated() {
                guard let renderer else {
                    diagrams[index] = MarkdownDiagram(error: "Java not found. Diagram not rendered.")
                    continue
                }
                let result = await renderer.render(diagram, baseDirectory: base)
                if Task.isCancelled { return }
                switch result {
                case .svg(let data): diagrams[index] = MarkdownDiagram(svg: String(decoding: data, as: UTF8.self))
                case .failure(let message): diagrams[index] = MarkdownDiagram(error: message)
                case .superseded: break
                }
                self?.markdownPreview = MarkdownPreview(markdown: prepared.markdown, diagrams: diagrams)
            }
            if renderer == nil { self?.markdownPreview = MarkdownPreview(markdown: prepared.markdown, diagrams: diagrams) }
        }
    }

    func save() {
        guard let session else { return }
        do { try session.save(); notice = nil } catch { notice = "Save failed: \(error.localizedDescription)" }
    }

    func reloadFromDisk() {
        try? session?.reloadFromDisk()
        scheduleRender(debounce: false)
    }

    func exportSVG() {
        guard let data = lastSVG, let session, DocumentKind(url: session.url) == .diagram else { return }
        saveDialog(name: session.url.deletingPathExtension().lastPathComponent + ".svg") { try data.write(to: $0) }
    }

    func exportPNG() {
        guard let session, let javaURL, DocumentKind(url: session.url) == .diagram else { return }
        let source = session.text, base = session.url.deletingLastPathComponent(), jar = jarURL, dot = dotURL
        let name = session.url.deletingPathExtension().lastPathComponent + ".png"
        Task {
            guard let data = await StudioCore.exportPNG(source: source, baseDirectory: base, javaURL: javaURL, jarURL: jar, dotURL: dot) else {
                notice = "PNG export failed. Check the diagram renders first."
                return
            }
            saveDialog(name: name) { try data.write(to: $0) }
        }
    }

    private func saveDialog(name: String, write: (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try write(url) } catch { notice = "Export failed: \(error.localizedDescription)" }
    }

    // MARK: sidebar operations

    func createFile(named name: String, in folder: URL?) { perform { let url = try LibraryOperations.createFile(named: name, in: folder ?? rootFolder!); rescan(); select(url) } }
    func createFolder(named name: String, in folder: URL?) { perform { _ = try LibraryOperations.createFolder(named: name, in: folder ?? rootFolder!); rescan() } }

    func rename(_ url: URL, to name: String) {
        perform {
            let renamed = try LibraryOperations.rename(url, to: name)
            rescan()
            if session?.url == url {
                session?.relocate(to: renamed)
                selection = renamed
                defaults.set(renamed.path, forKey: "lastFile")
            }
        }
    }

    func delete(_ url: URL) {
        perform {
            try LibraryOperations.delete(url)
            if session?.url.path.hasPrefix(url.path) == true { session = nil; selection = nil }
            rescan()
        }
    }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch LibraryOperationError.alreadyExists { notice = "That name already exists." }
        catch LibraryOperationError.invalidName { notice = "That name is not valid." }
        catch { notice = error.localizedDescription }
    }
}
