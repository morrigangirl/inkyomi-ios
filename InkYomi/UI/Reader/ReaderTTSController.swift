import Foundation
import MediaPlayer
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumNavigator

/// Accessible in-app **read-aloud**, built on Readium's
/// `PublicationSpeechSynthesizer`.
///
/// Gives blind and low-vision readers continuous narration that **auto-advances
/// the page** (via `onAdvance`), plus **lock-screen / headset transport
/// controls** (`MPRemoteCommandCenter`) so playback can be driven without
/// looking at the screen. Readium's synthesizer owns the `AVAudioSession`
/// (`.playback` / `.spokenAudio`, long-form), so with the `audio`
/// `UIBackgroundMode` set, narration continues while the screen is locked.
///
/// This is distinct from VoiceOver: it is a single, continuous reading voice
/// with media controls, rather than element-by-element navigation.
@MainActor
final class ReaderTTSController: PublicationSpeechSynthesizerDelegate {

    /// True when the publication has speakable text.
    var isAvailable: Bool { synthesizer != nil }

    /// Fired when narration starts/stops, so the UI can reflect play state.
    var onPlayingChanged: ((Bool) -> Void)?

    /// Fired with the locator of each new sentence so the host can turn the
    /// page to follow the narration. (Readium no-ops if it's already visible.)
    var onAdvance: ((Locator) -> Void)?

    private let synthesizer: PublicationSpeechSynthesizer?
    private let title: String
    private var lastUtteranceLocator: Locator?
    private var remoteConfigured = false

    init(publication: Publication, title: String) {
        self.title = title
        self.synthesizer = PublicationSpeechSynthesizer(publication: publication)
        self.synthesizer?.delegate = self
    }

    /// Toggle narration: pause when playing, resume when paused, or start from
    /// `locator` (the current reading position) when stopped.
    func toggle(from locator: Locator?) {
        guard let synthesizer else { return }
        switch synthesizer.state {
        case .playing:
            synthesizer.pause()
        case .paused:
            synthesizer.resume()
        case .stopped:
            configureRemoteCommands()
            synthesizer.start(from: locator)
        }
    }

    func skipNext() { synthesizer?.next() }
    func skipPrevious() { synthesizer?.previous() }

    func stop() {
        synthesizer?.stop()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - PublicationSpeechSynthesizerDelegate

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        stateDidChange state: PublicationSpeechSynthesizer.State
    ) {
        let playing: Bool
        var utteranceLocator: Locator?
        switch state {
        case let .playing(utterance, range: _):
            playing = true
            utteranceLocator = utterance.locator
        case .paused, .stopped:
            playing = false
        }

        onPlayingChanged?(playing)

        // Follow the narration: turn the page on each new sentence.
        if let loc = utteranceLocator, loc != lastUtteranceLocator {
            lastUtteranceLocator = loc
            onAdvance?(loc)
        }

        updateNowPlaying(playing: playing)
    }

    func publicationSpeechSynthesizer(
        _ synthesizer: PublicationSpeechSynthesizer,
        utterance: PublicationSpeechSynthesizer.Utterance,
        didFailWithError error: PublicationSpeechSynthesizer.Error
    ) {
        onPlayingChanged?(false)
    }

    // MARK: - Lock screen / headset controls

    private func configureRemoteCommands() {
        guard !remoteConfigured else { return }
        remoteConfigured = true
        let center = MPRemoteCommandCenter.shared()
        // MPRemoteCommand handlers are delivered on the main thread.
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.synthesizer?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.synthesizer?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.synthesizer?.pauseOrResume() }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.synthesizer?.next() }
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.synthesizer?.previous() }
            return .success
        }
    }

    private func updateNowPlaying(playing: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = "InkYomi"
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
