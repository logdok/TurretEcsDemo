import GameSimulation
import Metal

/// Owns every instanced pool, addressed by `RenderArchetypeId`.
package final class RenderBatchRegistry {
    package init() {}

    package private(set) var pools: [InstancePool?] = []

    package func build(device: MTLDevice, simulationConfig: SimulationConfig) {
        pools = [InstancePool?](repeating: nil, count: Int(RenderArchetypeId.count))
        for renderConfig in simulationConfig.resolveRenderArchetypes() {
            let archetypeId = Int(renderConfig.archetypeId)
            guard archetypeId >= 0 && archetypeId < pools.count else { continue }
            let capacity = Int(simulationConfig.resolveBatchCapacity(renderConfig))
            pools[archetypeId] = InstancePool(device: device, config: renderConfig, capacity: capacity)
        }
    }

    package func pool(_ archetypeId: Int32) -> InstancePool? {
        guard archetypeId >= 0 && Int(archetypeId) < pools.count else { return nil }
        return pools[Int(archetypeId)]
    }

    package func drawCallCount() -> Int {
        pools.reduce(0) { $0 + (($1?.visibleCount ?? 0) > 0 ? 1 : 0) }
    }
}
