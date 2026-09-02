import SwiftUI
import Charts

struct CustomerSatisfactionContentView: View {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case error(String)
    }

    let phase: Phase
    let showsLoadingIndicator: Bool
    let hasCachedContent: Bool
    let summary: CustomerSatisfactionSummary?
    let ratingBars: [CustomerSatisfactionRatingBar]
    let technicianSummaries: [CustomerSatisfactionTechnicianSummary]
    let recentEntries: [CustomerSatisfactionEntry]
    var onSelectEntry: (CustomerSatisfactionEntry) -> Void
    var onReload: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                AsyncLoadContainerView(
                    isLoading: phase == .loading,
                    showsLoadingIndicator: showsLoadingIndicator,
                    hasCachedContent: hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(phase),
                    isEmpty: phase == .empty,
                    loadingMessage: "Müşteri memnuniyeti yükleniyor...",
                    errorTitle: "Veriler yüklenemedi",
                    onRetry: onReload,
                    content: {
                        if let summary {
                            summarySection(summary)
                            ratingDistributionSection
                            technicianPerformanceSection
                            recentEvaluationsSection
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "star.bubble",
                            title: "Değerlendirme yok",
                            message: "Henüz müşteri memnuniyeti kaydı bulunmuyor."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private func summarySection(_ summary: CustomerSatisfactionSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Özet")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                SemanticMetricCard(
                    title: "Ortalama Puan",
                    value: summary.averageRatingLabel,
                    role: .completed,
                    systemImage: "star.fill"
                )
                SemanticMetricCard(
                    title: "Toplam Değerlendirme",
                    value: "\(summary.submittedCount)",
                    role: .primary,
                    systemImage: "checkmark.circle"
                )
                SemanticMetricCard(
                    title: "Bekleyen",
                    value: "\(summary.pendingCount)",
                    role: .paused,
                    systemImage: "clock"
                )
                SemanticMetricCard(
                    title: "Toplam Kayıt",
                    value: "\(summary.totalCount)",
                    role: .neutral,
                    systemImage: "list.bullet"
                )
            }
        }
    }

    private var ratingDistributionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "5 Üzerinden Puan Dağılımı")
            if ratingBars.allSatisfy({ $0.count == 0 }) {
                Text("Henüz yanıtlanmış değerlendirme yok.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.secondaryText)
                    .padding(AppSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            } else {
                Chart(ratingBars) { bar in
                    BarMark(
                        x: .value("Puan", bar.label),
                        y: .value("Adet", bar.count)
                    )
                    .foregroundStyle(AppColor.primary.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 180)
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))

                VStack(spacing: AppSpacing.xs) {
                    ForEach(ratingBars) { bar in
                        HStack {
                            Text("\(bar.label) yıldız")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                            Spacer()
                            Text("\(bar.count)")
                                .font(AppFont.label)
                        }
                    }
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var technicianPerformanceSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Teknisyen Performansı")
            if technicianSummaries.isEmpty {
                Text("Henüz yanıtlanmış değerlendirme yok.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.secondaryText)
                    .padding(AppSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            } else {
                ForEach(technicianSummaries) { summary in
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Text(summary.name)
                            .font(AppFont.subtitle)

                        HStack(spacing: AppSpacing.l) {
                            technicianMetricColumn(
                                title: "Ort. Puan",
                                value: summary.averageRatingLabel
                            )
                            technicianMetricColumn(
                                title: "Değerlendirme",
                                value: "\(summary.submittedCount)"
                            )
                            technicianMetricColumn(
                                title: "5 Yıldız",
                                value: summary.fiveStarRatioLabel
                            )
                        }
                    }
                    .padding(AppSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                }
            }
        }
    }

    private func technicianMetricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Text(value)
                .font(AppFont.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentEvaluationsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Son Değerlendirmeler")
            if recentEntries.isEmpty {
                Text("Gösterilecek kayıt yok.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(recentEntries) { entry in
                    CustomerSatisfactionEntryCard(
                        entry: entry,
                        onTap: { onSelectEntry(entry) }
                    )
                }
            }
        }
    }
}
