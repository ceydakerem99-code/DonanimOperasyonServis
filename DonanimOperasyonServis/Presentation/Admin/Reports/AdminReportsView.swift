import SwiftUI

struct AdminReportsView: View {
    var onSelectReport: (AdminReportKind) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppSpacing.m) {
                ForEach(AdminReportKind.allCases) { kind in
                    ReportHubTile(kind: kind) {
                        onSelectReport(kind)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Raporlar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Reports Hub") {
    NavigationStack {
        AdminReportsView(onSelectReport: { _ in })
    }
}
#endif
