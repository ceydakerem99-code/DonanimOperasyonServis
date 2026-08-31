import Foundation
import Observation

/// Shared async load lifecycle: generation tracking, delayed loading indicator,
/// and cancellation settlement compatible with `AsyncLoadSettlement`.
@Observable
@MainActor
final class AsyncLoadSession {
    /// Delay before showing a blocking spinner when no cached content exists.
    static var indicatorDelay: Duration = .milliseconds(400)

    private(set) var loadGeneration = 0
    private(set) var showsLoadingIndicator = false
    private var indicatorDelayTask: Task<Void, Never>?

    struct Context: Sendable {
        let generation: Int
        let hadCachedContentAtStart: Bool
    }

    func start(hadCachedContent: Bool) -> Context {
        loadGeneration &+= 1
        let generation = loadGeneration
        cancelIndicatorDelay()
        showsLoadingIndicator = false

        if !hadCachedContent {
            indicatorDelayTask = Task { [weak self] in
                try? await Task.sleep(for: Self.indicatorDelay)
                guard !Task.isCancelled else { return }
                guard let self, generation == self.loadGeneration else { return }
                self.showsLoadingIndicator = true
            }
        }

        return Context(generation: generation, hadCachedContentAtStart: hadCachedContent)
    }

    func isCurrent(_ generation: Int) -> Bool {
        generation == loadGeneration
    }

    func finish(generation: Int) {
        guard generation == loadGeneration else { return }
        cancelIndicatorDelay()
        showsLoadingIndicator = false
    }

    func settleCancelledLoad<Phase: Equatable>(
        context: Context,
        phase: Phase,
        loadingPhase: Phase,
        loadedPhase: Phase,
        emptyPhase: Phase
    ) -> Phase? {
        finish(generation: context.generation)
        return AsyncLoadSettlement.settleCancelledLoad(
            generation: context.generation,
            currentGeneration: loadGeneration,
            phase: phase,
            loadingPhase: loadingPhase,
            hadCachedContentAtStart: context.hadCachedContentAtStart,
            loadedPhase: loadedPhase,
            emptyPhase: emptyPhase
        )
    }

    private func cancelIndicatorDelay() {
        indicatorDelayTask?.cancel()
        indicatorDelayTask = nil
    }
}

enum AsyncLoadPhaseParsing {
    static func errorMessage<Phase>(_ phase: Phase) -> String? {
        let mirror = Mirror(reflecting: phase)
        guard mirror.displayStyle == .enum,
              let first = mirror.children.first,
              first.label == "error",
              let message = first.value as? String
        else { return nil }
        return message
    }
}
