import Foundation

/// Small seedable PRNG (SplitMix64). A reference type on purpose:
/// `GameContext.rng` is shared and mutated by many call sites.
///
/// Determinism here means "the same seed reproduces the same run within this
/// app" — the exact bit sequence is a contract with nothing else, which is all
/// `SimulationConfig.randomSeed` needs it to be.
package final class SeededRNG {
    private var state: UInt64

    package init(seed: Int64) {
        let s = UInt64(bitPattern: seed)
        state = s == 0 ? 0x9E3779B97F4A7C15 : s
    }

    @discardableResult
    private func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform float in `[0, 1)`.
    package func randf() -> Float {
        Float(nextUInt64() >> 40) * (1.0 / Float(1 << 24))
    }

    /// Uniform float in `[from, to]`.
    package func randfRange(_ from: Float, _ to: Float) -> Float {
        from + randf() * (to - from)
    }

    /// Uniform non-negative integer.
    package func randi() -> UInt32 {
        UInt32(truncatingIfNeeded: nextUInt64())
    }
}
