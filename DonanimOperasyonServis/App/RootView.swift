import SwiftUI

struct RootView: View {
    @Environment(\.diContainer) private var container

    var body: some View {
        VStack(spacing: AppSpacing.l) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(AppColor.brandPrimary)

            Text("Donanım Operasyon ve Servis")
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)
                .multilineTextAlignment(.center)

            Text("Faz 1 — Design System hazır.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.neutralBackground)
        .task {
            AppLogger.app.info("RootView appeared; DI container ready.")
            _ = container
        }
    }
}

#Preview {
    RootView()
        .environment(\.diContainer, .mock())
}
