import SwiftUI

struct MessagesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        // No navigation bar: the title sits at the very top and scrolls with the list.
        if model.store.messages.isEmpty {
            VStack(spacing: 0) {
                header
                ContentUnavailableView(
                    "No messages",
                    systemImage: "bell.slash",
                    description: Text(model.activeServers.isEmpty
                        ? "Add your ntfy server in the Settings tab."
                        : "New messages from your servers will show up here and as notifications.")
                )
            }
        } else {
            List {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                ForEach(model.store.messages) { message in
                    MessageRow(message: message, serverName: model.server(with: message.serverID)?.displayName)
                        .contentShape(Rectangle())
                        .onTapGesture { if let url = message.clickURL { openURL(url) } }
                        .contextMenu {
                            Button("Copy Text", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = message.message
                            }
                            if let url = message.attachment.flatMap({ URL(string: $0.url) }) {
                                Button("Open Attachment", systemImage: "paperclip") { openURL(url) }
                            }
                        }
                }
                .onDelete { offsets in
                    offsets.map { model.store.messages[$0] }.forEach(model.store.delete)
                }
            }
            .listStyle(.plain)
            .refreshable { await model.pollAll() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Messages")
                .font(.largeTitle.bold())
            Spacer()
            if !model.store.messages.isEmpty {
                Button("Clear", systemImage: "trash") { model.store.clear() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct MessageRow: View {
    let message: NtfyMessage
    let serverName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                priorityIcon
                Text(message.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(message.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !message.notificationBody.isEmpty {
                Text(message.notificationBody)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
            }
            HStack(spacing: 6) {
                chip(message.topic, systemImage: "number")
                if let serverName {
                    chip(serverName, systemImage: "server.rack")
                }
                ForEach(message.textTags, id: \.self) { tag in
                    Text("#\(tag)").font(.caption2).foregroundStyle(.secondary)
                }
                if message.clickURL != nil {
                    Image(systemName: "link").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text).lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.tint.opacity(0.15), in: Capsule())
    }

    @ViewBuilder private var priorityIcon: some View {
        switch message.effectivePriority {
        case 5: Image(systemName: "exclamationmark.2").foregroundStyle(.red)
        case 4: Image(systemName: "exclamationmark").foregroundStyle(.orange)
        case ...2: Image(systemName: "arrow.down").foregroundStyle(.secondary)
        default: EmptyView()
        }
    }
}
