import SwiftUI

struct CustomerSatisfactionEntryCard: View {
    let entry: CustomerSatisfactionEntry
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            cardContent
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        HStack(alignment: .center, spacing: AppSpacing.s) {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                headerRow
                summaryRows
                if let preview = entry.freeformCommentText {
                    commentPreview(preview)
                } else if entry.satisfaction.status == .pending {
                    Text("Müşteri yanıtı bekleniyor.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }

            Image(systemName: "chevron.right")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(AppSpacing.m)
        .semanticAccentCard(role: accentRole(for: entry.satisfaction.status))
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(entry.workOrderNumber)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                Text(entry.customerName)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Spacer(minLength: AppSpacing.s)
            satisfactionStatusBadge(entry.satisfaction.status)
        }
    }

    private var summaryRows: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            compactInfoRow(title: "Durum", value: entry.statusLabel)
            compactInfoRow(title: "Teknisyen", value: entry.technicianName)
            compactInfoRow(title: "İş Türü", value: entry.workTypeLabel)
            if let scheduledDate = entry.scheduledDate {
                compactInfoRow(
                    title: "Planlanan Tarih",
                    value: scheduledDate.formatted(date: .abbreviated, time: .omitted)
                )
            }
            compactInfoRow(title: "Genel Puan", value: entry.ratingLabel ?? "—")
            compactInfoRow(
                title: "Servis Kalitesi",
                value: entry.dimensionScoreLabel(entry.structuredComment.serviceQualityRating)
            )
            compactInfoRow(
                title: "Personel İlgisi",
                value: entry.dimensionScoreLabel(entry.structuredComment.staffCareRating)
            )
            compactInfoRow(
                title: "Çözüm Hızı",
                value: entry.dimensionScoreLabel(entry.structuredComment.resolutionSpeedRating)
            )
        }
    }

    private func commentPreview(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            Text("💬")
                .font(AppFont.caption)
                .accessibilityHidden(true)
            Text("“\(text)”")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .accessibilityLabel("Müşteri yorumu önizlemesi: \(text)")
    }

    private func compactInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(AppFont.label)
                .foregroundStyle(AppColor.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func satisfactionStatusBadge(_ status: CustomerSatisfactionStatus) -> some View {
        Text(status.displayName)
            .font(AppFont.label)
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, AppSpacing.xs)
            .foregroundStyle(accentRole(for: status).accentColor)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .fill(accentRole(for: status).accentColor.opacity(0.12))
            )
    }

    private func accentRole(for status: CustomerSatisfactionStatus) -> AppSemanticRole {
        switch status {
        case .pending: return .paused
        case .submitted: return .completed
        case .expired: return .neutral
        }
    }
}

struct CustomerSatisfactionDetailView: View {
    let entry: CustomerSatisfactionEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                headerSection
                overallRatingSection
                dimensionRatingsSection
                if let comment = entry.freeformCommentText {
                    customerCommentSection(comment)
                }
                workInfoSection
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.m)
        }
        .background(AppColor.neutralBackground)
        .navigationTitle("Müşteri Memnuniyeti")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(entry.workOrderNumber)
                .font(AppFont.title)
            Text(entry.customerName)
                .font(AppFont.body)
                .foregroundStyle(AppColor.secondaryText)
            satisfactionStatusBadge(entry.satisfaction.status)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private var overallRatingSection: some View {
        sectionCard(title: "Genel Değerlendirme") {
            if let rating = entry.overallRatingValue {
                CustomerSatisfactionStarRatingDisplay(rating: rating)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Henüz puanlanmadı.")
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
    }

    private var dimensionRatingsSection: some View {
        sectionCard(title: "Değerlendirme Detayları") {
            VStack(spacing: AppSpacing.s) {
                dimensionRow(
                    title: "Servis Kalitesi",
                    value: entry.structuredComment.serviceQualityRating
                )
                dimensionRow(
                    title: "Personel İlgisi",
                    value: entry.structuredComment.staffCareRating
                )
                dimensionRow(
                    title: "Çözüm Hızı",
                    value: entry.structuredComment.resolutionSpeedRating
                )
            }
        }
    }

    private func customerCommentSection(_ comment: String) -> some View {
        sectionCard(title: "Müşteri Yorumu") {
            Text("“\(comment)”")
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var workInfoSection: some View {
        sectionCard(title: "İş Bilgileri") {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                InfoRow(title: "Teknisyen", value: entry.technicianName, systemImage: "person.fill")
                InfoRow(title: "İş Türü", value: entry.workTypeLabel, systemImage: "wrench.and.screwdriver")
                if let scheduledDate = entry.scheduledDate {
                    InfoRow(
                        title: "Planlanan Tarih",
                        value: scheduledDate.formatted(date: .abbreviated, time: .omitted),
                        systemImage: "calendar"
                    )
                }
                if let submittedAt = entry.satisfaction.submittedAt {
                    InfoRow(
                        title: "Gönderim Tarihi",
                        value: submittedAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "paperplane"
                    )
                }
            }
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: title)
            content()
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private func dimensionRow(title: String, value: Int?) -> some View {
        HStack {
            Text(title)
                .font(AppFont.body)
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            Text(entry.dimensionScoreLabel(value))
                .font(AppFont.label)
                .foregroundStyle(AppColor.primaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(entry.dimensionScoreLabel(value))")
    }

    private func satisfactionStatusBadge(_ status: CustomerSatisfactionStatus) -> some View {
        Text(status.displayName)
            .font(AppFont.label)
            .padding(.horizontal, AppSpacing.s)
            .padding(.vertical, AppSpacing.xs)
            .foregroundStyle(accentRole(for: status).accentColor)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .fill(accentRole(for: status).accentColor.opacity(0.12))
            )
    }

    private func accentRole(for status: CustomerSatisfactionStatus) -> AppSemanticRole {
        switch status {
        case .pending: return .paused
        case .submitted: return .completed
        case .expired: return .neutral
        }
    }
}

struct CustomerSatisfactionStarRatingDisplay: View {
    let rating: Int

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(1...5, id: \.self) { value in
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(
                            value <= rating ? AppColor.brandPrimary : AppColor.secondaryText
                        )
                        .accessibilityHidden(true)
                }
            }
            Text("\(rating) / 5")
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Genel puan \(rating) üzerinden 5")
    }
}

#if DEBUG
#Preview("Customer Satisfaction Entry Card") {
    let entry = CustomerSatisfactionEntry(
        id: CustomerSatisfactionID("cs-preview"),
        satisfaction: CustomerSatisfaction(
            id: CustomerSatisfactionID("cs-preview"),
            workOrderId: WorkOrderID("wo-1"),
            customerId: CustomerID("cust-1"),
            status: .submitted,
            rating: .five,
            comment: """
            Servis Kalitesi: 4/5
            Personel İlgisi: 4/5
            Çözüm Hızı: 5/5
            Yorum: Servisten çok memnun kaldım. Teknisyen ilgiliydi ve işlem hızlı tamamlandı.
            """,
            createdAt: .now,
            updatedAt: .now,
            submittedAt: .now
        ),
        workOrderId: WorkOrderID("wo-1"),
        workOrderNumber: "WO-2026-001",
        customerName: "Migros Bahçelievler",
        technicianName: "Mehmet Kerem",
        workTypeLabel: "Arıza",
        scheduledDate: .now,
        sortDate: .now
    )

    return NavigationStack {
        ScrollView {
            CustomerSatisfactionEntryCard(
                entry: entry,
                onTap: {}
            )
            .padding()
        }
    }
}
#endif
