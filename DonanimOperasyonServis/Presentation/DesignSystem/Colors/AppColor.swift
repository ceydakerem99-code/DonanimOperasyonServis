import SwiftUI

/// Central color palette for the app.
///
/// All UI code must read colors from this namespace. Do not hard-code
/// hex or named colors in views. Adjustments here propagate everywhere.
///
/// Colors are **not** `@MainActor`. SwiftUI may resolve them on
/// `AsyncRenderer`; MainActor-isolated dynamic providers previously
/// crashed with `_dispatch_assert_queue_fail` when switching tabs.
enum AppColor {

    // MARK: - Brand

    /// Deep navy used for primary actions, key surfaces, and iconography.
    static let brandPrimary: Color = .dynamic(
        lightHex: 0x11365C,
        darkHex: 0x3D6DA1
    )

    /// Soft brand-tinted surface used behind grouped content.
    static let brandSurface: Color = .dynamic(
        lightHex: 0xF5F7FA,
        darkHex: 0x1B2434
    )

    // MARK: - Neutral

    /// Full-screen background.
    static let neutralBackground: Color = .dynamic(
        lightHex: 0xFFFFFF,
        darkHex: 0x0F1420
    )

    /// Elevated card surface, one step above `neutralBackground`.
    static let elevatedSurface: Color = .dynamic(
        lightHex: 0xFFFFFF,
        darkHex: 0x1B2434
    )

    /// Text/icon color to place on top of `brandPrimary`.
    static let onPrimary: Color = Color(hex: 0xFFFFFF)

    /// Primary text color.
    static let primaryText: Color = .dynamic(
        lightHex: 0x1A1F36,
        darkHex: 0xF2F4F8
    )

    /// Secondary/subdued text color.
    static let secondaryText: Color = .dynamic(
        lightHex: 0x5A6478,
        darkHex: 0xA6B0C2
    )

    /// 1-pt dividers and hairlines.
    static let divider: Color = .dynamic(
        lightHex: 0xE5E8EE,
        darkHex: 0x2A344A
    )

    // MARK: - Semantic

    static let success: Color = .dynamic(
        lightHex: 0x1B8E4B,
        darkHex: 0x2FBF6B
    )

    static let warning: Color = .dynamic(
        lightHex: 0xD97706,
        darkHex: 0xF59E0B
    )

    static let danger: Color = .dynamic(
        lightHex: 0xDC2626,
        darkHex: 0xEF4444
    )

    static let info: Color = .dynamic(
        lightHex: 0x2563EB,
        darkHex: 0x60A5FA
    )

    // MARK: - Status (visual proxy; real state machine lives in Domain later)

    static let statusAssigned: Color = .dynamic(
        lightHex: 0x6B7280,
        darkHex: 0x9CA3AF
    )

    static let statusAccepted: Color = .dynamic(
        lightHex: 0x2563EB,
        darkHex: 0x60A5FA
    )

    static let statusEnRoute: Color = .dynamic(
        lightHex: 0x7C3AED,
        darkHex: 0xA78BFA
    )

    static let statusArrived: Color = .dynamic(
        lightHex: 0x0D9488,
        darkHex: 0x2DD4BF
    )

    static let statusInProgress: Color = .dynamic(
        lightHex: 0xD97706,
        darkHex: 0xF59E0B
    )

    static let statusPaused: Color = .dynamic(
        lightHex: 0xCA8A04,
        darkHex: 0xEAB308
    )

    static let statusCompleted: Color = .dynamic(
        lightHex: 0x1B8E4B,
        darkHex: 0x2FBF6B
    )

    // MARK: - Priority

    static let priorityNormal: Color = .dynamic(
        lightHex: 0x5A6478,
        darkHex: 0xA6B0C2
    )

    static let priorityHigh: Color = .dynamic(
        lightHex: 0xD97706,
        darkHex: 0xF59E0B
    )

    static let priorityUrgent: Color = .dynamic(
        lightHex: 0xDC2626,
        darkHex: 0xEF4444
    )
}
