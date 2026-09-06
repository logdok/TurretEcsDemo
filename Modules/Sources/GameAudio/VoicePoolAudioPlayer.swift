import AVFoundation
import GameCore

/// A small round-robin pool of players routed through one dedicated mixer
/// "bus" node, shared by both `TurretFireAudio` and `EnemyDeathAudio` so bus
/// volume and mute can be controlled entirely from outside (see each of their
/// `bus` properties) rather than adding bespoke methods to either.
///
/// Each voice chain is `player -> varispeed -> bus`: `AVAudioUnitVarispeed`
/// shifts speed and pitch together — "tape speed" semantics, unlike
/// `AVAudioUnitTimePitch`, which would shift pitch independently of speed.
package final class VoicePoolAudioPlayer {
    package let bus: AVAudioMixerNode

    private var buffers: [AVAudioPCMBuffer] = []
    private var voices: [(player: AVAudioPlayerNode, varispeed: AVAudioUnitVarispeed)] = []
    private var nextVoiceIndex = 0
    private let rng: SeededRNG

    /// `seed` should be independent of `GameContext.rng`'s seed: picking a
    /// clip or a pitch jitter is purely cosmetic and must never perturb the
    /// deterministic simulation's own random draws (spawns, archetype picks).
    package init(engine: AVAudioEngine, voiceCount: Int, clipURLs: [URL], seed: Int64) {
        rng = SeededRNG(seed: seed)
        bus = AVAudioMixerNode()
        engine.attach(bus)
        engine.connect(bus, to: engine.mainMixerNode, format: nil)

        for url in clipURLs {
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
            guard (try? file.read(into: buffer)) != nil else { continue }
            buffers.append(buffer)
        }

        let connectFormat = buffers.first?.format
        for _ in 0..<voiceCount {
            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            engine.attach(player)
            engine.attach(varispeed)
            engine.connect(player, to: varispeed, format: connectFormat)
            engine.connect(varispeed, to: bus, format: connectFormat)
            voices.append((player, varispeed))
        }
    }

    package var hasClips: Bool { !buffers.isEmpty }

    package func playRandomClip(pitchJitter: Float = 0) {
        guard !buffers.isEmpty, !voices.isEmpty else { return }
        let (player, varispeed) = voices[nextVoiceIndex]
        nextVoiceIndex = (nextVoiceIndex + 1) % voices.count
        let buffer = buffers[Int(rng.randi() % UInt32(buffers.count))]
        varispeed.rate = pitchJitter > 0 ? (1.0 - pitchJitter + rng.randf() * (2 * pitchJitter)) : 1.0
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }
}
