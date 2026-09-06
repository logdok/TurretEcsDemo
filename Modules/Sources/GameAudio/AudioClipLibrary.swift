import Foundation

/// Where this module's own sound clips come from.
///
/// The clips used to be app-bundle resources looked up by the composition
/// root, which meant the app shell had to know both that audio exists and how
/// its folders are laid out. Inside a package they are `Bundle.module`
/// resources instead: the module owns its files, resolves them itself, and
/// the shell is not involved at all. That is the whole "resources move with
/// the module" trade the split buys — and it is why nothing outside this file
/// ever spells a `hit_NN.wav` path again.
///
/// A missing clip is not fatal anywhere downstream: both players check
/// `hasClips` and simply stay silent, so a resource-bundle problem costs the
/// sound, never the frame.
enum AudioClipLibrary {
    /// 31 fragments sliced from one continuous burst recording — see
    /// `TurretFireAudio` for why a single long sample would not work.
    static let turretFire: [URL] = clips(subdirectory: "Audio/TurretFire", count: 31)

    static let enemyExplosion: [URL] = clips(subdirectory: "Audio/EnemyExplosion", count: 3)

    /// Clips are named `hit_00.wav` … `hit_NN.wav`. `compactMap` rather than a
    /// force-unwrap: an incomplete set degrades to a smaller pool instead of
    /// trapping.
    private static func clips(subdirectory: String, count: Int) -> [URL] {
        (0..<count).compactMap {
            Bundle.module.url(forResource: String(format: "hit_%02d", $0), withExtension: "wav", subdirectory: subdirectory)
        }
    }
}
