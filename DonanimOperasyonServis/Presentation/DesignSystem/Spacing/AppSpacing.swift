import CoreGraphics

/// 4-pt spacing grid. Use these tokens for padding, insets, and gaps.
/// Do not sprinkle raw numeric literals through view code.
enum AppSpacing {
    /// 4 pt
    static let xs: CGFloat = 4
    /// 8 pt
    static let s: CGFloat = 8
    /// 12 pt
    static let m: CGFloat = 12
    /// 16 pt
    static let l: CGFloat = 16
    /// 24 pt
    static let xl: CGFloat = 24
    /// 32 pt
    static let xxl: CGFloat = 32

    /// Minimum touch target size mandated by HIG for tappable elements.
    static let minimumTouchTarget: CGFloat = 44
}
