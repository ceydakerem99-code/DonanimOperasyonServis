import SwiftUI
import UIKit

/// Visual signature-capture surface with optional parent-owned strokes
/// so callers can export PNG via `SignatureImageExport`.
struct SignatureCanvas: View {
    var title: String = "İmza"
    var subtitle: String?
    @Binding var strokes: [[CGPoint]]

    @State private var currentStroke: [CGPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            header

            canvas
                .frame(height: 180)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(AppColor.brandSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .foregroundStyle(AppColor.divider)
                )
                .overlay(alignment: .center) {
                    if strokes.isEmpty && currentStroke.isEmpty {
                        Text("İmza için ekrana dokunun")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

            HStack {
                Spacer()
                Button {
                    strokes.removeAll()
                    currentStroke.removeAll()
                } label: {
                    Label("Temizle", systemImage: "arrow.counterclockwise")
                        .font(AppFont.buttonLabel)
                        .foregroundStyle(AppColor.brandPrimary)
                        .frame(minHeight: AppSpacing.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .disabled(strokes.isEmpty && currentStroke.isEmpty)
                .accessibilityLabel(Text("İmzayı temizle"))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
            if let subtitle {
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
    }

    private var canvas: some View {
        Canvas { context, _ in
            for stroke in strokes {
                context.stroke(path(for: stroke), with: .color(AppColor.primaryText), lineWidth: 2)
            }
            context.stroke(path(for: currentStroke), with: .color(AppColor.primaryText), lineWidth: 2)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    currentStroke.append(value.location)
                }
                .onEnded { _ in
                    guard !currentStroke.isEmpty else { return }
                    strokes.append(currentStroke)
                    currentStroke.removeAll()
                }
        )
    }

    private func path(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

/// Renders captured strokes to PNG for `recordSignature(imageData:)`.
enum SignatureImageExport {
    @MainActor
    static func pngData(
        strokes: [[CGPoint]],
        size: CGSize = CGSize(width: 600, height: 240)
    ) -> Data? {
        guard !strokes.isEmpty else { return nil }
        let view = SignatureStrokePreview(strokes: strokes)
            .frame(width: size.width, height: size.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage?.pngData()
    }
}

private struct SignatureStrokePreview: View {
    let strokes: [[CGPoint]]

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                var path = Path()
                guard let first = stroke.first else { continue }
                path.move(to: first)
                for point in stroke.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(path, with: .color(.black), lineWidth: 2.5)
            }
        }
    }
}

#if DEBUG
#Preview("SignatureCanvas") {
    @Previewable @State var strokes: [[CGPoint]] = []
    VStack(spacing: AppSpacing.xl) {
        SignatureCanvas(
            title: "Teknisyen İmzası",
            subtitle: "Ahmet Yılmaz",
            strokes: $strokes
        )
        SignatureCanvas(
            title: "Müşteri İmzası",
            subtitle: "Mehmet Kaya (ABC Market)",
            strokes: $strokes
        )
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
