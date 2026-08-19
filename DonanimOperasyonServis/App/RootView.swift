import SwiftUI

struct RootView: View {
    @Environment(\.diContainer) private var container

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.tint)

            Text("Donanım Operasyon ve Servis")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Faz 0 — proje iskeleti hazır.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .task {
            AppLogger.app.info("RootView appeared; DI container ready.")
            _ = container
        }
    }
}

#Preview {
    RootView()
        .environment(\.diContainer, .live())
}
