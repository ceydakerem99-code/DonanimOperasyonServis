import SwiftUI

/// Customer-facing satisfaction survey (prototype / demo surface).
struct CustomerSatisfactionFormView: View {
    let satisfactionId: CustomerSatisfactionID

    @Environment(\.diContainer) private var container
    @State private var viewModel: CustomerSatisfactionFormViewModel?

    var body: some View {
        Group {
            if let viewModel {
                CustomerSatisfactionFormContent(viewModel: viewModel)
            } else {
                LoadingView(message: "Form yükleniyor...")
            }
        }
        .navigationTitle("Teknik Servis Değerlendirme")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard viewModel == nil else { return }
            viewModel = CustomerSatisfactionFormViewModel(
                satisfactionId: satisfactionId,
                submissionService: container.makeCustomerSatisfactionSubmissionService(),
                customerSatisfactionRepository: container.customerSatisfactionRepository,
                remoteCustomerSatisfactionRepository: container.remoteCustomerSatisfactionRepository,
                workOrderRepository: container.workOrderRepository,
                customerRepository: container.customerRepository
            )
        }
    }
}

private struct CustomerSatisfactionFormContent: View {
    @Bindable var viewModel: CustomerSatisfactionFormViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                switch viewModel.phase {
                case .loading:
                    LoadingView(message: "Değerlendirme bilgileri yükleniyor...")
                        .frame(minHeight: 200)
                case .success:
                    successSection
                default:
                    headerSection
                    if let context = viewModel.formContext {
                        workOrderInfoSection(context)
                    }
                    ForEach(CustomerSatisfactionRatingDimension.allCases) { dimension in
                        ratingSection(for: dimension)
                    }
                    experienceOptionsSection
                    commentSection
                    if case .error(let message) = viewModel.phase {
                        ErrorBanner(title: "Gönderilemedi", message: message)
                    }
                    PrimaryButton(
                        title: "Değerlendirmeyi Gönder",
                        systemImage: "paperplane.fill",
                        isLoading: viewModel.phase == .submitting,
                        isEnabled: viewModel.canSubmit
                    ) {
                        Task { await viewModel.submit() }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.m)
        }
        .background(AppColor.neutralBackground)
        .task { await viewModel.load() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("Teknik Servis Değerlendirme")
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)
            Text("Aldığınız hizmeti değerlendirin. Puanlarınız ve geri bildiriminiz hizmet kalitemizi geliştirmemize yardımcı olur.")
                .font(AppFont.body)
                .foregroundStyle(AppColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workOrderInfoSection(_ context: CustomerSatisfactionFormContext) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "İş Emri Bilgisi")
            VStack(spacing: AppSpacing.s) {
                InfoRow(title: "İş Emri", value: context.workOrderNumber)
                InfoRow(title: "Müşteri", value: context.customerName)
                InfoRow(title: "İş Türü", value: context.workTypeLabel)
                if let completedAt = context.completedAt {
                    InfoRow(
                        title: "Tamamlanma",
                        value: completedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        }
    }

    private func ratingSection(for dimension: CustomerSatisfactionRatingDimension) -> some View {
        let selected = viewModel.rating(for: dimension)
        return VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: dimension.rawValue)
            HStack(spacing: AppSpacing.s) {
                ForEach(CustomerSatisfactionRating.allCases, id: \.self) { rating in
                    Button {
                        viewModel.selectRating(rating, for: dimension)
                    } label: {
                        Image(
                            systemName: (selected?.rawValue ?? 0) >= rating.rawValue
                                ? "star.fill"
                                : "star"
                        )
                        .font(.title2)
                        .foregroundStyle(
                            (selected?.rawValue ?? 0) >= rating.rawValue
                                ? AppColor.brandPrimary
                                : AppColor.secondaryText
                        )
                        .frame(minWidth: AppSpacing.minimumTouchTarget, minHeight: AppSpacing.minimumTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("\(rating.rawValue) yıldız"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))

            if let selected {
                Text("Seçilen: \(selected.rawValue) / 5")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
    }

    private var experienceOptionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Deneyiminiz")
            Text("Uygun olanları seçin (isteğe bağlı)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            FlowLayout(spacing: AppSpacing.s) {
                ForEach(CustomerSatisfactionExperienceOption.allCases) { option in
                    experienceChip(option)
                }
            }
        }
    }

    private func experienceChip(_ option: CustomerSatisfactionExperienceOption) -> some View {
        let selected = viewModel.selectedExperienceOptions.contains(option)
        return Button {
            viewModel.toggleExperienceOption(option)
        } label: {
            Text(option.rawValue)
                .font(AppFont.label)
                .foregroundStyle(selected ? AppColor.onPrimary : AppColor.primaryText)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? AppColor.brandPrimary : AppColor.elevatedSurface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppColor.divider, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.phase == .submitting)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Yorum (İsteğe Bağlı)")
            TextField("Deneyiminizi kısaca paylaşın...", text: $viewModel.freeformComment, axis: .vertical)
                .lineLimit(3...6)
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                .disabled(viewModel.phase == .submitting)
        }
    }

    private var successSection: some View {
        EmptyState(
            systemImage: "checkmark.circle.fill",
            title: "Teşekkürler!",
            message: "Değerlendirmeniz başarıyla kaydedildi."
        )
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xl)
    }
}

/// Simple wrapping layout for experience chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}

#if DEBUG
#Preview("Customer Satisfaction Form") {
    NavigationStack {
        CustomerSatisfactionFormView(satisfactionId: CustomerSatisfactionID("preview-survey"))
    }
    .environment(\.diContainer, DIContainer.mock())
}
#endif
