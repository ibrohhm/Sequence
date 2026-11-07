import SwiftUI
import Combine
import AppKit
import StudioCore
import UniformTypeIdentifiers

struct FindRequest {
    let query: String
    let backwards: Bool
    let advance: Bool
}

enum NewItemKind { case file, folder }

/// A new file or folder being named in the sidebar.
struct NewItem: Equatable {
    let kind: NewItemKind
    let parent: URL
}

enum ViewMode: String { case view, edit, editPreview }

@MainActor final class AppModel: ObservableObject {
    @Published var rootFolder: URL?
    @Published var tree: [FileNode] = []
    @Published var selection: URL?
    @Published var session: DocumentSession?
    @Published var mode: ViewMode = .view
    @Published var showSidebar = true
    @Published var query = ""
    @Published var searching = false
    @Published var sidebarFocus: URL?
    @Published var newItem: NewItem?
    @Published var findQuery = ""
    @Published private(set) var findFocusTick = 0
    @Published private(set) var promptFocusTick = 0
    @Published private(set) var isAIRunning = false
    @Published var aiError: String?
    @Published private(set) var aiUndoText: String?
    let findRequests = PassthroughSubject<FindRequest, Never>()
    let formatRequests = PassthroughSubject<MarkdownFormat, Never>()
    @Published private(set) var playgroundKind: DocumentKind = .diagram
    private let playgroundDirectory = Playground.defaultDirectory()
    private var modeBeforePlayground: ViewMode?
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
    private let store = VaultStore.shared
    private var vaultSub: AnyCancellable?
    private var defaultsSub: AnyCancellable?

    /// The model of the window the user last focused; the Settings window acts on it.
    static weak var active: AppModel?

    private var jarURL: URL {
        Bundle.main.url(forResource: "plantuml", withExtension: "jar")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/plantuml.jar")
    }

    private static var restoredOnce = false

    /// True for the first window only, so later windows start empty instead of repeating the last folder.
    static func claimRestore() -> Bool {
        defer { restoredOnce = true }
        return !restoredOnce
    }

    init(restoreSession: Bool = true) {
        playgroundKind = defaults.string(forKey: "playgroundKind") == "markdown" ? .markdown : .diagram
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .light
        defaultsSub = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).sink { [weak self] _ in
            guard let self, let saved = Theme(rawValue: self.defaults.string(forKey: "theme") ?? ""), saved != self.theme else { return }
            self.theme = saved
        }
        vaultSub = store.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        resolveTools()
        if restoreSession, let path = defaults.string(forKey: "rootFolder"), FileManager.default.fileExists(atPath: path) {
            openRoot(URL(fileURLWithPath: path))
            if let file = defaults.string(forKey: "lastFile"), FileManager.default.fileExists(atPath: file) {
                select(URL(fileURLWithPath: file))
            }
        }
    }

    func resolveTools() {
        let locator = ToolLocator(searchDirs: ToolLocator.bundledDirs(in: Bundle.main.resourceURL) + ToolLocator.defaultDirs)
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

    var vaults: [Vault] { store.vaults }

    func windowClosed() {
        guard AppModel.active === self else { return }
        AppModel.active = nil
        store.hasWindow = false
    }

    func becameActive() {
        AppModel.active = self
        store.hasWindow = true
        store.activePath = rootFolder?.standardizedFileURL.path
    }

    /// The vault whose folder is open.
    var activeVault: Vault? { vaults.first { $0.path == rootFolder?.standardizedFileURL.path } }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use as Vault"
        if panel.runModal() == .OK, let url = panel.url { openRoot(url) }
    }

    func switchVault(_ vault: Vault) {
        guard FileManager.default.fileExists(atPath: vault.path) else { notice = "\(vault.name) is missing from disk."; return }
        openRoot(vault.url)
    }

    func createVault(named name: String) {
        var created: Vault?
        perform {
            try store.update { created = try $0.create(named: name, in: VaultList.defaultBase()) }
        }
        if let created { openRoot(created.url) }
    }

    private func updateVaults(_ change: (inout VaultList) -> Void) {
        do { try store.update(change) } catch { notice = error.localizedDescription }
    }

    func openRoot(_ url: URL) {
        if session?.isDirty == true {
            notice = "Save or discard your changes before switching folders."
            return
        }
        rootFolder = url
        sidebarFocus = nil
        newItem = nil
        defaults.set(url.path, forKey: "rootFolder")
        updateVaults { $0.add(folder: url) }
        store.activePath = url.standardizedFileURL.path
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

    /// True when a markdown file is open in a mode that shows the editor.
    var canFormatMarkdown: Bool {
        guard let session else { return false }
        return DocumentKind(url: session.url) == .markdown && mode != .view
    }

    /// Asks the markdown editor to toggle bold or italic on its selection.
    func format(_ format: MarkdownFormat) {
        guard canFormatMarkdown else { return }
        formatRequests.send(format)
    }

    func focusFind() { findFocusTick += 1 }

    func focusPrompt() { promptFocusTick += 1 }

    /// Asks the open editor and previews to select the next match of `query`.
    func find(_ query: String, backwards: Bool = false, advance: Bool = false) {
        guard !query.isEmpty else { return }
        findRequests.send(FindRequest(query: query, backwards: backwards, advance: advance))
    }

    func select(_ url: URL?) {
        guard let url, LibraryScanner.extensions.contains(url.pathExtension.lowercased()) else { return }
        if inPlayground, session?.isDirty == true { save() }
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
            aiError = nil
            aiUndoText = nil
            lastSVG = nil
            markdownPreview = nil
            renderError = nil
            if Playground.contains(url, in: playgroundDirectory) {
                if modeBeforePlayground == nil { modeBeforePlayground = mode }
                mode = .editPreview
                playgroundKind = DocumentKind(url: url)
                defaults.set(playgroundKind == .markdown ? "markdown" : "diagram", forKey: "playgroundKind")
            } else {
                if let saved = modeBeforePlayground { mode = saved; modeBeforePlayground = nil }
                if DocumentKind(url: url) == .markdown { mode = .view }
            }
            defaults.set(url.path, forKey: "lastFile")
            scheduleRender(debounce: false)
        } catch {
            notice = "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func scheduleRender(debounce: Bool) {
        renderTask?.cancel()
        guard let session else { return }
        if debounce, inPlayground { try? session.save() }
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

    /// Starts naming a new file or folder in `folder`, else in the focused folder, else in the root.
    func beginNew(_ kind: NewItemKind, in folder: URL? = nil) {
        guard let rootFolder else { notice = "Add a vault first."; return }
        closePlayground()
        showSidebar = true
        searching = false
        query = ""
        newItem = NewItem(kind: kind, parent: folder ?? LibraryOperations.targetFolder(for: sidebarFocus, root: rootFolder))
    }

    /// Creates the item being named, or drops it when the name is empty.
    func commitNewItem(named name: String) {
        guard let item = newItem else { return }
        newItem = nil
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch item.kind {
        case .file: createFile(named: name, in: item.parent)
        case .folder: createFolder(named: name, in: item.parent)
        }
    }

    func toggleSearch() {
        closePlayground()
        showSidebar = true
        searching.toggle()
        query = ""
    }

    func createFile(named name: String, in folder: URL?) {
        guard let target = folder ?? rootFolder else { notice = "Open a folder first."; return }
        perform { let url = try LibraryOperations.createFile(named: name, in: target); rescan(); select(url) }
    }

    func createFolder(named name: String, in folder: URL?) {
        guard let target = folder ?? rootFolder else { notice = "Open a folder first."; return }
        perform { _ = try LibraryOperations.createFolder(named: name, in: target); rescan() }
    }

    // MARK: playground

    var inPlayground: Bool {
        guard let session else { return false }
        return Playground.contains(session.url, in: playgroundDirectory)
    }

    /// Opens the scratch editor for `kind` (the last one used by default). Its text is kept between launches.
    func openPlayground(kind: DocumentKind? = nil) {
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
