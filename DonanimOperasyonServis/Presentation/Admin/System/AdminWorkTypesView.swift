import SwiftUI

/// Read-only display of fixed domain `WorkType` values.
struct AdminWorkTypesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("İş türleri domain enum'undan okunur. Kalıcı yönetim bu sürümde desteklenmez.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                ForEach(WorkType.allCases, id: \.self) { type in
                    HStack(spacing: AppSpacing.m) {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(AppColor.brandPrimary)
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(type.displayName)
                                .font(AppFont.subtitle)
                            Text(type.rawValue)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        Spacer()
                        Text("Sabit")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .padding(AppSpacing.m)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("İş Türleri Yönetimi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Work Types") {
    NavigationStack {
        AdminWorkTypesView()
    }
}
#endif
