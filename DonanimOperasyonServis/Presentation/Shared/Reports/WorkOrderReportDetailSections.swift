import SwiftUI
import UIKit

/// Shared read-only report body: notes, photos, GPS, signatures + media.
struct WorkOrderReportDetailSections: View {
    let snapshot: WorkOrderReportSnapshot
    let mediaLoader: WorkOrderMediaLoader

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            header
            deviceBlock
            milestonesBlock
            timelineBlock
            notesBlock
            photosBlock
            locationsBlock
            signaturesBlock
            editRequestsBlock
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Text(snapshot.workOrder.workOrderNumber).font(AppFont.title)
                Spacer()
                StatusChip(status: WorkOrderPresentationMapping.appStatus(from: snapshot.workOrder.status))
            }
            InfoRow(title: "Müşteri", value: snapshot.customerName, systemImage: "building.2")
            if let address = snapshot.customerAddress, !address.isEmpty {
                InfoRow(title: "Adres", value: address, systemImage: "mappin.and.ellipse")
            }
            if let technicianName = snapshot.technicianName, !technicianName.isEmpty {
                InfoRow(title: "Teknisyen", value: technicianName, systemImage: "person.fill")
            }
            InfoRow(title: "İş Türü", value: snapshot.workOrder.workType.displayName, systemImage: "briefcase")
            if let completedAt = snapshot.workOrder.completedAt {
                InfoRow(
                    title: "Tamamlanma",
                    value: WorkOrderPresentationMapping.formatDateTime(completedAt),
                    systemImage: "checkmark.seal"
                )
            }
            if let description = snapshot.workOrder.issueDescription, !description.isEmpty {
                InfoRow(title: "Yapılan İşlem", value: description, systemImage: "text.alignleft")
            }
        }
    }

    private var deviceBlock: some View {
        reportCard("Cihaz") {
            InfoRow(
                title: "Kategori",
                value: snapshot.workOrder.deviceCategory.displayName,
                systemImage: "shippingbox"
            )
            InfoRow(title: "Marka / Model", value: "\(snapshot.workOrder.deviceBrand) · \(snapshot.workOrder.deviceModel)", systemImage: "creditcard")
            InfoRow(title: "Seri No", value: snapshot.workOrder.serialNumber, systemImage: "number")
        }
    }

    private var milestonesBlock: some View {
        reportCard("Saha Zamanları") {
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
                snapshot.workOrder.completedAt
                    ?? snapshot.milestoneTime(status: .completed, locationEvent: .completed)
            )
        }
    }

    private var timelineBlock: some View {
        reportCard("Durum Geçmişi (\(snapshot.timeline.count))") {
            if snapshot.timeline.isEmpty {
                Text("Kayıt yok.").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(snapshot.timeline, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.toStatus.displayName).font(AppFont.body)
                        Text(WorkOrderPresentationMapping.formatDateTime(entry.occurredAt))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
    }

    private func milestoneRow(_ title: String, _ date: Date?) -> some View {
        InfoRow(
            title: title,
            value: date.map(WorkOrderPresentationMapping.formatDateTime) ?? "—",
            systemImage: "clock"
        )
    }

    private var notesBlock: some View {
        reportCard("Servis Notları (\(snapshot.noteCount))") {
            if snapshot.notes.isEmpty {
                Text("Not yok.").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(snapshot.notes, id: \.id) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WorkOrderPresentationMapping.formatDateTime(note.createdAt))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        Text(note.text)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
    }

    private var photosBlock: some View {
        reportCard("Fotoğraflar (\(snapshot.photoCount))") {
            if snapshot.photos.isEmpty {
                Text("Fotoğraf yok.").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: AppSpacing.m
                ) {
                    ForEach(snapshot.photos, id: \.id) { photo in
                        ReportPhotoCell(photo: photo, mediaLoader: mediaLoader)
                    }
                }
            }
        }
    }

    private var locationsBlock: some View {
        reportCard("GPS Kayıtları (\(snapshot.locationCount))") {
            if snapshot.locations.isEmpty {
                Text("GPS kaydı yok.").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(snapshot.locations, id: \.id) { location in
                    VStack(alignment: .leading, spacing: 2) {
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
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
    }

    private var signaturesBlock: some View {
        reportCard("İmzalar (\(snapshot.signatureCount))") {
            if snapshot.signatures.isEmpty {
                Text("İmza yok.").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
            } else {
                ForEach(snapshot.signatures, id: \.id) { signature in
                    ReportSignatureCell(signature: signature, mediaLoader: mediaLoader)
                }
            }
        }
    }

    @ViewBuilder
    private var editRequestsBlock: some View {
        if !snapshot.editRequests.isEmpty {
            reportCard("Düzenleme Talepleri (\(snapshot.editRequestCount))") {
                ForEach(snapshot.editRequests, id: \.id) { req in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(EditableWorkOrderField(rawValue: req.field)?.displayName ?? req.field)
                                .font(AppFont.body)
                            Spacer()
                            Text(req.status.displayName)
                                .font(AppFont.label)
                                .foregroundStyle(editRequestStatusColor(req.status))
                                .padding(.horizontal, AppSpacing.s)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(editRequestStatusColor(req.status).opacity(0.12)))
                        }
                        Text("Talep: \(WorkOrderPresentationMapping.formatDateTime(req.createdAt))")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        if let reviewedAt = req.reviewedAt {
                            Text("Karar: \(WorkOrderPresentationMapping.formatDateTime(reviewedAt))")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        Text("Eski: \(req.currentValue.isEmpty ? "—" : req.currentValue)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        Text("Yeni: \(req.requestedValue.isEmpty ? "—" : req.requestedValue)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        if !req.reason.isEmpty {
                            Text("Neden: \(req.reason)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        if let note = req.decisionNote, !note.isEmpty {
                            Text("Karar Notu: \(note)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
    }

    private func editRequestStatusColor(_ status: EditRequestStatus) -> Color {
        switch status {
        case .pending:  return AppColor.warning
        case .approved: return AppColor.success
        case .rejected: return AppColor.danger
        }
    }

    private func reportCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(title).font(AppFont.subtitle)
            content()
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }
}

private struct ReportPhotoCell: View {
    let photo: WorkOrderPhoto
    let mediaLoader: WorkOrderMediaLoader
    @State private var imageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Group {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(AppColor.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(AppColor.neutralBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))

            Text(photo.category.displayName)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .task(id: photo.id) {
            imageData = await mediaLoader.loadPhoto(photo)
        }
    }
}

private struct ReportSignatureCell: View {
    let signature: Signature
    let mediaLoader: WorkOrderMediaLoader
    @State private var imageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(signature.kind.displayName).font(AppFont.body)
            if let name = signature.signerName, !name.isEmpty {
                Text(name).font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
            }
            Group {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Image(systemName: "signature")
                        .foregroundStyle(AppColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(AppColor.neutralBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.divider)
            )
            Text(WorkOrderPresentationMapping.formatDateTime(signature.capturedAt))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(.vertical, AppSpacing.xs)
        .task(id: signature.id) {
            imageData = await mediaLoader.loadSignature(signature)
        }
    }
}
