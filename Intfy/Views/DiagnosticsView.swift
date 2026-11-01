import SwiftUI

struct DiagnosticsView: View {
    private let log = DiagnosticsLog.shared

    var body: some View {
        List {
            Section {
                Text("""
                A heartbeat is recorded every minute. “Not running for…” means iOS suspended the app; \
                “ended without notice” means iOS killed it (or it crashed – check Settings → Privacy & Security → \
                Analytics & Improvements → Analytics Data for files starting with “Intfy”). While unplugged, \
                every 5 % of battery used is logged with the drain rate of the whole phone.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                if log.entries.isEmpty {
                    Text("No events yet").foregroundStyle(.secondary)
                }
                ForEach(log.entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text).font(.callout)
                        Text(DiagnosticsLog.format(entry.date))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = log.exportText }
                Button("Clear", systemImage: "trash", role: .destructive) { log.clear() }
            }
        }
    }
}
