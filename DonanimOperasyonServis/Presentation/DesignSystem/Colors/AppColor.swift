import SwiftUI

/// Central color palette for the app.
///
/// All UI code must read colors from this namespace. Do not hard-code
/// hex or named colors in views. Adjustments here propagate everywhere.
///
/// Colors are exposed as `@MainActor` computed properties because
/// `Color.dynamic(light:dark:)` bridges through `UIColor`, which is main-
/// actor bound.
@MainActor
enum AppColor {

    // MARK: - Brand

    /// Deep navy used for primary actions, key surfaces, and iconography.
    static let brandPrimary: Color = .dynamic(
        light: Color(hex: 0x11365C),
        dark: Color(hex: 0x3D6DA1)
    )

    /// Soft brand-tinted surface used behind grouped content.
    static let brandSurface: Color = .dynamic(
        light: Color(hex: 0xF5F7FA),
        dark: Color(hex: 0x1B2434)
    )

    // MARK: - Neutral

    /// Full-screen background.
    static let neutralBackground: Color = .dynamic(
        light: Color(hex: 0xFFFFFF),
        dark: Color(hex: 0x0F1420)
    )

    /// Elevated card surface, one step above `neutralBackground`.
    static let elevatedSurface: Color = .dynamic(
        light: Color(hex: 0xFFFFFF),
        dark: Color(hex: 0x1B2434)
    )

    /// Text/icon color to place on top of `brandPrimary`.
    static let onPrimary: Color = Color(hex: 0xFFFFFF)

    /// Primary text color.
    static let primaryText: Color = .dynamic(
        light: Color(hex: 0x1A1F36),
        dark: Color(hex: 0xF2F4F8)
    )

    /// Secondary/subdued text color.
    static let secondaryText: Color = .dynamic(
        light: Color(hex: 0x5A6478),
        dark: Color(hex: 0xA6B0C2)
    )

    /// 1-pt dividers and hairlines.
    static let divider: Color = .dynamic(
        light: Color(hex: 0xE5E8EE),
        dark: Color(hex: 0x2A344A)
    )

    // MARK: - Semantic

    static let success: Color = .dynamic(
        light: Color(hex: 0x1B8E4B),
        dark: Color(hex: 0x2FBF6B)
    )

    static let warning: Color = .dynamic(
        light: Color(hex: 0xD97706),
        dark: Color(hex: 0xF59E0B)
    )

    static let danger: Color = .dynamic(
        light: Color(hex: 0xDC2626),
        dark: Color(hex: 0xEF4444)
    )

    static let info: Color = .dynamic(
        light: Color(hex: 0x2563EB),
        dark: Color(hex: 0x60A5FA)
    )

    // MARK: - Status (visual proxy; real state machine lives in Domain later)

    static let statusAssigned: Color = .dynamic(
        light: Color(hex: 0x6B7280),
        dark: Color(hex: 0x9CA3AF)
    )

    static let statusAccepted: Color = .dynamic(
        light: Color(hex: 0x2563EB),
        dark: Color(hex: 0x60A5FA)
    )

    static let statusEnRoute: Color = .dynamic(
        light: Color(hex: 0x7C3AED),
        dark: Color(hex: 0xA78BFA)
    )

    static let statusArrived: Color = .dynamic(
        light: Color(hex: 0x0D9488),
        dark: Color(hex: 0x2DD4BF)
    )

    static let statusInProgress: Color = .dynamic(
        light: Color(hex: 0xD97706),
        dark: Color(hex: 0xF59E0B)
    )

    static let statusPaused: Color = .dynamic(
        light: Color(hex: 0xCA8A04),
        dark: Color(hex: 0xEAB308)
    )

    static let statusCompleted: Color = .dynamic(
        light: Color(hex: 0x1B8E4B),
        dark: Color(hex: 0x2FBF6B)
    )

    // MARK: - Priority

    static let priorityNormal: Color = .dynamic(
        light: Color(hex: 0x5A6478),
        dark: Color(hex: 0xA6B0C2)
    )

    static let priorityHigh: Color = .dynamic(
        light: Color(hex: 0xD97706),
        dark: Color(hex: 0xF59E0B)
    )

    static let priorityUrgent: Color = .dynamic(
        light: Color(hex: 0xDC2626),
        dark: Color(hex: 0xEF4444)
    )
}
