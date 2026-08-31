import Foundation

/// Settles list/detail loading so a cancelled in-flight load cannot
/// leave the UI stuck on a spinner when no newer generation replaced it.
enum AsyncLoadSettlement {
    static func phaseAfterCancellation<Item>(
        currentPhaseIsLoading: Bool,
        itemsEmpty: Bool,
        loaded: Item,
        empty: Item
    ) -> Item? {
        guard currentPhaseIsLoading else { return nil }
        return itemsEmpty ? empty : loaded
    }

    /// Applies cancellation settlement for a specific load generation.
    /// Uses the content snapshot captured when the load started so a
    /// superseded task cannot skip settlement while `phase` is still loading.
    static func settleCancelledLoad<Phase: Equatable>(
        generation: Int,
        currentGeneration: Int,
        phase: Phase,
        loadingPhase: Phase,
        hadCachedContentAtStart: Bool,
        loadedPhase: Phase,
        emptyPhase: Phase
    ) -> Phase? {
        guard generation == currentGeneration else { return nil }
        return phaseAfterCancellation(
            currentPhaseIsLoading: phase == loadingPhase,
            itemsEmpty: !hadCachedContentAtStart,
            loaded: loadedPhase,
            empty: emptyPhase
        )
    }
}
