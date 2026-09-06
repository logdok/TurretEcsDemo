import AegisECS
import Foundation

/// Composition root of the game layer.
///
/// Reading this file top to bottom tells you the FULL component set and the
/// EXACT execution order of the game. Component stores and systems are
/// registered nowhere else — this is the single assembly point for the game
/// layer (the classic "composition root").
///
/// The renderer is deliberately NOT added here: it belongs to the
/// presentation layer and is appended by the app's composition root, after
/// `build()` returns. That is what keeps the game layer completely free of
/// any dependency on render types — the whole game layer can be driven
/// headless, with no rendering at all.
package enum SimulationBootstrap {
    package static func build(simulationConfig: SimulationConfig, weaponConfig: TurretConfig) -> GameContext {
        let context = GameContext()
        context.initialize(simulationConfig: simulationConfig, weaponConfig: weaponConfig)

        context.world = World(entityCapacity: simulationConfig.computeWorldCapacity())
        context.scheduler = Scheduler()

        registerStores(context, simulationConfig)
        configureBroadphase(context, simulationConfig)
        registerSystems(context)

        // setupAll is deliberately NOT called here. The app's composition root
        // still needs to add the presentation layer's renderer system, and
        // every system must be set up exactly once, only after the whole
        // pipeline is fully assembled. Call `finalize` separately once the
        // presentation layer has finished appending its systems.
        return context
    }

    /// Completes assembly after the presentation layer has added its systems
    /// (the renderer, in particular).
    package static func finalize(_ context: GameContext) {
        _ = context.scheduler.setupAll(world: context.world, context: context)
        TurretFactory.setCount(context, to: Int(context.turretCount))
    }

    private static func registerStores(_ context: GameContext, _ simulationConfig: SimulationConfig) {
        let world = context.world!

        context.transforms = TransformComponentStore()
        context.velocities = VelocityComponentStore()
        context.healths = HealthComponentStore()
        context.locomotions = LocomotionComponentStore()
        context.colliders = ColliderComponentStore()
        context.projectiles = ProjectileComponentStore()
        context.lifetimes = LifetimeComponentStore()
        context.contactPayloads = ContactPayloadComponentStore()
        context.turrets = TurretComponentStore()
        context.hostiles = TagStore()
        context.missileLaunchers = MissileLauncherComponentStore()
        context.interceptables = TagStore()

        world.registerStore(context.transforms, typeID: ComponentType.transform)
        world.registerStore(context.velocities, typeID: ComponentType.velocity)
        world.registerStore(context.healths, typeID: ComponentType.health)
        world.registerStore(context.locomotions, typeID: ComponentType.locomotion)
        world.registerStore(context.colliders, typeID: ComponentType.collider)
        world.registerStore(context.projectiles, typeID: ComponentType.projectile)
        world.registerStore(context.lifetimes, typeID: ComponentType.lifetime)
        world.registerStore(context.contactPayloads, typeID: ComponentType.contactPayload)
        world.registerStore(context.turrets, typeID: ComponentType.turret)
        world.registerStore(context.hostiles, typeID: ComponentType.hostileTag)
        world.registerStore(context.missileLaunchers, typeID: ComponentType.missileLauncher)
        world.registerStore(context.interceptables, typeID: ComponentType.interceptableTag)

        // One tag-like store per visual archetype. This is exactly what turns
        // the render pass into a filter-free walk — see RenderBatchComponentStore.
        for renderConfig in simulationConfig.resolveRenderArchetypes() {
            let archetypeId = renderConfig.archetypeId
            guard archetypeId >= 0 && Int(archetypeId) < context.renderBatches.count else {
                print("Warning: render archetype id \(archetypeId) is outside RenderArchetypeId range")
                continue
            }
            let batch = RenderBatchComponentStore()
            batch.archetypeId = archetypeId
            world.registerStore(batch, typeID: ComponentType.renderBatchBase + archetypeId)
            context.renderBatches[Int(archetypeId)] = batch
            context.renderArchetypeConfigs[Int(archetypeId)] = renderConfig
        }
    }

    private static func configureBroadphase(_ context: GameContext, _ simulationConfig: SimulationConfig) {
        // Flat mode is passed to the grid as a zero vertical extent — that is
        // its normal API, not a trick. `verticalExtent` itself is NOT zeroed:
        // RenderBatchRegistry also reads it for `customAABB`.
        let gridVerticalExtent: Float = simulationConfig.flatSpatialGrid ? 0 : simulationConfig.verticalExtent

        context.spatialGrid = UniformSpatialGrid()
        context.spatialGrid.configure(
            arenaRadius: simulationConfig.arenaRadius,
            verticalExtent: gridVerticalExtent,
            cellSize: simulationConfig.spatialCellSize,
            entryCapacity: Int(simulationConfig.computeWorldCapacity()))

        // The missile grid has its OWN, much larger cell size: its population
        // is two orders of magnitude smaller, and small cells there would mean
        // almost all rebuild time goes into iterating emptiness. See
        // `SimulationConfig.missileSpatialCellSize`.
        context.missileSpatialGrid = UniformSpatialGrid()
        context.missileSpatialGrid.configure(
            arenaRadius: simulationConfig.arenaRadius,
            verticalExtent: gridVerticalExtent,
            cellSize: simulationConfig.missileSpatialCellSize,
            entryCapacity: Int(simulationConfig.maxMissileCapacity))
    }

    /// EXECUTION ORDER IS A BEHAVIOURAL CONTRACT OF THE GAME. Reordering these
    /// lines changes the simulation; treat this list as code, not
    /// configuration. Briefly, why this exact order:
    ///   1-2  enemy spawn/missiles first — new entities this frame must still
    ///        make it into the index rebuilds below;
    ///   3-4  broadphase indices are built BEFORE targeting — targeting and
    ///        hit-testing read them, so the index must already be current;
    ///   5-6  ordinary targeting first, then missile-intercept priority on
    ///        top of it (see TurretComponentStore/TurretInterceptTargetingSystem);
    ///   7    firing — against the finally-chosen target;
    ///   8-9  movement (intent -> velocity -> position) — projectiles and
    ///        enemies move to this frame's new position;
    ///   10-11 projectile hits and core breach are checked against the NEW
    ///        positions;
    ///   12   damage is applied centrally, after every damage source this
    ///        frame has already reported in;
    ///   13   lifetime expiry — after a projectile has had its chance to hit;
    ///   14   destruction — strictly the last game system, the single real
    ///        entity-removal point (`ReaperSystem`);
    ///   15   rendering (added by the app) — reads an already fully
    ///        consistent frame state.
    private static func registerSystems(_ context: GameContext) {
        let scheduler = context.scheduler!
        scheduler.addSystem(EnemySpawnSystem())                 // 1
        scheduler.addSystem(EnemyMissileFiringSystem())         // 2
        scheduler.addSystem(SpatialIndexSystem())                // 3
        scheduler.addSystem(MissileSpatialIndexSystem())         // 4
        scheduler.addSystem(TurretTargetingSystem())             // 5
        scheduler.addSystem(TurretInterceptTargetingSystem())    // 6
        scheduler.addSystem(TurretFiringSystem())                // 7
        scheduler.addSystem(EnemySteeringSystem())               // 8
        scheduler.addSystem(MotionIntegrationSystem())           // 9
        scheduler.addSystem(ProjectileImpactSystem())            // 10
        scheduler.addSystem(CoreBreachSystem())                  // 11
        scheduler.addSystem(DamageResolutionSystem())            // 12
        scheduler.addSystem(LifetimeExpirySystem())              // 13
        scheduler.addSystem(ReaperSystem(world: context.world))  // 14
        // 15 - the instanced renderer is added by the app's composition root.
    }

    /// Clears every entity and restores runtime counters, reusing every
    /// memory allocation (see `World.reset()` — not a single new allocation).
    package static func restart(_ context: GameContext) {
        context.world.reset()
        context.resetRuntimeState()
        TurretFactory.setCount(context, to: Int(context.turretCount))
    }
}
