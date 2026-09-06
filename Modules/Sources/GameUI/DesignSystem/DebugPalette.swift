import SwiftUI

/// Colors and type matching `AegisECSInspectorUI.InspectorPanelView`'s own
/// look, hex-for-hex, so the settings panel and the ECS inspector panel read
/// as one consistent design instead of two different UI styles side by side.
///
/// This can't just import the inspector's palette — those constants are
/// `internal` to the AegisECSInspectorUI module, invisible outside it — so
/// this is a deliberate parallel definition, kept in sync by eye against
/// that package's `InspectorPanelView.swift`.
enum DebugPalette {
    static let text = Color(hex: 0xd6dae0)
    static let dim = Color(hex: 0x7a828c)
    static let accent = Color(hex: 0x8ab4f8)
    static let good = Color(hex: 0x7fd18c)
    static let warn = Color(hex: 0xe5c07b)
    static let bad = Color(hex: 0xe08b7b)

    static let panelBackground = Color(hex: 0x0f1017)
    static let cardBackground = Color(hex: 0x1a1c24)
    static let border = Color(hex: 0x33373f)
    static let controlBackground = Color(hex: 0x1b1e26)

    static let mono = Font.system(size: 12, design: .monospaced)
    static let monoHeader = Font.system(size: 12, weight: .semibold, design: .monospaced)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}
