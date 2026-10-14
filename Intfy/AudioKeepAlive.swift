import AVFoundation

/// Second keep-alive: loops a buffer of silence with the `audio` background mode. While audio
/// is playing iOS does not suspend the app — more dependable than location alone, which iOS
/// may stop honouring at coarse accuracy. The session mixes with others, so it never stops
/// the user's music and shows no Now Playing controls.
@MainActor
final class AudioKeepAlive {
    var onEvent: (String) -> Void = { _ in }

    private var player: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []

    var isPlaying: Bool { player?.isPlaying ?? false }

    func start() {
        guard !isPlaying else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try player ?? AVAudioPlayer(data: Self.silence)
            player.numberOfLoops = -1
            player.prepareToPlay()
            guard player.play() else {
                onEvent("Silent audio keep-alive could not start playing")
                return
            }
            self.player = player
            observeSession()
            onEvent("Silent audio keep-alive running")
        } catch {
            onEvent("Silent audio keep-alive failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onEvent("Silent audio keep-alive stopped")
    }

    private func observeSession() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                switch raw.flatMap(AVAudioSession.InterruptionType.init) {
                case .began:
                    self?.onEvent("Audio interrupted (call, Siri, alarm…)")
                case .ended:
                    // Resume even without .shouldResume — silence never bothers anyone.
                    self?.player?.stop()
                    self?.start()
                default:
                    break
                }
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onEvent("Audio services were reset")
                self?.player = nil
                self?.start()
            }
        })
    }

    /// One second of 8 kHz mono 16-bit PCM silence as a WAV file, looped forever.
    private static let silence: Data = {
        let sampleRate: UInt32 = 8000
        let dataSize: UInt32 = sampleRate * 2
        var wav = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + dataSize))
        wav.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                 // PCM, mono
        append(sampleRate); append(sampleRate * 2)           // sample rate, byte rate
        append(UInt16(2)); append(UInt16(16))                // block align, bits per sample
        wav.append(contentsOf: Array("data".utf8)); append(dataSize)
        wav.append(Data(count: Int(dataSize)))
        return wav
    }()
}
