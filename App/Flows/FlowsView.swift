import SwiftUI
import StudioCore

/// The Flows page: the canvas fills the panel; a pill at its top left names the open flow and opens a floating list of flows.
struct FlowsView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var flows = FlowsModel()
    @State private var open = false
    @State private var pillHover = false
    @State private var prompt: FlowPrompt?
    @State private var promptText = ""
    @State private var deleteTarget: FlowItem?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                FlowWebView(flowID: flows.selectedID, graph: flows.graph, theme: model.theme, onChanged: { id, graph in flows.save(graph: graph, flow: id) })
                if flows.selectedID == nil && !open {
                    Text(flows.flows.isEmpty ? "Flows you create with Claude show here." : "Pick a flow from the list.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            if open {
                Color.clear.contentShape(Rectangle()).onTapGesture { open = false }
            }
            VStack(alignment: .leading, spacing: 8) {
                pill
                if let notice = flows.notice {
                    Text(notice).font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 360, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.attentionFill))
                }
                if open { listPanel }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            flows.start()
            if flows.selectedID == nil && !flows.flows.isEmpty { open = true }
        }
        .onDisappear { flows.stop() }
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { current in
            TextField("Name", text: $promptText)
            Button(current.button) {
                switch current {
                case .create: flows.create(promptText)
                case .rename(let item): flows.rename(item.id, to: promptText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \"\(deleteTarget?.name ?? "")\"?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { item in
            Button("Delete flow", role: .destructive) { flows.delete(item.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its nodes and connectors are lost. This cannot be undone.")
        }
    }

    private func ask(_ next: FlowPrompt) {
        promptText = next.initial
        prompt = next
    }

    private var pill: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 12)).foregroundStyle(.secondary)
                Text(flows.selectedName ?? "Flows").font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7).frame(maxWidth: 420, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.cardBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(pillHover || open ? model.theme.cardBorderHover : model.theme.cardBorder))
            .shadow(color: model.theme.cardShadow, radius: 4, y: 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Choose a flow")
        .onHover { inside in
            guard inside != pillHover else { return }
            pillHover = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if pillHover { pillHover = false; NSCursor.pop() } }
    }

    private var listPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            if flows.flows.isEmpty {
                Text("No flows yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(flows.flows) { item in
                            FlowRow(
                                title: item.name, selected: flows.selectedID == item.id,
                                onSelect: {
                                    flows.select(item.id)
                                    open = false
                                },
                                onRename: { ask(.rename(item)) },
                                onDelete: { deleteTarget = item }
                            )
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
            Rectangle().fill(model.theme.border).frame(height: 1).padding(.vertical, 4)
            NewFlowRow { ask(.create) }
        }
        .padding(8)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 10).fill(model.theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.theme.cardBorderHover))
        .shadow(color: model.theme.cardShadow, radius: 10, y: 4)
    }
}

private enum FlowPrompt {
    case create
    case rename(FlowItem)

    var title: String {
        switch self {
        case .create: return "New flow"
        case .rename: return "Rename flow"
        }
    }

    var button: String {
        switch self {
        case .create: return "Create flow"
        case .rename: return "Rename"
        }
    }

    var initial: String {
        switch self {
        case .create: return ""
        case .rename(let item): return item.name
        }
    }
}

private struct NewFlowRow: View {
    @EnvironmentObject var model: AppModel
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                Text("New flow").font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(model.theme.accent)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? model.theme.hoverRow : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            guard inside != hovering else { return }
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if hovering { hovering = false; NSCursor.pop() } }
    }
}

private struct FlowRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let selected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onSelect) {
                Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                    .padding(.leading, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hovering {
                iconButton("pencil", help: "Rename flow", action: onRename)
                iconButton("trash", help: "Delete flow", action: onDelete)
            }
        }
        .padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? model.theme.selectedRow : (hovering ? model.theme.hoverRow : Color.clear)))
        .onHover { inside in
            guard inside != hovering else { return }
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if hovering { hovering = false; NSCursor.pop() } }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
