import SwiftUI
import UIKit

/// Small photo thumbnail for use in detail views (not the full report).
struct DetailPhotoThumbnail: View {
    let photo: WorkOrderPhoto
    let mediaLoader: WorkOrderMediaLoader
    @State private var imageData: Data?

    var body: some View {
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
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .background(AppColor.neutralBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.divider)
        )
        .task(id: photo.id) {
            imageData = await mediaLoader.loadPhoto(photo)
        }
    }
}

/// Compact signature preview for detail views.
struct DetailSignatureThumbnail: View {
    let signature: Signature
    let mediaLoader: WorkOrderMediaLoader
    @State private var imageData: Data?

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            Group {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    Image(systemName: "signature")
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            .frame(width: 80, height: 48)
            .background(AppColor.neutralBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.divider)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(signature.kind.displayName)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.primaryText)
                if let name = signature.signerName, !name.isEmpty {
                    Text(name)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Text(WorkOrderPresentationMapping.formatDateTime(signature.capturedAt))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Spacer()
        }
        .task(id: signature.id) {
            imageData = await mediaLoader.loadSignature(signature)
        }
    }
}
