import SwiftUI

/// Read-only display of fixed domain `PauseReason` values.
struct AdminPauseReasonsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("Bekleme nedenleri domain enum'undan okunur. Kalıcı yönetim bu sürümde desteklenmez.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                ForEach(PauseReason.allCases, id: \.self) { reason in
                    HStack(spacing: AppSpacing.m) {
                        Image(systemName: "pause.circle")
                            .foregroundStyle(AppColor.brandPrimary)
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(reason.displayName)
                                .font(AppFont.subtitle)
                            Text(reason.rawValue)
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
        .navigationTitle("Bekleme Nedenleri")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Pause Reasons") {
    NavigationStack {
        AdminPauseReasonsView()
    }
}
#endif
