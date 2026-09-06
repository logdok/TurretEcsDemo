import AegisECSInspectorUI
import GameRuntime
import SwiftUI
import UIKit

/// Root view: the Metal viewport, the core-health readout on top, and two
/// slide-over HUD docks (settings on the left, ECS inspector on the right).
///
/// The tab of each dock is a SIBLING of its panel inside one `HStack`, and
/// that single `HStack` carries the one `.offset` both of them ride. That is
/// what makes the two things impossible to desync: there is only one animated
/// value, and the tab never overlaps the panel's own content because it never
/// shares a position with it — it sits beside the panel, attached to its outer
/// edge, and slides as the same rigid unit. Closed, the offset exactly cancels
/// the panel's width, so only the tab peeks out at the screen edge; open, the
/// panel sits flush against the edge with the tab now attached to its inner
/// edge like a handle.
///
/// One of the two `public` symbols in this package: the app shell builds a
/// `GameSession` and hands it here, and that is the entire contract between
/// shell and app.
public struct GameScreen: View {
    @StateObject private var viewModel: GameViewModel
    private let session: GameSession

    @State private var settingsOpen = false
    @State private var inspectorOpen = false

    private let tabSize: CGFloat = 44

    public init(session: GameSession) {
        self.session = session
        _viewModel = StateObject(wrappedValue: GameViewModel(session: session))
    }

    public var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(430, proxy.size.width * 0.66)

            ZStack {
                MetalView(session: session)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    DefeatBanner(viewModel: viewModel)
                        .padding(.top, 14)
                    TurretHealthRow(viewModel: viewModel)
                    Spacer()
                }

                settingsDock(height: proxy.size.height, panelWidth: panelWidth)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)

                inspectorDock(height: proxy.size.height, panelWidth: panelWidth)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private func settingsDock(height: CGFloat, panelWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ControlPanelView(viewModel: viewModel)
                .frame(width: panelWidth, height: height)
            dockTab(systemImage: "slider.horizontal.3", corners: [.topRight, .bottomRight]) {
                settingsOpen.toggle()
            }
            .padding(.top, 14)
        }
        .offset(x: settingsOpen ? 0 : -panelWidth)
        .animation(.easeOut(duration: 0.22), value: settingsOpen)
    }

    private func inspectorDock(height: CGFloat, panelWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            dockTab(systemImage: "chart.bar", corners: [.topLeft, .bottomLeft]) {
                inspectorOpen.toggle()
            }
            .padding(.top, 14)
            InspectorPanelView(inspector: session.inspector, isActive: inspectorOpen)
                .frame(width: panelWidth, height: height)
        }
        .offset(x: inspectorOpen ? 0 : panelWidth)
        .animation(.easeOut(duration: 0.22), value: inspectorOpen)
    }

    /// Square on the side that touches its panel, rounded on the outward
    /// side — reads as a handle attached to the panel, not a free-floating button.
    private func dockTab(systemImage: String, corners: UIRectCorner, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.541, green: 0.706, blue: 0.973))
                .frame(width: tabSize, height: tabSize)
                .background(Color(red: 0.10, green: 0.12, blue: 0.15).opacity(0.92))
                .clipShape(RoundedCorner(radius: 10, corners: corners))
                .overlay(
                    RoundedCorner(radius: 10, corners: corners)
                        .stroke(Color(red: 0.34, green: 0.40, blue: 0.48), lineWidth: 1)
                )
        }
    }
}

/// A rectangle rounded only on the given corners.
private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
