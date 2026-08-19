import SwiftUI

/// A label/value row used inside detail cards and forms.
///
/// The optional `systemImage` is rendered as a leading glyph. `value`
/// is optional so the row can render a title-only header line when
/// paired with other InfoRows.
struct InfoRow: View {
    let title: String
    var value: String?
    var systemImage: String?
    var valueColor: Color?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.m) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.brandPrimary)
                    .frame(width: AppSpacing.xl, alignment: .center)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                if let value {
                    Text(value)
                        .font(AppFont.body)
                        .foregroundStyle(valueColor ?? AppColor.primaryText)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("InfoRow") {
    VStack(spacing: AppSpacing.s) {
        InfoRow(title: "Müşteri", value: "ABC Market", systemImage: "building.2")
        InfoRow(title: "Telefon", value: "0505 123 45 67", systemImage: "phone")
        InfoRow(title: "Adres",
                value: "Bahçelievler Mah. Gazi Cad. No:12 Çorum",
                systemImage: "mappin.and.ellipse")
        InfoRow(title: "Cihaz", value: "POS Ingenico DX8000", systemImage: "creditcard")
        InfoRow(title: "Seri No", value: "98765432310", systemImage: "number")
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
