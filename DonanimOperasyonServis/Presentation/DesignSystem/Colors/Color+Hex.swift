import SwiftUI
import UIKit

extension Color {
    /// Creates a color from an integer hex literal like `0x11365C`.
    init(hex: UInt32, alpha: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Creates a color that resolves to `light` in Light Appearance and
    /// `dark` in Dark Appearance.
    ///
    /// Must remain **nonisolated**. SwiftUI may resolve colors on
    /// `com.apple.SwiftUI.AsyncRenderer`; a `@MainActor` trait provider
    /// traps with `_dispatch_assert_queue_fail` when switching tabs.
    nonisolated static func dynamic(lightHex: UInt32, darkHex: UInt32) -> Color {
        let lightUI = UIColor(rgbaHex: lightHex)
        let darkUI = UIColor(rgbaHex: darkHex)
        return Color(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? darkUI : lightUI
            }
        )
    }
}

extension UIColor {
    /// Pure RGB UIColor from a 0xRRGGBB hex — safe off the main actor.
    nonisolated convenience init(rgbaHex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((rgbaHex >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgbaHex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgbaHex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}
