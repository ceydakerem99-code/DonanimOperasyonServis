import SwiftUI

struct AdminReportsView: View {
    var onSelectReport: (AdminReportKind) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppSpacing.m) {
                ForEach(AdminReportKind.allCases) { kind in
                    reportTile(kind)
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Raporlar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reportTile(_ kind: AdminReportKind) -> some View {
        Button {
            onSelectReport(kind)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(AppColor.brandPrimary)
                Text(kind.title)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.leading)
                Text(kind.subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityHint(kind.subtitle)
    }
}

#if DEBUG
#Preview("Reports Hub") {
    NavigationStack {
        AdminReportsView(onSelectReport: { _ in })
    }
}
#endif
