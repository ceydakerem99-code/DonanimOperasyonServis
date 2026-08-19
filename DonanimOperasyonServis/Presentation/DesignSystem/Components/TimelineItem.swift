import SwiftUI

/// Timeline row used by service-note and status-history lists.
///
/// Renders a colored dot in the left rail with the connecting line,
/// followed by the title, an optional subtitle, and a timestamp label.
struct TimelineItem: View {
    let time: String
    let title: String
    var subtitle: String?
    var author: String?
    var accentColor: Color = AppColor.brandPrimary
    var systemImage: String?
    /// When `false`, the vertical connector below the dot is hidden.
    /// Set on the last item of a list.
    var showsConnector: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.m) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Circle()
                        .fill(accentColor)
                        .frame(width: 10, height: 10)
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                }
                if showsConnector {
                    Rectangle()
                        .fill(AppColor.divider)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.s) {
                    Text(time)
                        .font(AppFont.monoDigits)
                        .foregroundStyle(AppColor.secondaryText)
                    if let author {
                        Text(author)
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                Text(title)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            .padding(.bottom, AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("TimelineItem") {
    VStack(alignment: .leading, spacing: 0) {
        TimelineItem(
            time: "10:42",
            title: "Cihaz kontrol edildi.",
            author: "Ahmet Yılmaz",
            accentColor: AppStatus.inProgress.accentColor,
            systemImage: AppStatus.inProgress.symbolName
        )
        TimelineItem(
            time: "10:55",
            title: "Adaptörün arızalı olduğu tespit edildi.",
            author: "Ahmet Yılmaz",
            accentColor: AppColor.warning
        )
        TimelineItem(
            time: "11:20",
            title: "Adaptör değiştirildi.",
            subtitle: "Yeni adaptör seri no: A-451923",
            author: "Ahmet Yılmaz",
            accentColor: AppStatus.completed.accentColor,
            systemImage: AppStatus.completed.symbolName,
            showsConnector: false
        )
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
