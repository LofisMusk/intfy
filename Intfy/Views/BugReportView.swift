import SwiftUI

/// Collects a title and description, then opens a prefilled GitHub issue in the browser.
struct BugReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var title = ""
    @State private var description = ""
    @State private var includeDiagnostics = false

    var body: some View {
        Form {
            Section {
                TextField("Short summary", text: $title)
            } header: {
                Text("Title")
            }

            Section {
                TextField("What did you do, what did you expect, what happened?",
                          text: $description, axis: .vertical)
                    .lineLimit(5...12)
            } header: {
                Text("Description")
            }

            Section {
                LabeledContent("intfy", value: "\(model.appVersion) · \(model.appCommit)")
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
                LabeledContent("Device", value: BugReport.deviceName)
            } header: {
                Text("Added automatically")
            }

            Section {
                Toggle("Include Diagnostics Log", isOn: $includeDiagnostics)
            } footer: {
                Text("""
                Adds the latest Diagnostics entries – very helpful for missed or late notifications. \
                They can contain server names or addresses; you can edit everything on GitHub before submitting.
                """)
            }

            Section {
                Button {
                    let report = BugReport(title: title, description: description, includeDiagnostics: includeDiagnostics)
                    if let url = report.url(model: model) { openURL(url) }
                } label: {
                    Label("Open Issue on GitHub", systemImage: "arrow.up.right.square")
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Opens a prefilled issue in your browser. Nothing is sent until you submit it there (needs a GitHub account).")
            }
        }
        .navigationTitle("Report a Bug")
        .navigationBarTitleDisplayMode(.inline)
    }
}
