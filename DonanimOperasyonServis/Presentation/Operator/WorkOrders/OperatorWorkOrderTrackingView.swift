import SwiftUI

/// Operator read-only field tracking: map + GPS / status times for one work order.
struct OperatorWorkOrderTrackingView: View {
    let workOrderId: WorkOrderID
    @State private var viewModel: OperatorWorkOrderDetailViewModel

    init(workOrderId: WorkOrderID, dependencies: OperatorDependencies, actor: User) {
        self.workOrderId = workOrderId
        _viewModel = State(initialValue: OperatorWorkOrderDetailViewModel(
            workOrderId: workOrderId,
            actor: actor,
            dependencies: dependencies
        ))
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                LoadingView(message: "Takip yükleniyor...")
            case .error(let message):
                ErrorBanner(title: "Takip yüklenemedi", message: message) {
                    Task { await viewModel.load() }
                }
                .padding(AppSpacing.l)
            case .loaded:
                if let content = viewModel.content {
                    trackingBody(content)
                }
            }
        }
        .navigationTitle("Saha Takibi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func trackingBody(_ content: OperatorWorkOrderDetailContent) -> some View {
        let snapshot = content.reportSnapshot
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                HStack {
                    Text(content.workOrder.workOrderNumber).font(AppFont.title)
                    Spacer()
                    StatusChip(status: WorkOrderPresentationMapping.appStatus(from: content.workOrder.status))
                }

                InfoRow(title: "Müşteri", value: content.customer.name, systemImage: "building.2")
                InfoRow(title: "Teknisyen", value: content.technicianName, systemImage: "person.fill")

                WorkOrderMapSection(
                    customerName: content.customer.name,
                    address: content.customer.address,
                    city: content.customer.city,
                    capturedLocations: content.locations
                )
                .environment(\.workOrderMapHeight, 260)

                SectionHeader(title: "Saha Zamanları")
                milestoneRow(
                    "Yola Çıkış",
                    snapshot.milestoneTime(status: .enRoute, locationEvent: .enRoute)
                )
                milestoneRow(
                    "Varış",
                    snapshot.milestoneTime(status: .arrived, locationEvent: .arrived)
                )
                milestoneRow("İşe Başlama", snapshot.firstStatusTime(.inProgress))
                milestoneRow(
                    "Tamamlanma",
                    content.workOrder.completedAt
                        ?? snapshot.milestoneTime(status: .completed, locationEvent: .completed)
                )

                SectionHeader(title: "GPS Kayıtları")
                if content.locations.isEmpty {
                    Text("Henüz GPS kaydı yok. Teknisyen yola çıktığında burada görünür.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                } else {
                    ForEach(content.locations.sorted(by: { $0.capturedAt > $1.capturedAt }), id: \.id) { location in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.event.displayName).font(AppFont.body)
                            Text(WorkOrderPresentationMapping.formatDateTime(location.capturedAt))
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                            Text(
                                String(
                                    format: "%.5f, %.5f",
                                    location.coordinate.latitude,
                                    location.coordinate.longitude
                                )
                            )
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.m)
                        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
                    }
                }
            }
            .padding(AppSpacing.l)
        }
    }

    private func milestoneRow(_ title: String, _ date: Date?) -> some View {
        InfoRow(
            title: title,
            value: date.map(WorkOrderPresentationMapping.formatDateTime) ?? "—",
            systemImage: "clock"
        )
    }
}
