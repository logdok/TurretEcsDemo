import AVFoundation
import GameSimulation

/// Plays a short explosion sound on every hostile-entity destruction — shot
/// down (`GameContext.killCount`) or reaching the core
/// (`GameContext.breachCount`). Not tied to
/// the turret — explosions happen anywhere on the arena — so this is its own
/// presentation-layer object rather than part of `TurretPresenter`.
///
/// Unlike the turret's own fire sound (at most one shot per frame), MANY
/// enemies can die in the SAME frame: `DamageResolutionSystem` and
/// `CoreBreachSystem` each resolve their whole candidate list in one pass. A
/// naive "one sound per death" would become a wall of noise the moment the
/// core gets swarmed, so playback is capped at `voicePoolSize` triggers per
/// frame — extra simultaneous deaths beyond what the pool can voice would
/// only steal a channel from each other anyway. A `pitchJitter` of ±8% adds
/// variety on top of the (only three) source clips — the fire sound has no
/// equivalent need, since it already has 31 natural variants from one recording.
package final class EnemyDeathAudio {
    package init() {}

    package static let voicePoolSize = 8
    package static let pitchJitter: Float = 0.08

    private var context: GameContext!
    private var voicePool: VoicePoolAudioPlayer!
    private var lastDeathCount = 0

    /// See `TurretFireAudio.configure` on why the clip list is a defaulted
    /// parameter rather than a hard-wired lookup.
    package func configure(engine: AVAudioEngine, context: GameContext, clipURLs: [URL] = AudioClipLibrary.enemyExplosion) {
        self.context = context
        lastDeathCount = context.killCount + context.breachCount
        voicePool = VoicePoolAudioPlayer(engine: engine, voiceCount: Self.voicePoolSize, clipURLs: clipURLs, seed: 0xE4E5)
    }

    package var bus: AVAudioMixerNode { voicePool.bus }

    /// Called once per frame after the scheduler has run.
    package func refresh() {
        guard let context, voicePool.hasClips else { return }
        let deaths = context.killCount + context.breachCount
        let newDeaths = deaths - lastDeathCount
        if newDeaths > 0 {
            let triggers = min(newDeaths, EnemyDeathAudio.voicePoolSize)
            for _ in 0..<triggers {
                voicePool.playRandomClip(pitchJitter: Self.pitchJitter)
            }
        }
        lastDeathCount = deaths
    }
}
