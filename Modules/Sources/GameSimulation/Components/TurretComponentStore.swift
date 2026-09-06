import AegisECS

/// Weapon state of the core's turret. `targetEntity == -1` means idle.
///
/// **Two targeting passes, one barrel:** `interceptTargetEntity` /
/// `interceptRetargetTimer` serve a SECOND, independent target search in
/// `TurretInterceptTargetingSystem` — the one that specifically hunts enemy
/// missiles. When a missile enters `TurretConfig.interceptRange` (well inside
/// the normal `engagementRange`), that system simply OVERWRITES
/// `targetEntity` with the missile. There is only one barrel, so "intercept
/// priority" is implemented not as a second barrel but as the interceptor
/// being allowed to overwrite the same field `TurretFiringSystem` actually
/// reads when it fires — the second targeting pass never touches the firing
/// or hit logic at all, it only decides where the one existing barrel should
/// point this frame.
package final class TurretComponentStore: PackedStore {
    private enum Column: Int32 {
        case yaw, pitch, cooldown, retargetTimer, targetEntity, interceptTargetEntity, interceptRetargetTimer
    }

    init() {
        super.init(schema: [.float32, .float32, .float32, .float32, .int32, .int32, .float32])
    }

    package var yaw: UnsafeMutablePointer<Float> { columnF32(Column.yaw.rawValue)! }
    package var pitch: UnsafeMutablePointer<Float> { columnF32(Column.pitch.rawValue)! }
    var cooldown: UnsafeMutablePointer<Float> { columnF32(Column.cooldown.rawValue)! }
    var retargetTimer: UnsafeMutablePointer<Float> { columnF32(Column.retargetTimer.rawValue)! }
    var targetEntity: UnsafeMutablePointer<Int32> { columnI32(Column.targetEntity.rawValue)! }
    var interceptTargetEntity: UnsafeMutablePointer<Int32> { columnI32(Column.interceptTargetEntity.rawValue)! }
    var interceptRetargetTimer: UnsafeMutablePointer<Float> { columnF32(Column.interceptRetargetTimer.rawValue)! }

    @discardableResult
    func assign(_ entity: Entity) -> Int32 {
        let slot = attach(entity)
        guard slot >= 0 else { return slot }
        yaw[Int(slot)] = 0
        pitch[Int(slot)] = 0
        cooldown[Int(slot)] = 0
        retargetTimer[Int(slot)] = 0
        targetEntity[Int(slot)] = -1
        interceptTargetEntity[Int(slot)] = -1
        interceptRetargetTimer[Int(slot)] = 0
        return slot
    }
}
