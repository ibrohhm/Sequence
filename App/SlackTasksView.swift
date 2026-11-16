import SwiftUI
import StudioCore

/// The Tasks page (every board tag as a section, or all merged into one board) and one page per list tag.
struct SlackTasksView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var board = SlackTasksModel()
    @Environment(\.openWindow) private var openWindow
    @AppStorage("groupTasksByTag") private var grouped = true
    @State private var link = ""

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            tabBar
            if let notice = board.notice {
                Text(notice).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8).background(model.theme.attentionFill)
            }
            if board.tasks.isEmpty {
                Text(emptyText).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if board.isTasksPage {
                        if grouped { sectionsPage } else { mergedPage }
                    } else {
                        listPage
                    }
                    if board.showArchived { archived }
                }
            }
        }
        .onAppear { board.start() }
        .onDisappear { board.stop() }
    }

    // MARK: Header

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text(board.isTasksPage ? "Tasks" : (board.currentListTag?.name ?? "Tasks")).font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 0)
            if board.isTasksPage, let target = board.addTag {
                Menu {
                    ForEach(board.boardTags) { tag in Button(tag.name) { board.setAddTag(tag.id) } }
                } label: {
                    Text("Add to \(target.name)").font(.system(size: 12))
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            TextField("Paste a Slack link", text: $link)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 6).frame(width: 240)
                .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.chipFill))
                .onSubmit(addLink)
            ChromeIconButton(symbol: "plus", help: "Add to this page", size: 28, tip: .belowTrailing, action: addLink)
            if let tags = titleSyncTags {
                syncButton(key: tags.key, help: tags.help, size: 28, glyph: 15) { board.sync(tags: tags.tags, key: tags.key) }
            }
            Toggle("Archived", isOn: $board.showArchived).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(model.theme.border).frame(height: 1) }
    }

    /// The page-level sync: a list page's own tag, or every board tag when the Tasks page is merged (split mode syncs per section).
    private var titleSyncTags: (tags: [SlackTag], key: String, help: String)? {
        if let list = board.currentListTag { return ([list], SlackTasksModel.syncKey(tag: list.id), "Sync \(list.name)") }
        if board.isTasksPage, !grouped, !board.boardTags.isEmpty { return (board.boardTags, "tag:*", "Sync all tasks") }
        return nil
    }

    @ViewBuilder private func syncButton(key: String, help: String, size: CGFloat, glyph: CGFloat, action: @escaping () -> Void) -> some View {
        if board.syncing.contains(key) {
            ProgressView().controlSize(.small).frame(width: size, height: size).help("Syncing…")
        } else {
            ChromeIconButton(symbol: "arrow.triangle.2.circlepath", help: help, size: size, glyph: glyph, tip: .aboveTrailing, action: action)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(board.pages, id: \.id) { page in
                    TagTab(name: page.title, selected: page.id == board.selectedPage) { board.select(page: page.id) }
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(model.theme.tabTrack))
            Button("Edit tags…") { openWindow(id: "slack-tags") }.controlSize(.small)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }

    private func addLink() {
        guard !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        board.add(link)
        link = ""
    }

    // MARK: Pages

    /// Each board tag is a collapsible section with its own four columns.
    private var sectionsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(board.sections, id: \.tag.id) { section in
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(section.tag, count: section.columns.reduce(0) { $0 + $1.tasks.count })
                    if !board.collapsed.contains(section.tag.id) {
                        columnsRow(section.columns, section: section.tag.id)
                    }
                }
            }
        }
        .padding(16)
    }

    /// Every board tag's cards in one set of four columns.
    private var mergedPage: some View {
        columnsRow(board.mergedColumns, section: nil).padding(16)
    }

    private func columnsRow(_ columns: [(name: String, tasks: [SlackTask])], section: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(columns.enumerated()), id: \.element.name) { index, column in
                BoardColumn(name: column.name, icon: columnIcon(index, of: columns.count), count: column.tasks.count,
                            onDrop: { ids in drop(ids, on: column.name, section: section) }) {
                    ForEach(column.tasks) { card($0, list: false) }
                }
            }
        }
    }

    private func sectionHeader(_ tag: SlackTag, count: Int) -> some View {
        let isCollapsed = board.collapsed.contains(tag.id)
        return HStack(spacing: 8) {
            Button { board.toggleCollapsed(tag.id) } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 12)
                    Text(tag.name).font(.system(size: 14, weight: .semibold))
                    CountChip(count: count)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(tag.name), \(count) tasks, \(isCollapsed ? "collapsed" : "expanded")")
            let key = SlackTasksModel.syncKey(tag: tag.id)
            syncButton(key: key, help: "Sync \(tag.name)", size: 24, glyph: 13) { board.sync(tags: [tag], key: key) }
        }
    }

    private var listPage: some View {
        VStack(spacing: 10) {
            ForEach(board.listCards) { card($0, list: true) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14).fill(model.theme.columnBackground))
        .padding(16).frame(maxWidth: 720).frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var archived: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Archived").font(.system(size: 13, weight: .medium)).padding(.horizontal, 2)
            ForEach(board.archivedTasks) { task in
                HStack(spacing: 10) {
                    if let number = task.number { Text("#\(number)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary) }
                    if board.isTasksPage { Chip(text: board.tagName(task.tag) ?? task.tag) }
                    Text(TaskCard.channelLabel(task)).font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(TaskCard.title(task)).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                    ChromeIconButton(symbol: "arrow.up.right.square", help: "Open in Slack", size: 24, glyph: 13, tip: .aboveTrailing) {
                        if let url = URL(string: task.permalink) { NSWorkspace.shared.open(url) }
                    }
                    Button("Restore") { board.restore(task.id) }.controlSize(.small)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(model.theme.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.theme.cardBorder))
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private func card(_ task: SlackTask, list: Bool) -> some View {
        TaskCard(task: task, list: list, doneColumn: list ? nil : SlackColumns.done, tagName: list ? nil : board.tagName(task.tag),
                 syncing: board.syncing.contains(SlackTasksModel.syncKey(task: task.id)),
                 onSync: { board.sync(task: task) }, onArchive: { board.archive(task.id) })
    }

    private func drop(_ ids: [String], on column: String, section: String?) -> Bool {
        ids.forEach { board.move($0, to: column, inSection: section) }
        return !ids.isEmpty
    }

    /// Dashed circle for the first column, a check for the last, a half circle between.
    private func columnIcon(_ index: Int, of count: Int) -> String {
        if index == 0 { return "circle.dashed" }
        if index == count - 1 { return "checkmark.circle" }
        return "circle.lefthalf.filled"
    }

    private var emptyText: String {
        if let list = board.currentListTag {
            var parts: [String] = []
            if !list.reactions.isEmpty { parts.append("React with \(list.reactions.map { ":\($0):" }.joined(separator: " ")) on a Slack message") }
            if list.slackList == .saved { parts.append("save a message in Slack") }
            let how = parts.isEmpty ? "Add this tag's emoji in Edit tags" : parts.joined(separator: " or ")
            return "Nothing here yet. \(how), then tell Claude \"sync the \(list.name) tag\"."
        }
        return "No tasks yet. Tag a Slack thread with one of your task emoji (see Edit tags…) or paste a link above, then tell Claude \"sync my Slack tasks\"."
    }
}

// MARK: Pieces

private struct TagTab: View {
    @EnvironmentObject var model: AppModel
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8).fill(model.theme.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.theme.cardBorder))
                            .shadow(color: model.theme.cardShadow, radius: 1, y: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

private struct BoardColumn<Cards: View>: View {
    @EnvironmentObject var model: AppModel
    let name: String
    let icon: String
    let count: Int
    let onDrop: ([String]) -> Bool
    @ViewBuilder let cards: () -> Cards
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary)
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                CountChip(count: count)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.top, 4)
            cards()
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(model.theme.columnBackground))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(targeted ? model.theme.accent : Color.clear, lineWidth: 1.5))
        .dropDestination(for: String.self) { ids, _ in onDrop(ids) } isTargeted: { targeted = $0 }
    }
}

private struct CountChip: View {
    @EnvironmentObject var model: AppModel
    let count: Int

    var body: some View {
        Text("\(count)").font(.system(size: 12, weight: .medium)).foregroundStyle(model.theme.chipText)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(model.theme.chipFill))
    }
}

private struct Chip: View {
    @EnvironmentObject var model: AppModel
    let text: String
    var symbol: String?
    var attention = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: symbol == "circle.fill" ? 6 : 10)) }
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(attention ? model.theme.attentionText : model.theme.chipText)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(attention ? model.theme.attentionFill : model.theme.chipFill))
    }
}

/// Lays chips out left to right and wraps them onto new lines.
private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct TaskCard: View {
    @EnvironmentObject var model: AppModel
    let task: SlackTask
    let list: Bool
    let doneColumn: String?
    var tagName: String?
    let syncing: Bool
    let onSync: () -> Void
    let onArchive: () -> Void
    @State private var hovering = false

    static func channelLabel(_ task: SlackTask) -> String { task.channelName.map { "#\($0)" } ?? task.channelID }
    static func title(_ task: SlackTask) -> String {
        (task.summary ?? task.snippet ?? task.permalink).replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.title(task)).font(.system(size: 14, weight: .medium)).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !list, let next = task.nextAction, !next.isEmpty {
                Text("→ \(next)").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hasChips {
                ChipFlow {
                    if let tagName { Chip(text: tagName) }
                    if task.synced == nil {
                        Chip(text: "Waiting for sync")
                    } else if !list, let replies = task.replies {
                        Chip(text: "\(replies) \(replies == 1 ? "reply" : "replies")")
                    }
                    if let new = task.newReplies { Chip(text: "\(new) new", symbol: "circle.fill", attention: true) }
                    if !list, let days = task.quietDays(now: Date(), doneColumn: doneColumn) {
                        Chip(text: "quiet \(days)d", symbol: "clock", attention: true)
                    }
                }
            }
            HStack(spacing: 8) {
                if let number = task.number {
                    Text("#\(number)").font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left").font(.system(size: 10))
                    Text(task.channelName ?? task.channelID).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let last = task.lastReply {
                    Text(RelativeDateTimeFormatter.abbreviated.localizedString(for: last, relativeTo: Date()))
                }
                if syncing {
                    ProgressView().controlSize(.small).frame(width: 24, height: 24).help("Syncing…")
                } else {
                    ChromeIconButton(symbol: "arrow.triangle.2.circlepath", help: "Sync this task", size: 24, glyph: 13, tip: .aboveTrailing, action: onSync)
                }
                ChromeIconButton(symbol: "arrow.up.right.square", help: "Open in Slack", size: 24, glyph: 13, tip: .aboveTrailing) {
                    if let url = URL(string: task.permalink) { NSWorkspace.shared.open(url) }
                }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(model.theme.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(hovering ? model.theme.cardBorderHover : model.theme.cardBorder))
        .shadow(color: model.theme.cardShadow, radius: 2, y: 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .draggable(task.id)
        .contextMenu { Button("Archive", action: onArchive) }
    }

    private var hasChips: Bool {
        tagName != nil || task.synced == nil || (!list && task.replies != nil) || task.newReplies != nil || (!list && task.quietDays(now: Date(), doneColumn: doneColumn) != nil)
    }
}

private extension RelativeDateTimeFormatter {
    static let abbreviated: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
