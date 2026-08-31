import SwiftUI

struct OperatorCustomerDetailView: View {
    @Bindable var viewModel: OperatorCustomerDetailViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void
    var onEditCustomer: (CustomerID) -> Void

    var body: some View {
        Group {
            AsyncLoadContainerView(
                isLoading: viewModel.phase == .loading,
                showsLoadingIndicator: viewModel.showsLoadingIndicator,
                hasCachedContent: viewModel.hasCachedContent,
                errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                isEmpty: false,
                loadingMessage: "Müşteri yükleniyor...",
                errorTitle: "Detay yüklenemedi",
                onRetry: { Task { await viewModel.load() } }
            ) {
                if let content = viewModel.content {
                    detailContent(content)
                }
            }
        }
        .navigationTitle("Müşteri Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Düzenle") {
                    onEditCustomer(viewModel.customerId)
                }
            }
        }
        .task(id: viewModel.customerId) { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private func detailContent(_ content: OperatorCustomerDetailContent) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.l) {
                infoSection(content.customer)
                historySection(content)
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private func infoSection(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("İletişim Bilgileri")
                .font(AppFont.subtitle)
            InfoRow(title: "Firma / Ad", value: customer.name, systemImage: "building.2")
            if let contact = customer.contactPersonName, !contact.isEmpty {
                InfoRow(title: "Yetkili", value: contact, systemImage: "person")
            }
            if let phone = customer.phoneNumber?.rawValue, !phone.isEmpty {
                InfoRow(title: "Telefon", value: phone, systemImage: "phone")
            }
            if let email = customer.email, !email.isEmpty {
                InfoRow(title: "E-posta", value: email, systemImage: "envelope")
            }
            InfoRow(title: "Adres", value: customer.address, systemImage: "mappin.and.ellipse")
            if let city = customer.city, !city.isEmpty {
                InfoRow(title: "Şehir", value: city, systemImage: "location")
            }
            if let notes = customer.notes, !notes.isEmpty {
                InfoRow(title: "Not", value: notes, systemImage: "note.text")
            }
            InfoRow(
                title: "Son Güncelleme",
                value: WorkOrderPresentationMapping.formatDateTime(customer.updatedAt),
                systemImage: "clock"
            )
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }

    private func historySection(_ content: OperatorCustomerDetailContent) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Text("İş Emri Geçmişi")
                    .font(AppFont.subtitle)
                Spacer()
                Text("\(content.workOrderCards.count)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            if content.workOrderCards.isEmpty {
                EmptyState(
                    systemImage: "doc.text",
                    title: "Henüz iş emri yok",
                    message: "Bu müşteri için oluşturulmuş iş emri bulunmuyor."
                )
                .frame(minHeight: 120)
            } else {
                ForEach(content.workOrderCards) { card in
                    WorkOrderCard(data: card) {
                        onSelectWorkOrder(WorkOrderID(card.id))
                    }
                }
            }
        }
    }
}
