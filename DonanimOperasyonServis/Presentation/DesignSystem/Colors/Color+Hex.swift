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
    /// `dark` in Dark Appearance. Both operands are captured on the main
    /// actor because `Color`/`UIColor` conversions must run there.
    @MainActor
    static func dynamic(light: Color, dark: Color) -> Color {
        let lightUI = UIColor(light)
        let darkUI = UIColor(dark)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkUI : lightUI
        })
    }
}
