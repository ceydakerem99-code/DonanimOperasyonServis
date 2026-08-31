import Foundation
import Observation

@Observable
@MainActor
final class DailyOperationsReportViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var report: DailyOperationsReport?

    var selectedDay: Date

    private let actor: User
    private let dependencies: AdminDependencies
    private let asyncLoad = AsyncLoadSession()
    private let calendar: Calendar
    private var cachedOrders: [WorkOrder] = []
    private var customersById: [CustomerID: Customer] = [:]
    private var techniciansById: [UserID: User] = [:]
    private var activeTechnicians: [User] = []
    private var cachedHistories: [WorkOrderID: [WorkOrderStatusHistory]] = [:]
    private var loadCount = 0

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { report != nil }

    init(
        actor: User,
        dependencies: AdminDependencies,
        calendar: Calendar = .current
    ) {
        self.actor = actor
        self.dependencies = dependencies
        self.calendar = calendar
        self.selectedDay = calendar.startOfDay(for: Date())
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation

        do {
            let orders = try await dependencies.getSystemWorkOrders.execute(actor: actor)
            guard asyncLoad.isCurrent(generation) else { return }
            loadCount += 1
            cachedOrders = orders

            let customerList = try await dependencies.customerRepository.list(searchText: nil)
            guard asyncLoad.isCurrent(generation) else { return }
            customersById = Dictionary(uniqueKeysWithValues: customerList.map { ($0.id, $0) })

            techniciansById = await loadTechnicians(from: orders)
            guard asyncLoad.isCurrent(generation) else { return }

            if let technicians = try? await dependencies.userRepository.list(role: .technician, isActive: nil) {
                activeTechnicians = technicians
            }

            cachedHistories = await loadStatusHistories(for: orders.map(\.id))
            guard asyncLoad.isCurrent(generation) else { return }

            applyReport()
        } catch is CancellationError {
            if let settled = asyncLoad.settleCancelledLoad(
                context: context,
                phase: phase,
                loadingPhase: Phase.loading,
                loadedPhase: Phase.ready,
                emptyPhase: Phase.empty
            ) {
                phase = settled
            }
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.adminMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Günlük operasyon raporu yüklenemedi.")
        }
    }

    func selectPreviousDay() {
        guard let previous = calendar.date(byAdding: .day, value: -1, to: selectedDay) else { return }
        selectedDay = calendar.startOfDay(for: previous)
        applyReport()
    }

    func selectNextDay() {
        guard let next = calendar.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        selectedDay = calendar.startOfDay(for: next)
        applyReport()
    }

    func selectDay(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        applyReport()
    }

    var remoteLoadCount: Int { loadCount }

    private func applyReport() {
        let built = DailyOperationsAggregator.buildReport(
            selectedDay: selectedDay,
            orders: cachedOrders,
            customers: customersById,
            technicians: techniciansById,
            activeTechnicians: activeTechnicians,
            statusHistories: cachedHistories,
            calendar: calendar
        )
        report = built
        phase = built.isEmpty ? .empty : .ready
    }

    private func loadTechnicians(from orders: [WorkOrder]) async -> [UserID: User] {
        var result: [UserID: User] = [:]
        if let technicians = try? await dependencies.userRepository.list(role: .technician, isActive: nil) {
            for tech in technicians { result[tech.id] = tech }
        }
        for techId in Set(orders.map(\.assignedTechnicianId)) where result[techId] == nil {
            if let tech = try? await dependencies.userRepository.fetch(id: techId) {
                result[techId] = tech
            }
        }
        return result
    }

    private func loadStatusHistories(for workOrderIds: [WorkOrderID]) async -> [WorkOrderID: [WorkOrderStatusHistory]] {
        guard !workOrderIds.isEmpty else { return [:] }
        return await withTaskGroup(of: (WorkOrderID, [WorkOrderStatusHistory]).self) { group in
            for id in workOrderIds {
                group.addTask {
                    let history = (try? await self.dependencies.statusHistoryRepository.list(for: id)) ?? []
                    return (id, history)
                }
            }
            var result: [WorkOrderID: [WorkOrderStatusHistory]] = [:]
            for await (id, history) in group {
                if !history.isEmpty {
                    result[id] = history
                }
            }
            return result
        }
    }
}

#if DEBUG
extension DailyOperationsReportViewModel {
    static func previewReady() -> DailyOperationsReportViewModel {
        let vm = DailyOperationsReportViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .ready
        vm.report = DailyOperationsReport(
            selectedDay: AdminPreviewData.referenceDate,
            kpis: DailyOperationsKPIs(
                openedCount: 3,
                completedCount: 2,
                inProgressCount: 1,
                pausedCount: 1,
                urgentCount: 1,
                delayedCount: 0,
                rejectedCount: 0,
                completionRate: 66,
                activeTechnicianCount: 4,
                assignedTechnicianCount: 2
            ),
            technicianSummaries: [],
            customerSummary: DailyCustomerOperationSummary(
                uniqueCustomerCount: 2,
                workTypeCounts: [.repair: 2],
                deviceCategoryCounts: [.pos: 2]
            ),
            workflowEntries: [],
            delayedEntries: [],
            pauseSummary: DailyPauseSummary(
                pausedCount: 0,
                reasonCounts: [:],
                averagePauseDurationSeconds: nil,
                entries: []
            )
        )
        return vm
    }
}
#endif
