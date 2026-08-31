import SwiftUI

/// Live connection badge driven by shared `NetworkReachabilityProviding`.
/// Reflects DEBUG simulated offline via `DebuggableNetworkReachability.isReachable`.
struct ConnectionStatusIndicator: View {
    @Environment(\.diContainer) private var container
    @State private var isOnline = true

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(isOnline ? AppColor.success : AppColor.secondaryText)
                .frame(width: 8, height: 8)
            Text(isOnline ? "Çevrimiçi" : "Çevrimdışı")
                .font(AppFont.label)
                .foregroundStyle(AppColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isOnline ? "Çevrimiçi" : "Çevrimdışı")
        .task {
            isOnline = await container.networkReachability.isReachable
            let stream = await container.networkReachability.reachabilityUpdates()
            for await reachable in stream {
                isOnline = reachable
            }
        }
    }
}

#if DEBUG
#Preview {
    ConnectionStatusIndicator()
        .environment(\.diContainer, DIContainer.mock())
        .padding()
}
#endif
