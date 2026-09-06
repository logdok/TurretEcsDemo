import AegisECS

/// Damage dealt to the core when an entity gets within `triggerRadius`. The
/// carrier is CONSUMED on delivery — this models a kamikaze detonation: both
/// ordinary ground enemies reaching the core (`CoreBreachSystem`) and an
/// uncaught enemy missile (`EnemyMissileFactory`) carry this component and
/// "explode" identically on contact.
///
/// This is exactly what keeps an archetype's missile on/off switch
/// (`EnemyArchetypeConfig.canFireMissiles`) from being a full threat toggle:
/// even an enemy barred from firing missiles at range still carries this
/// component and stays dangerous as a kamikaze up close — the two threats are
/// independent.
package final class ContactPayloadComponentStore: PackedStore {
    private enum Column: Int32 { case damage, triggerRadius }

    init() { super.init(schema: [.float32, .float32]) }

    var damage: UnsafeMutablePointer<Float> { columnF32(Column.damage.rawValue)! }
    var triggerRadius: UnsafeMutablePointer<Float> { columnF32(Column.triggerRadius.rawValue)! }

    @discardableResult
    func assign(_ entity: Entity, contactDamage: Float, radius: Float) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        damage[Int(slot)] = contactDamage
        triggerRadius[Int(slot)] = radius
        return slot
    }
}
