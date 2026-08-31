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

    /// Primary corporate blue — actions, active navigation, key accents.
    static let brandPrimary: Color = .dynamic(
        lightHex: 0x1557B0,
        darkHex: 0x4A8FD4
    )

    /// Alias for primary brand actions.
    static var primary: Color { brandPrimary }

    /// Soft brand-tinted page background behind grouped content.
    static let brandSurface: Color = .dynamic(
        lightHex: 0xF5F7FA,
        darkHex: 0x1B2434
    )

    /// Light blue wash used for primary-tinted card surfaces.
    static let brandLightSurface: Color = .dynamic(
        lightHex: 0xEEF5FF,
        darkHex: 0x1A2840
    )

    // MARK: - Neutral

    static let neutralBackground: Color = .dynamic(
        lightHex: 0xFFFFFF,
        darkHex: 0x0F1420
    )

    static let elevatedSurface: Color = .dynamic(
        lightHex: 0xFFFFFF,
        darkHex: 0x1B2434
    )

    static let onPrimary: Color = Color(hex: 0xFFFFFF)

    static let primaryText: Color = .dynamic(
        lightHex: 0x1A1F36,
        darkHex: 0xF2F4F8
    )

    static let secondaryText: Color = .dynamic(
        lightHex: 0x5A6478,
        darkHex: 0xA6B0C2
    )

    static let divider: Color = .dynamic(
        lightHex: 0xE5E8EE,
        darkHex: 0x2A344A
    )

    // MARK: - Semantic (operational roles)

    static let statusUrgent: Color = .dynamic(
        lightHex: 0xE53935,
        darkHex: 0xEF5350
    )

    static let statusOverdue: Color = .dynamic(
        lightHex: 0xF8C800,
        darkHex: 0xFFD54F
    )

    static let statusPaused: Color = .dynamic(
        lightHex: 0xF6B300,
        darkHex: 0xFFCA28
    )

    static let statusAvailable: Color = .dynamic(
        lightHex: 0x2CC55E,
        darkHex: 0x4CD97B
    )

    static let statusBusy: Color = .dynamic(
        lightHex: 0x0D1B3D,
        darkHex: 0x7BA3D4
    )

    static let statusCompleted: Color = statusAvailable

    static let statusError: Color = statusUrgent

    static let statusOpen: Color = brandPrimary

    // MARK: - Priority accents (badges + work-order card left stripe)

    static let priorityNormalAccent: Color = brandPrimary

    static let priorityHighAccent: Color = .dynamic(
        lightHex: 0xF57C00,
        darkHex: 0xFFB74D
    )

    static let priorityUrgentAccent: Color = statusUrgent

    // MARK: - Time status accents (badges only — not card stripe)

    static let timeToday: Color = brandPrimary

    static let timeApproaching: Color = .dynamic(
        lightHex: 0xF6B300,
        darkHex: 0xFFCA28
    )

    static let timeDelayed: Color = .dynamic(
        lightHex: 0xF57C00,
        darkHex: 0xFFB74D
    )

    static let timeWindowPassed: Color = statusUrgent

    static let timeScheduled: Color = statusAssigned

    // MARK: - Semantic (general aliases)

    static let success: Color = statusAvailable

    static let warning: Color = statusPaused

    static let danger: Color = statusUrgent

    static let info: Color = brandPrimary

    // MARK: - Semantic card surfaces (pastel)

    static let semanticPrimarySurface: Color = brandLightSurface

    static let semanticUrgentSurface: Color = .dynamic(
        lightHex: 0xFFEBEE,
        darkHex: 0x3A1C1C
    )

    static let semanticOverdueSurface: Color = .dynamic(
        lightHex: 0xFFFBE6,
        darkHex: 0x3A3210
    )

    static let semanticPausedSurface: Color = .dynamic(
        lightHex: 0xFFF8E6,
        darkHex: 0x3A2E10
    )

    static let semanticAvailableSurface: Color = .dynamic(
        lightHex: 0xEAF9F0,
        darkHex: 0x143322
    )

    static let semanticBusySurface: Color = .dynamic(
        lightHex: 0xE8EDF5,
        darkHex: 0x121E33
    )

    static let semanticCompletedSurface: Color = semanticAvailableSurface

    static let semanticErrorSurface: Color = semanticUrgentSurface

    static let semanticNeutralSurface: Color = elevatedSurface

    // MARK: - Workflow status (distinct from priority / time status)

    static let statusAssigned: Color = .dynamic(
        lightHex: 0x6B7280,
        darkHex: 0x9CA3AF
    )

    static let statusAccepted: Color = brandPrimary

    static let statusEnRoute: Color = .dynamic(
        lightHex: 0x3949AB,
        darkHex: 0x7986CB
    )

    static let statusArrived: Color = .dynamic(
        lightHex: 0x00897B,
        darkHex: 0x4DB6AC
    )

    static let statusInProgress: Color = .dynamic(
        lightHex: 0x1557B0,
        darkHex: 0x64B5F6
    )

    // MARK: - Priority (badge aliases)

    static var priorityNormal: Color { priorityNormalAccent }

    static var priorityHigh: Color { priorityHighAccent }

    static var priorityUrgent: Color { priorityUrgentAccent }
}
