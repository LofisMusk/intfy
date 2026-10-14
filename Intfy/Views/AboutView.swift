import SwiftUI

struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    SettingsIcon(systemName: "bell.fill", color: .intfy, size: 76)
                    Text("intfy").font(.title2.bold())
                    Text("ntfy notifications from your own server – no APNs, no Apple servers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Version", value: model.appVersion)
                LabeledContent("Commit") {
                    Text(model.appCommit).monospaced()
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/LofisMusk/intfy")!) {
                    Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://docs.ntfy.sh")!) {
                    Label("ntfy Documentation", systemImage: "book")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
