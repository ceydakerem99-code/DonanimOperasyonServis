import SwiftUI

/// Shared DOPS logo + wordmark used on auth and branding surfaces.
struct DOPSBrandMark: View {
    var logoSize: CGFloat = 88
    var showsFullName: Bool = true
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: AppSpacing.s) {
            Image("DOPSLogo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .accessibilityHidden(true)

            Text("DOPS")
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)
                .accessibilityAddTraits(.isHeader)

            if showsFullName {
                Text("Donanım Operasyon ve Servis")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DOPS, Donanım Operasyon ve Servis")
    }
}

#if DEBUG
#Preview("DOPSBrandMark") {
    DOPSBrandMark()
        .padding(AppSpacing.l)
        .background(AppColor.neutralBackground)
}
#endif
