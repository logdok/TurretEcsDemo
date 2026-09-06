import AegisECS
import Foundation
import GameCore

/// Root configuration for the whole simulation.
///
/// The archetype arrays may be left empty — then code-side defaults are used
/// (see `resolveEnemyArchetypes`/`resolveRenderArchetypes`), so the app runs
/// out of the box with no configuration step.
package final class SimulationConfig {
    // MARK: Population
    /// How many live enemies the spawner tries to maintain. This is the value
    /// the population slider drives, applied continuously frame over frame —
    /// never through a scene rebuild.
    package var targetPopulation: Int32 = 20
    /// Hard ceiling on the hostile pool. Also sizes the instanced-render batches.
    package var maxEnemyCapacity: Int32 = 10_000
    package var maxProjectileCapacity: Int32 = 512
    /// Hard ceiling on simultaneously flying enemy missiles. Not just a pool
    /// size but a GAMEPLAY LEVER: the turret has one barrel, so this is what
    /// stops a large enemy population from producing an aggregate missile
    /// volume no single turret could ever intercept.
    package var maxMissileCapacity: Int32 = 32
    /// Per-frame spawn/cull budgets that keep a slider change from spiking
    /// creation/destruction in a single frame.
    package var maxSpawnsPerFrame: Int32 = 96
    package var maxCullsPerFrame: Int32 = 192

    // MARK: Arena
    package var spawnRadius: Float = 90.0
    package var arenaRadius: Float = 130.0
    package var verticalExtent: Float = 24.0

    /// Build broadphase grids in FLAT (2D) mode. Y is ignored when bucketing
    /// into cells, but distance checks stay fully 3D, so query results never
    /// change — only the rebuild cost does (`O(entries + CELLS)`, and flat
    /// mode drops the vertical multiplier). This is correct as long as the
    /// arena is essentially flat; if entities ever spread as widely in height
    /// as horizontally, turn this off.
    package var flatSpatialGrid: Bool = true
    /// Enemy broadphase cell size. Rule of thumb: 2-4x the largest collider.
    package var spatialCellSize: Float = 6.0
    /// Missile broadphase cell size — deliberately much larger than
    /// `spatialCellSize`. The rebuild cost is `O(entries + CELLS)`, paid every
    /// frame; the missile grid holds at most `maxMissileCapacity` (32)
    /// entries, so selectivity is worthless there and empty cells are pure
    /// loss. Cell size never affects query results, only speed.
    ///
    /// 64, not an eyeballed number: `UniformSpatialGrid.suggestCellSize(
    /// arenaRadius: 130, verticalExtent: 0, expectedEntries: 32,
    /// typicalQueryRadius: TurretConfig.interceptRange)` — the widest single
    /// query this grid ever answers is a turret's own intercept-range search,
    /// and the library's own floor of `2 * typicalQueryRadius` wins out over
    /// the density term at this population. In-app diagnostics measured the
    /// old value of 40 producing 64 cells for as little as 1 live missile;
    /// 64 collapses that to roughly 36.
    package var missileSpatialCellSize: Float = 64.0

    // MARK: Core
    /// Where the turret ring centres on and where the arena's spawn ring is
    /// measured from. The core has no health of its own — see
    /// `GameContext.areAllTurretsDestroyed` — it is a location, not a target.
    package var corePosition: SIMDVector3 = .zero

    // MARK: Content
    package var enemyArchetypes: [EnemyArchetypeConfig] = []
    package var renderArchetypes: [RenderArchetypeConfig] = []

    // MARK: Determinism
    package var randomSeed: Int64 = 20_260_822

    /// Extra entity slots beyond enemies and projectiles (turret, future props).
    package static let reservedEntitySlots: Int32 = 64

    package init() {}

    package func resolveEnemyArchetypes() -> [EnemyArchetypeConfig] {
        enemyArchetypes.isEmpty ? EnemyArchetypeConfig.createDefaultRoster() : enemyArchetypes
    }

    package func resolveRenderArchetypes() -> [RenderArchetypeConfig] {
        renderArchetypes.isEmpty ? RenderArchetypeConfig.createDefaultSet() : renderArchetypes
    }

    /// Total entity slot count the world must preallocate up front.
    package func computeWorldCapacity() -> Int32 {
        maxEnemyCapacity + maxProjectileCapacity + maxMissileCapacity + SimulationConfig.reservedEntitySlots
    }

    /// Instance capacity for one render batch, honouring a per-archetype
    /// override when set.
    package func resolveBatchCapacity(_ config: RenderArchetypeConfig) -> Int32 {
        if config.capacity > 0 { return config.capacity }
        if config.archetypeId == RenderArchetypeId.projectile { return maxProjectileCapacity }
        if config.archetypeId == RenderArchetypeId.missile { return maxMissileCapacity }
        return maxEnemyCapacity
    }

    package static func createDefault() -> SimulationConfig { SimulationConfig() }
}
