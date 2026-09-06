import SwiftUI

/// The settings panel's own controls, drawn entirely from `DebugPalette`.
///
/// They exist because the NATIVE ones cannot be made to match. `Slider` always
/// draws a pure-white thumb and `Toggle(.switch)` a white knob on a saturated
/// capsule; neither colour is reachable through any public modifier — `.tint`
/// only reaches the filled track. That white was the single loudest thing in
/// the panel and the only real reason it read as a different design from the
/// inspector dock beside it, whose backgrounds are already identical to this
/// panel's hex for hex.
///
/// So: flat rectangles, one accent, dark handles, 1px borders — the same
/// vocabulary the inspector uses for its own chrome.

/// Replaces `Slider`. Same `value`/`range`/`step` contract, including
/// quantisation, so call sites read the same as before.
struct PanelSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    private let trackHeight: CGFloat = 8
    private let knobWidth: CGFloat = 12
    private let knobHeight: CGFloat = 18
    private let radius: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            // The knob travels between the track's ends rather than past them,
            // so `usable` is the width minus one knob — otherwise the handle
            // would hang half-off the track at both extremes.
            let usable = max(proxy.size.width - knobWidth, 1)
            let span = max(range.upperBound - range.lowerBound, 0.000_001)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let knobX = usable * fraction

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius)
                    .fill(DebugPalette.controlBackground)
                    .overlay(RoundedRectangle(cornerRadius: radius).stroke(DebugPalette.border, lineWidth: 1))
                    .frame(height: trackHeight)

                RoundedRectangle(cornerRadius: radius)
                    .fill(DebugPalette.accent)
                    .frame(width: knobX + knobWidth * 0.5, height: trackHeight)

                // Dark handle with a light outline, not a light handle: the
                // accent fill ending underneath it is what makes it readable.
                RoundedRectangle(cornerRadius: radius)
                    .fill(DebugPalette.border)
                    .overlay(RoundedRectangle(cornerRadius: radius).stroke(DebugPalette.dim, lineWidth: 1))
                    .frame(width: knobWidth, height: knobHeight)
                    .offset(x: knobX)
            }
            .frame(height: knobHeight)
            // `minimumDistance: 0` so a tap anywhere on the track jumps to that
            // value, matching what `Slider` does.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { gesture in
                    let f = min(max((gesture.location.x - knobWidth * 0.5) / usable, 0), 1)
                    let quantised = quantise(range.lowerBound + f * span)
                    if quantised != value { value = quantised }
                }
            )
        }
        .frame(height: knobHeight)
    }

    private func quantise(_ raw: Double) -> Double {
        guard step > 0 else { return min(max(raw, range.lowerBound), range.upperBound) }
        let steps = ((raw - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }
}

/// Replaces `.toggleStyle(.switch)`. Reads as a switch — a handle that slides
/// to the side it is on — without iOS's white-on-blue capsule.
struct PanelSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(DebugPalette.controlBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(configuration.isOn ? DebugPalette.accent : DebugPalette.border, lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 2)
                    .fill(configuration.isOn ? DebugPalette.accent : DebugPalette.dim)
                    .frame(width: 15, height: 13)
                    .padding(.horizontal, 3)
            }
            .frame(width: 38, height: 20)
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

/// Flat, dark, monospaced button — matches the inspector panel's own small
/// "log" button instead of SwiftUI's default capsule-shaped bordered style.
struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DebugPalette.mono)
            .foregroundStyle(DebugPalette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(DebugPalette.controlBackground.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Same flat look as `PanelButtonStyle`, but stays highlighted while toggled
/// on — used for "Pause"/"Resume", which is a toggle, not a momentary action.
struct PanelToggleButtonStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(DebugPalette.mono)
                .foregroundStyle(configuration.isOn ? DebugPalette.accent : DebugPalette.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(DebugPalette.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(configuration.isOn ? DebugPalette.accent : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
