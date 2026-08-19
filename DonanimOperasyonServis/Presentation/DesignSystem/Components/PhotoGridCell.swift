import SwiftUI

/// Square photo cell used inside grids. Renders an image (or a symbol
/// placeholder when no image is provided), an optional caption/category
/// label, and an optional upload indicator.
struct PhotoGridCell: View {
    let image: Image?
    var categoryLabel: String?
    var isUploading: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.image, style: .continuous)
            .fill(AppColor.brandSurface)
            .overlay(imageOverlay)
            .overlay(alignment: .topLeading) { categoryChip }
            .overlay(alignment: .topTrailing) { uploadIndicator }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.image, style: .continuous))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var imageOverlay: some View {
        if let image {
            image
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "photo")
                .font(AppFont.title)
                .foregroundStyle(AppColor.secondaryText)
        }
    }

    @ViewBuilder private var categoryChip: some View {
        if let categoryLabel {
            Text(categoryLabel)
                .font(AppFont.label)
                .foregroundStyle(AppColor.onPrimary)
                .padding(.horizontal, AppSpacing.s)
                .padding(.vertical, AppSpacing.xs)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppColor.brandPrimary.opacity(0.85))
                )
                .padding(AppSpacing.xs)
        }
    }

    @ViewBuilder private var uploadIndicator: some View {
        if isUploading {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColor.onPrimary)
                .padding(AppSpacing.s)
                .background(
                    Circle().fill(Color.black.opacity(0.35))
                )
                .padding(AppSpacing.xs)
        }
    }

    private var accessibilityLabel: Text {
        if let categoryLabel {
            Text("Fotoğraf, \(categoryLabel)")
        } else {
            Text("Fotoğraf")
        }
    }
}

#if DEBUG
#Preview("PhotoGridCell") {
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    return LazyVGrid(columns: columns, spacing: AppSpacing.s) {
        PhotoGridCell(image: nil, categoryLabel: "Öncesi")
        PhotoGridCell(image: nil, categoryLabel: "Sonrası", isUploading: true)
        PhotoGridCell(image: nil, categoryLabel: "Kanıt")
        PhotoGridCell(image: nil)
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
