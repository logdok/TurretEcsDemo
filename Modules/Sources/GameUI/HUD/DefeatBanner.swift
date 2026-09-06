import SwiftUI

/// Shown only once every turret is gone — the actual end of the game (see
/// `GameContext.areAllTurretsDestroyed`). Silent the rest of the time: with
/// `TurretHealthRow` already showing exactly how close to that state the
/// battle is, a bar that sat unchanged for nearly the whole game until this
/// moment (the old `CoreHealthHudView`, built around an abstract core-health
/// pool the simulation no longer has) would have been dead weight everywhere
/// but here.
struct DefeatBanner: View {
    @ObservedObject var viewModel: GameViewModel

    var body: some View {
        if viewModel.isDefeated {
            Text("ALL TURRETS DESTROYED")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.42, green: 0.10, blue: 0.10).opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
        }
    }
}
