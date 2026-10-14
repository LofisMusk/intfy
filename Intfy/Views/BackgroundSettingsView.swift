import SwiftUI

struct BackgroundSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Toggle("Silent Audio Keep-Alive", isOn: Binding(
                    get: { model.audioKeepAliveEnabled },
                    set: { model.setAudioKeepAlive($0) }
                ))
            } footer: {
                Text("""
                Plays inaudible silence so iOS keeps intfy running in the background. It mixes \
                with other audio, never interrupts your music and shows no playback controls. \
                Turn it off to rely on location alone – it uses less battery, but iOS may suspend the app.
                """)
            }

            Section {
                PermissionRows(locationOnly: true)
            } header: {
                Text("Location Keep-Alive")
            } footer: {
                Text("""
                Location set to “Always” keeps the app alive and lets iOS relaunch it if it was \
                terminated. Approximate accuracy is enough; your location is never stored or sent anywhere.
                """)
            }

            Section("Tips") {
                Label("Don't swipe intfy away in the app switcher – iOS may stop waking it up.",
                      systemImage: "hand.raised")
                Label("Low Power Mode makes iOS more aggressive about suspending apps.",
                      systemImage: "battery.25percent")
                Label("If notifications stop, open Diagnostics to see whether iOS suspended or killed the app.",
                      systemImage: "waveform.path.ecg")
            }
            .font(.subheadline)
        }
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
    }
}
