import SwiftUI
import StudioCore

/// State behind the Slack tags window: the tag list and the tag being edited.
@MainActor
final class SlackTagsEditorModel: ObservableObject {
    struct Column: Identifiable {
        let id = UUID()
        var original: String?
        var name: String
    }

    struct Draft {
        var id: String
        var isNew: Bool
        var builtin: Bool
        var slackList: SlackList
        var name: String
        var kind: SlackTagKind
        var reactionsText: String
        var columns: [Column]
    }

    @Published private(set) var tags: [SlackTag] = []
    @Published var selectedID: String? { didSet { if selectedID != oldValue { loadDraft() } } }
    @Published var draft: Draft?
    @Published var error: String?
    @Published var confirmDelete = false

    private var store: SlackTaskStore?

    func load() {
        if store == nil { store = try? SlackTaskStore() }
        guard let store else { error = "Cannot open the Slack tasks database."; return }
        do {
            tags = try store.tags()
            if selectedID == nil || !tags.contains(where: { $0.id == selectedID }) { selectedID = tags.first?.id }
            loadDraft()
        } catch { self.error = error.localizedDescription }
    }

    private func loadDraft() {
        guard let tag = tags.first(where: { $0.id == selectedID }) else { return draft = nil }
        draft = Draft(id: tag.id, isNew: false, builtin: tag.builtin, slackList: tag.slackList, name: tag.name, kind: tag.kind,
                      reactionsText: tag.reactions.joined(separator: ", "), columns: tag.columns.map { Column(original: $0, name: $0) })
    }

    func addTag() {
        selectedID = nil
        draft = Draft(id: "", isNew: true, builtin: false, slackList: .none, name: "New tag", kind: .board, reactionsText: "",
                      columns: ["Todo", "In progress", "Blocked", "Done"].map { Column(original: nil, name: $0) })
    }

    func save() {
        guard var draft, let store else { return }
        let reactions = draft.reactionsText.split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ": ")).lowercased() }.filter { !$0.isEmpty }
        let columns = draft.columns.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        var renames: [String: String] = [:]
        for (column, name) in zip(draft.columns, columns) { if let old = column.original, old != name { renames[old] = name } }
        if draft.kind == .list { draft.columns = [] }
        let id = draft.isNew ? SlackTagRules.slug(for: draft.name, existing: Set(tags.map(\.id))) : draft.id
        let tag = SlackTag(id: id, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), kind: draft.kind, slackList: draft.slackList,
                           reactions: reactions, columns: draft.kind == .list ? [] : columns, position: 0, builtin: draft.builtin)
        do {
            try store.saveTag(tag, renames: renames)
            tags = try store.tags()
            selectedID = id
            loadDraft()
        } catch { self.error = error.localizedDescription }
    }

    func delete() {
        guard let draft, !draft.isNew, let store else { return }
        do {
            try store.deleteTag(draft.id)
            selectedID = nil
            load()
        } catch { self.error = error.localizedDescription }
    }

    func moveTag(by offset: Int) {
        guard let id = selectedID, let index = tags.firstIndex(where: { $0.id == id }), let store else { return }
        do {
            try store.moveTag(id, to: index + offset)
            tags = try store.tags()
        } catch { self.error = error.localizedDescription }
    }

    func addColumn() { draft?.columns.append(Column(original: nil, name: "New column")) }
    func removeColumn(_ id: UUID) { draft?.columns.removeAll { $0.id == id } }

    func moveColumn(_ id: UUID, by offset: Int) {
        guard let columns = draft?.columns, let index = columns.firstIndex(where: { $0.id == id }), columns.indices.contains(index + offset) else { return }
        draft?.columns.swapAt(index, index + offset)
    }
}

/// The "Slack tags" window: add, rename, reorder and delete tags, set their emoji and board columns.
struct SlackTagsEditorView: View {
    @StateObject private var editor = SlackTagsEditorModel()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $editor.selectedID) {
                    ForEach(editor.tags) { tag in
                        Text(tag.name).tag(Optional(tag.id))
                    }
                }
                Divider()
                HStack(spacing: 6) {
                    Button { editor.addTag() } label: { Image(systemName: "plus") }
                    Button { editor.moveTag(by: -1) } label: { Image(systemName: "arrow.up") }.disabled(editor.selectedID == nil)
                    Button { editor.moveTag(by: 1) } label: { Image(systemName: "arrow.down") }.disabled(editor.selectedID == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 200)
            Divider()
            detail
        }
        .frame(minWidth: 640, minHeight: 440)
        .onAppear { editor.load() }
        .alert("Slack tags", isPresented: Binding(get: { editor.error != nil }, set: { if !$0 { editor.error = nil } })) {
            Button("OK") { editor.error = nil }
        } message: {
            Text(editor.error ?? "")
        }
        .alert("Delete this tag?", isPresented: $editor.confirmDelete) {
            Button("Delete", role: .destructive) { editor.delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its cards are hidden, not deleted. Creating a tag with the same name shows them again.")
        }
    }

    @ViewBuilder private var detail: some View {
        if let draft = editor.draft {
            Form {
                TextField("Name", text: Binding(get: { draft.name }, set: { editor.draft?.name = $0 }))
                if !draft.builtin {
                    Picker("Kind", selection: Binding(get: { draft.kind }, set: { editor.draft?.kind = $0 })) {
                        Text("Board (columns)").tag(SlackTagKind.board)
                        Text("List (no statuses)").tag(SlackTagKind.list)
                    }
                    .disabled(!draft.isNew)
                }
                if draft.slackList != .none {
                    LabeledContent("Slack list", value: draft.slackList == .saved ? "Saved items" : "To-dos")
                }
                TextField("Emoji names", text: Binding(get: { draft.reactionsText }, set: { editor.draft?.reactionsText = $0 }),
                          prompt: Text("loading, loading1  (no colons)"))
                if draft.kind == .board {
                    Section("Columns (the first is where new cards land, the last counts as done)") {
                        ForEach(draft.columns) { column in
                            HStack {
                                TextField("Column", text: Binding(
                                    get: { editor.draft?.columns.first { $0.id == column.id }?.name ?? "" },
                                    set: { value in if let i = editor.draft?.columns.firstIndex(where: { $0.id == column.id }) { editor.draft?.columns[i].name = value } }
                                ))
                                Button { editor.moveColumn(column.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                Button { editor.moveColumn(column.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                Button { editor.removeColumn(column.id) } label: { Image(systemName: "minus.circle") }
                            }
                        }
                        Button("Add column") { editor.addColumn() }
                    }
                }
                HStack {
                    Button("Save") { editor.save() }.keyboardShortcut(.defaultAction)
                    if !draft.builtin && !draft.isNew {
                        Button("Delete tag…", role: .destructive) { editor.confirmDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            Text("Select a tag, or add one.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
