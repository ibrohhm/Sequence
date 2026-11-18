import SwiftUI
import StudioCore

/// Loads the flow list and the open flow's graph from the shared database, and keeps them fresh while the Flows page is open.
@MainActor
final class FlowsModel: ObservableObject {
    @Published private(set) var flows: [FlowItem] = []
    @Published private(set) var selectedID: Int? = {
        let saved = UserDefaults.standard.integer(forKey: "flowSelected")
        return saved == 0 ? nil : saved
    }()
    @Published private(set) var graph: String?
    @Published var notice: String?

    private var store: FlowStore?
    private var lastVersion = -1
    private var polling: Task<Void, Never>?

    /// Name of the open flow.
    var selectedName: String? { flows.first { $0.id == selectedID }?.name }

    func start() {
        guard polling == nil else { return }
        reload()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.poll()
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
    }

    func select(_ id: Int) {
        guard id != selectedID else { return }
        selectedID = id
        UserDefaults.standard.set(id, forKey: "flowSelected")
        reload()
    }

    func create(_ name: String) {
        guard let store = openStore() else { return }
        do { select(try store.create(name: name)) } catch { notice = error.localizedDescription }
    }

    func rename(_ id: Int, to name: String) {
        guard let store = openStore() else { return }
        do {
            try store.rename(id, to: name)
            reload()
        } catch { notice = error.localizedDescription }
    }

    func delete(_ id: Int) {
        guard let store = openStore() else { return }
        do {
            try store.delete(id)
            reload()
        } catch { notice = error.localizedDescription }
    }

    private func openStore() -> FlowStore? {
        if store == nil { store = try? FlowStore() }
        if store == nil { notice = "Cannot open the flows database." }
        return store
    }

    func save(graph: String, flow id: Int) {
        guard let store else { return }
        do { try store.saveGraph(graph, flow: id) } catch { notice = error.localizedDescription }
    }

    private func poll() {
        guard let store else { return reload() }
        if let version = try? store.dataVersion(), version != lastVersion || notice != nil { reload() }
    }

    private func reload() {
        do {
            if store == nil { store = try FlowStore() }
            guard let store else { return }
            let version = try store.dataVersion()
            let loaded = try store.list()
            if let current = selectedID, !loaded.contains(where: { $0.id == current }) {
                selectedID = nil
                UserDefaults.standard.removeObject(forKey: "flowSelected")
            }
            flows = loaded
            let next = try selectedID.flatMap { try store.graph(id: $0) }
            if next != graph { graph = next }
            lastVersion = version
            notice = nil
        } catch {
            notice = error.localizedDescription
        }
    }
}
