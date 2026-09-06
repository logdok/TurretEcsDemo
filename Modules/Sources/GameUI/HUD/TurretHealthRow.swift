import SwiftUI

/// One small health badge per turret, directly under `DefeatBanner` — the
/// primary readout of how the battle is going, now that turrets themselves
/// are what gets worn down and destroyed (see
/// `GameContext.areAllTurretsDestroyed`).
///
/// The row's length tracks `viewModel.turretHealthReadouts` exactly: adding a
/// turret in the settings panel adds a badge here. A turret destroyed in
/// battle does NOT remove its badge — it stays, pinned at "0 / max" and red —
/// since the wreck itself stays on the battlefield too (see
/// `TurretPresenter`); the row is a live count of exactly how many defenders
/// are left standing, not a setting to keep in sync.
struct TurretHealthRow: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        if !viewModel.turretHealthReadouts.isEmpty {
            HStack(spacing: 6) {
                ForEach(viewModel.turretHealthReadouts) { readout in
                    TurretHealthBadge(readout: readout)
                }
            }
            .padding(8)
            .background(Color(red: 0.06, green: 0.07, blue: 0.09).opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)
        }
    }
}

private struct TurretHealthBadge: View {
    let readout: GameViewModel.TurretHealthReadout

    /// Same green/amber/red thresholds this whole HUD uses everywhere else —
    /// one glance should read a turret's danger the same way as any other
    /// bar in the game, not a second color language to learn.
    private var barColor: Color {
        if readout.ratio > 0.5 { return Color(red: 0.35, green: 0.85, blue: 0.45) }
        if readout.ratio > 0.2 { return Color(red: 0.95, green: 0.75, blue: 0.25) }
        return Color(red: 0.92, green: 0.25, blue: 0.25)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(readout.text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            ProgressView(value: readout.ratio)
                .tint(barColor)
                .frame(width: 56, height: 6)
        }
    }
}
