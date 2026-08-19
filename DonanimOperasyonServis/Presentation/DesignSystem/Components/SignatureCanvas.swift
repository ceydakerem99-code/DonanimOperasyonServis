import SwiftUI

/// Visual signature-capture surface.
///
/// Captures finger strokes as `Path` values held in local state so the
/// component looks and feels functional in previews. No persistence,
/// export, or upload behaviour lives here — those responsibilities
/// belong to the Signature use cases and repositories added in Phase 8.
///
/// Provide an optional `title` and `subtitle` shown above the canvas.
struct SignatureCanvas: View {
    var title: String = "İmza"
    var subtitle: String?

    @State private var currentStroke: [CGPoint] = []
    @State private var completedStrokes: [[CGPoint]] = []

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
                    if completedStrokes.isEmpty && currentStroke.isEmpty {
                        Text("İmza için ekrana dokunun")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

            HStack {
                Spacer()
                Button {
                    completedStrokes.removeAll()
                    currentStroke.removeAll()
                } label: {
                    Label("Temizle", systemImage: "arrow.counterclockwise")
                        .font(AppFont.buttonLabel)
                        .foregroundStyle(AppColor.brandPrimary)
                        .frame(minHeight: AppSpacing.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .disabled(completedStrokes.isEmpty && currentStroke.isEmpty)
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
            for stroke in completedStrokes {
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
                    completedStrokes.append(currentStroke)
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

#if DEBUG
#Preview("SignatureCanvas") {
    VStack(spacing: AppSpacing.xl) {
        SignatureCanvas(title: "Teknisyen İmzası",
                        subtitle: "Ahmet Yılmaz")
        SignatureCanvas(title: "Müşteri İmzası",
                        subtitle: "Mehmet Kaya (ABC Market)")
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
