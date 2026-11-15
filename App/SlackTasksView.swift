import SwiftUI
import StudioCore

/// The Slack tasks board: four status columns of cards, filled by the sync tool and arranged by hand.
struct SlackTasksView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var board = SlackTasksModel()
    @State private var link = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if let notice = board.notice {
                Text(notice).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Color.yellow.opacity(0.2))
            }
            if board.tasks.isEmpty {
                Text("No Slack tasks yet. Tag a thread with :loading: and tell Claude \"sync my Slack tasks\".")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(SlackStatus.allCases, id: \.self) { column($0) }
                    }
                    .padding(12)
                    if board.showArchived { archived }
                }
            }
        }
        .onAppear { board.start() }
        .onDisappear { board.stop() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Slack tasks").font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 0)
            TextField("Paste a Slack link", text: $link)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 8).padding(.vertical, 6).frame(width: 280)
                .background(RoundedRectangle(cornerRadius: 6).fill(model.theme.hoverRow))
                .onSubmit(addLink)
            ChromeIconButton(symbol: "plus", help: "Add task", size: 28, tip: .belowTrailing, action: addLink)
            Toggle("Show archived", isOn: $board.showArchived).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(model.theme.border).frame(height: 1) }
    }

    private func addLink() {
        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        board.add(link)
        link = ""
    }

    private func column(_ status: SlackStatus) -> some View {
        let tasks = board.columns[status] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(status.title).font(.system(size: 12, weight: .semibold))
                Text("\(tasks.count)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
            ForEach(tasks) { task in
                TaskCard(task: task, onArchive: { board.archive(task.id) })
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(model.theme.sidebarBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.theme.border))
        .dropDestination(for: String.self) { ids, _ in
            ids.forEach { board.move($0, to: status) }
            return !ids.isEmpty
        }
    }

    private var archived: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Archived").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 2)
            ForEach(board.archivedTasks) { task in
                HStack(spacing: 8) {
                    Text(TaskCard.channelLabel(task)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text(TaskCard.snippet(task)).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Restore") { board.restore(task.id) }.controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.sidebarBackground))
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
    }
}

private struct TaskCard: View {
    @EnvironmentObject var model: AppModel
    let task: SlackTask
    let onArchive: () -> Void

    static func channelLabel(_ task: SlackTask) -> String { task.channelName.map { "#\($0)" } ?? task.channelID }
    static func snippet(_ task: SlackTask) -> String {
        (task.snippet ?? task.permalink).replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.channelLabel(task)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let last = task.lastReply {
                    Text(RelativeDateTimeFormatter.abbreviated.localizedString(for: last, relativeTo: Date()))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Text(task.summary ?? Self.snippet(task)).font(.system(size: 13)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            if let next = task.nextAction, !next.isEmpty {
                Text("→ \(next)").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                if let replies = task.replies {
                    Text("\(replies) \(replies == 1 ? "reply" : "replies")").foregroundStyle(.secondary)
                } else {
                    Text("Waiting for sync").foregroundStyle(.secondary)
                }
                if let new = task.newReplies {
                    Label("\(new) new", systemImage: "circle.fill").labelStyle(CardBadge()).foregroundStyle(model.theme.accent)
                }
                if let days = task.quietDays(now: Date()) {
                    Label("quiet \(days)d", systemImage: "clock").labelStyle(CardBadge()).foregroundStyle(model.theme.accent)
                }
            }
            .font(.system(size: 11))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.theme.border))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: task.permalink) { NSWorkspace.shared.open(url) }
        }
        .draggable(task.id)
        .contextMenu { Button("Archive", action: onArchive) }
    }
}

private struct CardBadge: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 6))
            configuration.title
        }
    }
}

private extension RelativeDateTimeFormatter {
    static let abbreviated: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
