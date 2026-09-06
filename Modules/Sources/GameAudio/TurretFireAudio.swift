import AVFoundation
import GameSimulation

/// Plays a short gunshot sound on every turret shot. A separate object from
/// the visual rig (`TurretPresenter`), and now a separate module: the audio
/// graph and the render rig share nothing but the counter they both read.
///
/// Follows `GameContext.shotsFired` rather than being called directly from
/// `TurretFiringSystem` — the same "presentation reads the simulation, never
/// drives it" split applies here as everywhere else: the game layer stays
/// unaware that anything is listening at all.
///
/// The source clip was a single 5.7s recording that turned out to be a
/// solid burst of about 32 back-to-back shots, not one shot with reverb tail
/// (confirmed by envelope peak-picking — energy never dropped below 3% of
/// peak). It is pre-sliced into `Resources/Audio/TurretFire/hit_NN.wav`
/// (31 short fragments); a random one plays per shot through a small voice
/// pool instead of restarting one long sample at rates of up to 40 shots/s.
package final class TurretFireAudio {
    package init() {}

    package static let voicePoolSize = 6

    private var context: GameContext!
    private var voicePool: VoicePoolAudioPlayer!
    private var lastShotsFired = 0

    /// `clipURLs` defaults to this module's own bundled clips, so the
    /// composition root no longer has to know where the audio files live.
    /// It stays a parameter so a test or a feature demo can hand in its own.
    package func configure(engine: AVAudioEngine, context: GameContext, clipURLs: [URL] = AudioClipLibrary.turretFire) {
        self.context = context
        lastShotsFired = context.shotsFired
        voicePool = VoicePoolAudioPlayer(engine: engine, voiceCount: Self.voicePoolSize, clipURLs: clipURLs, seed: 0xF12E)
    }

    package var bus: AVAudioMixerNode { voicePool.bus }

    /// A single shot can raise the counter by exactly one per frame (there is
    /// one turret, and `TurretFiringSystem` fires at most once per turret per
    /// frame), so a plain "did it increase" check is enough. A decrease
    /// (population/world reset via `SimulationBootstrap.restart`) silently
    /// resynchronises rather than being read as a shot.
    package func refresh() {
        guard let context, voicePool.hasClips else { return }
        let shots = context.shotsFired
        if shots > lastShotsFired {
            voicePool.playRandomClip()
        }
        lastShotsFired = shots
    }
}
