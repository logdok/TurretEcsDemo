import GameSimulation
import SwiftUI

/// Real-time settings surface.
///
/// Population control writes straight into the live simulation: the spawner
/// treats it as a target to converge on, so dragging the slider never
/// restarts anything. Below population sit three more groups applying the
/// same idea to combat/sound — no config file, no restart, no code change:
/// move a slider and the very next shot or spawn already reflects it.
///
/// Visually this is styled to match `AegisECSInspectorUI.InspectorPanelView`
/// (see `DebugPalette`) exactly — same dark card background, same border,
/// same monospaced type and accent color — so the two side docks read as one
/// consistent panel design rather than two different UI styles bolted
/// together.
struct ControlPanelView: View {
    @ObservedObject var viewModel: GameViewModel

    static let presetValues = [20, 50, 500, 2000, 5000, 10000]

    @State private var population: Double
    @State private var isPaused = false
    @State private var turretCount: Double
    @State private var turretDamage: Double
    @State private var turretFireRate: Double
    @State private var soundEnabled = true
    @State private var fireVolume: Double
    @State private var explosionVolume: Double
    @State private var archetypeEnabled: [Bool]
    @State private var archetypeHealth: [Double]
    @State private var archetypeSpeed: [Double]
    @State private var archetypeMissileRate: [Double]
    @State private var expandedSections: Set<String>

    private let archetypes: [EnemyArchetypeConfig]

    init(viewModel: GameViewModel) {
        self.viewModel = viewModel
        let archetypes = viewModel.enemyArchetypes
        self.archetypes = archetypes
        _population = State(initialValue: Double(viewModel.initialPopulation))
        _turretCount = State(initialValue: Double(viewModel.initialTurretCount))
        _turretDamage = State(initialValue: Double(viewModel.initialTurretDamage))
        _turretFireRate = State(initialValue: Double(viewModel.initialTurretFireRate))
        _fireVolume = State(initialValue: Double(viewModel.initialFireVolume))
        _explosionVolume = State(initialValue: Double(viewModel.initialExplosionVolume))
        _archetypeEnabled = State(initialValue: archetypes.map { $0.spawnWeight > 0 })
        _archetypeHealth = State(initialValue: archetypes.map { Double($0.maxHealth) })
        _archetypeSpeed = State(initialValue: archetypes.map { Double($0.moveSpeed) })
        _archetypeMissileRate = State(initialValue: archetypes.map { $0.canFireMissiles ? Double(60.0 / $0.missileFireInterval) : 0 })
        _expandedSections = State(initialValue: Set(["Turret Settings", "Sound"] + archetypes.map { $0.displayName }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    populationCard

                    section("Turret Settings") {
                        labeledSlider("Turrets: \(Int(turretCount))",
                                      effect($turretCount) { viewModel.setTurretCount(Int($0)) },
                                      in: 1...Double(viewModel.maxTurretCount), step: 1)
                        labeledSlider("Turret damage: \(Int(turretDamage))",
                                      effect($turretDamage) { viewModel.setTurretDamage(Float($0)) }, in: 10...200, step: 2)
                        labeledSlider(String(format: "Turret fire rate: %.1f/s", turretFireRate),
                                      effect($turretFireRate) { viewModel.setTurretFireRate(Float($0)) }, in: 2...40, step: 1)
                    }

                    section("Sound", headerExtra: AnyView(
                        Toggle("On", isOn: effect($soundEnabled) { viewModel.setSoundEnabled($0) })
                            .toggleStyle(PanelSwitchToggleStyle())
                    )) {
                        labeledSlider("Fire volume: \(Int(fireVolume))%",
                                      effect($fireVolume) { viewModel.setTurretFireVolume(Float($0)) }, in: 0...100, step: 5)
                        labeledSlider("Explosion volume: \(Int(explosionVolume))%",
                                      effect($explosionVolume) { viewModel.setEnemyExplosionVolume(Float($0)) }, in: 0...100, step: 5)
                    }

                    ForEach(archetypes.indices, id: \.self) { index in
                        let preview = viewModel.archetypePreview(archetypes[index])
                        section(archetypes[index].displayName, headerExtra: AnyView(
                            HStack(spacing: 8) {
                                ArchetypeIcon(meshKind: preview.meshKind, color: preview.color)
                                Toggle("On", isOn: effect($archetypeEnabled[index]) { viewModel.setEnemyEnabled(index, enabled: $0) })
                                    .toggleStyle(PanelSwitchToggleStyle())
                            }
                        )) {
                            labeledSlider("Health: \(Int(archetypeHealth[index]))",
                                          effect($archetypeHealth[index]) { viewModel.setEnemyMaxHealth(index, value: Float($0)) },
                                          in: 5...500, step: 5)
                            labeledSlider(String(format: "Speed: %.1f", archetypeSpeed[index]),
                                          effect($archetypeSpeed[index]) { viewModel.setEnemyMoveSpeed(index, value: Float($0)) },
                                          in: 1...30, step: 0.5)
                            labeledSlider(archetypeMissileRate[index] <= 0 ? "No missiles" : "Missiles: \(Int(archetypeMissileRate[index]))/min",
                                          effect($archetypeMissileRate[index]) { viewModel.setEnemyMissileRate(index, ratePerMinute: Float($0)) },
                                          in: 0...30, step: 1)
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(DebugPalette.panelBackground.opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(DebugPalette.border, lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("TURRET ECS DEMO").font(DebugPalette.monoHeader).foregroundStyle(DebugPalette.accent)
            Spacer()
            Text(Self.appVersion).font(DebugPalette.mono).foregroundStyle(DebugPalette.dim)
        }
        .padding(8)
    }

    /// Read from the running app's own bundle, not retyped here — this can
    /// never drift out of sync with what `project.yml` actually shipped,
    /// unlike a literal string someone forgets to bump alongside a release.
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(marketing) (\(build))"
    }

    /// The population controls are always relevant, so unlike the sections
    /// below they are never collapsed — but they still sit in the same card
    /// chrome as everything else, rather than floating loose above it.
    private var populationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Enemies in arena: \(Int(population))").font(DebugPalette.mono).foregroundStyle(DebugPalette.text)
                PanelSlider(value: effect($population) { viewModel.setPopulation(Int($0)) },
                            range: 0...Double(max(viewModel.maxEnemyCapacity, 1)), step: 20)
            }

            HStack(spacing: 6) {
                ForEach(Self.presetValues.filter { $0 <= viewModel.maxEnemyCapacity }, id: \.self) { preset in
                    Button("\(preset)") {
                        population = Double(preset)
                        viewModel.setPopulation(preset)
                    }
                    .buttonStyle(PanelButtonStyle())
                }
            }

            HStack(spacing: 6) {
                // The label names the ACTION the button performs, not the
                // state it is in: paused, the only thing left to do is resume.
                Toggle(isOn: effect($isPaused) { viewModel.setPaused($0) }) {
                    Text(isPaused ? "Resume" : "Pause")
                }
                .toggleStyle(PanelToggleButtonStyle())
                // Restarting a frozen game and leaving it frozen would look
                // like the button did nothing, so it always resumes. The local
                // mirror has to be cleared too — `viewModel.restart()` clears
                // the simulation's own flag, but this `@State` is a separate
                // copy that drives the label above.
                Button("Restart") {
                    viewModel.restart()
                    isPaused = false
                }
                .buttonStyle(PanelButtonStyle())
            }
        }
        .padding(8)
        .background(DebugPalette.cardBackground.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// A binding that writes the local `@State` copy AND forwards the new
    /// value to the simulation in one step, so a control both refreshes its
    /// own label and applies the change.
    private func effect<T>(_ state: Binding<T>, _ sideEffect: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: { state.wrappedValue }, set: { state.wrappedValue = $0; sideEffect($0) })
    }

    /// Same card look and the same "▾ open / ▸ closed" self-toggling header
    /// as `InspectorPanelView`'s own `card(_:)`.
    @ViewBuilder
    private func section(_ title: String, headerExtra: AnyView? = nil, @ViewBuilder content: () -> some View) -> some View {
        let isExpanded = expandedSections.contains(title)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    if isExpanded { expandedSections.remove(title) } else { expandedSections.insert(title) }
                } label: {
                    Text((isExpanded ? "▾ " : "▸ ") + title)
                        .font(DebugPalette.mono)
                        .foregroundStyle(DebugPalette.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                if let headerExtra { headerExtra }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) { content() }
            }
        }
        .padding(8)
        .background(DebugPalette.cardBackground.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func labeledSlider(_ label: String, _ value: Binding<Double>, in range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(DebugPalette.mono).foregroundStyle(DebugPalette.dim)
            PanelSlider(value: value, range: range, step: step)
        }
    }
}

/// A small 2D stand-in for an archetype's 3D silhouette (box/capsule/wing/…),
/// filled with that archetype's actual rendered color (see
/// `GameViewModel.archetypePreview`) — a legend so a slider section can be
/// matched to what it actually looks like in the arena, where ground
/// archetypes are otherwise hard to tell apart at a glance.
struct ArchetypeIcon: View {
    let meshKind: RenderArchetypeConfig.MeshKind
    let color: Color

    /// A `Capsule()` at a 1:1 aspect ratio is visually indistinguishable from
    /// a `Circle()` — its straight sides shrink to nothing — so a capsule
    /// needs a deliberately non-square frame to actually read as a pill
    /// rather than a sphere.
    private var size: CGSize {
        switch meshKind {
        case .capsule, .missile: CGSize(width: 34, height: 20)
        case .flyingWing: CGSize(width: 32, height: 22)
        default: CGSize(width: 26, height: 26)
        }
    }

    private var shape: AnyShape {
        switch meshKind {
        case .box, .cylinder, .tank:
            AnyShape(RoundedRectangle(cornerRadius: 6))
        case .capsule, .missile:
            AnyShape(Capsule())
        case .sphere:
            AnyShape(Circle())
        case .flyingWing:
            AnyShape(TriangleShape())
        }
    }

    var body: some View {
        shape
            .fill(color)
            .overlay(shape.stroke(DebugPalette.border, lineWidth: 1))
            .frame(width: size.width, height: size.height)
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
