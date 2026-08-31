import SwiftUI

/// Presents cache-first async content with a delayed blocking spinner.
struct AsyncLoadContainerView<Content: View, Empty: View>: View {
    let isLoading: Bool
    let showsLoadingIndicator: Bool
    let hasCachedContent: Bool
    let errorMessage: String?
    let isEmpty: Bool
    var loadingMessage: String = "Yükleniyor..."
    var errorTitle: String = "Yüklenemedi"
    var onRetry: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let empty: () -> Empty

    var body: some View {
        Group {
            if let errorMessage, !hasCachedContent {
                ErrorBanner(title: errorTitle, message: errorMessage, onRetry: onRetry)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if hasCachedContent || (!isLoading && !isEmpty) {
                content()
            } else if isEmpty && !isLoading {
                empty()
            } else if isLoading && showsLoadingIndicator {
                LoadingView(message: loadingMessage)
            } else {
                Color.clear
                    .frame(minHeight: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension AsyncLoadContainerView where Empty == EmptyView {
    init(
        isLoading: Bool,
        showsLoadingIndicator: Bool,
        hasCachedContent: Bool,
        errorMessage: String?,
        isEmpty: Bool,
        loadingMessage: String = "Yükleniyor...",
        errorTitle: String = "Yüklenemedi",
        onRetry: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.showsLoadingIndicator = showsLoadingIndicator
        self.hasCachedContent = hasCachedContent
        self.errorMessage = errorMessage
        self.isEmpty = isEmpty
        self.loadingMessage = loadingMessage
        self.errorTitle = errorTitle
        self.onRetry = onRetry
        self.content = content
        self.empty = { EmptyView() }
    }
}
