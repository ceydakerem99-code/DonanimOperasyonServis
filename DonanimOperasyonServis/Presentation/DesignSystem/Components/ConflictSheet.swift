import SwiftUI

/// Modal sheet content used when the sync layer detects that a
/// server-side change and a local change collide on the same field.
///
/// Purely visual for Phase 1 — the sync/conflict logic that decides
/// when to present this sheet is added in Phase 5.
///
/// Caller passes two records (already formatted for display) and gets
/// back the user's choice via callbacks.
struct ConflictSheet: View {
    struct Version {
        let title: String
        let subtitle: String?
        let updatedByLabel: String?
        let timestampLabel: String?
    }

    let field: String
    let server: Version
    let local: Version
    let onUseServer: () -> Void
    let onUseLocal: () -> Void
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            header
            versionCard(title: "Sunucudaki Sürüm",
                        systemImage: "cloud.fill",
                        version: server)
            versionCard(title: "Cihazdaki Sürüm",
                        systemImage: "iphone",
                        version: local)

            VStack(spacing: AppSpacing.s) {
                PrimaryButton(title: "Sunucu Verisini Kullan",
                              systemImage: "cloud.fill",
                              action: onUseServer)
                SecondaryButton(title: "Yerel Veriyi Kullan",
                                systemImage: "iphone",
                                action: onUseLocal)
                if let onDismiss {
                    Button("Sonra Karar Ver", action: onDismiss)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .frame(minHeight: AppSpacing.minimumTouchTarget)
                }
            }
        }
        .padding(AppSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous)
                .fill(AppColor.elevatedSurface)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.warning)
                Text("Senkronizasyon Çakışması")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.primaryText)
            }
            Text("\"\(field)\" alanı sunucuda ve cihazda farklı. Hangi sürümü kullanmak istersiniz?")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
    }

    private func versionCard(title: String, systemImage: String, version: Version) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(AppColor.brandPrimary)
                Text(title)
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Text(version.title)
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
            if let subtitle = version.subtitle {
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            HStack(spacing: AppSpacing.s) {
                if let updatedByLabel = version.updatedByLabel {
                    Text(updatedByLabel)
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.secondaryText)
                }
                if let timestampLabel = version.timestampLabel {
                    Text(timestampLabel)
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.brandSurface)
        )
    }
}

#if DEBUG
#Preview("ConflictSheet") {
    ConflictSheet(
        field: "Planlanan Saat",
        server: .init(
            title: "10:00 – 11:30",
            subtitle: "Sunucuda güncellenmiş plan",
            updatedByLabel: "Mehmet Kaya",
            timestampLabel: "18.08.2026 10:15"
        ),
        local: .init(
            title: "11:00 – 12:00",
            subtitle: "Cihazda offline yapılmış değişiklik",
            updatedByLabel: "Ahmet Yılmaz",
            timestampLabel: "18.08.2026 10:12"
        ),
        onUseServer: {},
        onUseLocal: {},
        onDismiss: {}
    )
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
