import AegisECS

/// Steering parameters for hostile entities.
///
/// Altitude is a two-phase profile: an entity holds `cruiseAltitude` until it
/// enters `descentRadius` around the core, then converges on `strikeAltitude`
/// — this lets flying enemies (drones) dive onto the target instead of flying
/// flat along the ground. Ground units simply set the same value for both
/// altitudes and a zero descent radius, so the descent phase produces no
/// visible height change and one shared movement code path serves both air
/// and ground archetypes with no `isFlying` branch anywhere.
package final class LocomotionComponentStore: PackedStore {
    private enum Column: Int32 { case moveSpeed, turnRate, cruiseAltitude, strikeAltitude, descentRadius }

    init() { super.init(schema: [.float32, .float32, .float32, .float32, .float32]) }

    var moveSpeed: UnsafeMutablePointer<Float> { columnF32(Column.moveSpeed.rawValue)! }
    var turnRate: UnsafeMutablePointer<Float> { columnF32(Column.turnRate.rawValue)! }
    var cruiseAltitude: UnsafeMutablePointer<Float> { columnF32(Column.cruiseAltitude.rawValue)! }
    var strikeAltitude: UnsafeMutablePointer<Float> { columnF32(Column.strikeAltitude.rawValue)! }
    var descentRadius: UnsafeMutablePointer<Float> { columnF32(Column.descentRadius.rawValue)! }

    @discardableResult
    func assign(_ entity: Entity, speed: Float, turn: Float, cruise: Float, strike: Float, descent: Float) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        moveSpeed[Int(slot)] = speed
        turnRate[Int(slot)] = turn
        cruiseAltitude[Int(slot)] = cruise
        strikeAltitude[Int(slot)] = strike
        descentRadius[Int(slot)] = descent
        return slot
    }
}
