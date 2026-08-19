import SwiftUI

/// Central typography scale.
///
/// Views must use these tokens instead of building `Font` values inline
/// with `.system(size:weight:)`. Point sizes here map to SF Pro Text
/// at the default Dynamic Type baseline (`.body` = 17 pt); each token is
/// declared as a relative `Font.system(_:weight:)` so it scales with the
/// user's preferred content size.
enum AppFont {

    /// 28 pt bold — top-level screen title.
    static let displayTitle: Font = .system(.largeTitle, weight: .bold)

    /// 22 pt semibold — section or sheet title.
    static let title: Font = .system(.title2, weight: .semibold)

    /// 17 pt semibold — subtitles, prominent list rows.
    static let subtitle: Font = .system(.headline, weight: .semibold)

    /// 16 pt regular — body copy, form values.
    static let body: Font = .system(.body, weight: .regular)

    /// 13 pt regular — captions, helper text.
    static let caption: Font = .system(.footnote, weight: .regular)

    /// 12 pt medium — small labels, chips, badges.
    static let label: Font = .system(.caption, weight: .medium)

    /// 15 pt semibold — primary button label.
    static let buttonLabel: Font = .system(.subheadline, weight: .semibold)

    /// Monospaced digits for timelines, numbers-heavy rows.
    static let monoDigits: Font = .system(.body, weight: .regular)
        .monospacedDigit()
}
