import Foundation

enum OperatorWorkOrderBulkOperations {
    static func assignTechnician(
        orderIds: [WorkOrderID],
        ordersByID: [WorkOrderID: WorkOrder],
        technicianId: UserID,
        actor: User,
        service: OperatorWorkOrderService,
        at now: Date = Date()
    ) async -> BulkWorkOrderMutationResult {
        await apply(orderIds: orderIds, ordersByID: ordersByID, actor: actor) { orderId in
            _ = try await service.assignWithSync(
                actor: actor,
                orderId: orderId,
                newTechnicianId: technicianId,
                at: now
            )
        }
    }

    static func updatePriority(
        orderIds: [WorkOrderID],
        ordersByID: [WorkOrderID: WorkOrder],
        priority: WorkOrderPriority,
        actor: User,
        service: OperatorWorkOrderService,
        at now: Date = Date()
    ) async -> BulkWorkOrderMutationResult {
        await apply(orderIds: orderIds, ordersByID: ordersByID, actor: actor) { orderId in
            _ = try await service.updatePlanningWithSync(
                actor: actor,
                orderId: orderId,
                update: WorkOrderPlanningUpdate(priority: priority),
                at: now
            )
        }
    }

    static func updateSchedule(
        orderIds: [WorkOrderID],
        ordersByID: [WorkOrderID: WorkOrder],
        scheduledDate: Date,
        scheduledTimeRange: ScheduledTimeRange?,
        actor: User,
        service: OperatorWorkOrderService,
        at now: Date = Date()
    ) async -> BulkWorkOrderMutationResult {
        await apply(orderIds: orderIds, ordersByID: ordersByID, actor: actor) { orderId in
            _ = try await service.updatePlanningWithSync(
                actor: actor,
                orderId: orderId,
                update: WorkOrderPlanningUpdate(
                    scheduledDate: scheduledDate,
                    scheduledTimeRange: scheduledTimeRange
                ),
                at: now
            )
        }
    }

    private static func apply(
        orderIds: [WorkOrderID],
        ordersByID: [WorkOrderID: WorkOrder],
        actor: User,
        mutation: (WorkOrderID) async throws -> Void
    ) async -> BulkWorkOrderMutationResult {
        var result = BulkWorkOrderMutationResult()
        var processed = Set<WorkOrderID>()

        for orderId in orderIds {
            guard processed.insert(orderId).inserted else { continue }
            guard let order = ordersByID[orderId] else {
                result.failures.append(
                    BulkWorkOrderMutationFailure(
                        orderId: orderId,
                        workOrderNumber: orderId.rawValue,
                        reason: "İş emri bulunamadı."
                    )
                )
                continue
            }

            guard WorkOrderBulkMutationPolicy.supportsBulkPlanningMutation(order) else {
                result.failures.append(
                    BulkWorkOrderMutationFailure(
                        orderId: order.id,
                        workOrderNumber: order.workOrderNumber,
                        reason: failureMessage(for: order, error: nil)
                    )
                )
                continue
            }

            do {
                try await mutation(orderId)
                result.succeeded.append(orderId)
            } catch {
                result.failures.append(
                    BulkWorkOrderMutationFailure(
                        orderId: order.id,
                        workOrderNumber: order.workOrderNumber,
                        reason: failureMessage(for: order, error: error)
                    )
                )
            }
        }

        return result
    }

    private static func failureMessage(for order: WorkOrder, error: Error?) -> String {
        if let error = error as? DomainError {
            return error.operatorMessage
        }
        if order.isLocked {
            return DomainError.workOrderLocked(order.id).operatorMessage
        }
        if order.status.isTerminal {
            return "Tamamlanan veya reddedilen iş emirleri güncellenemez."
        }
        return "Güncelleme başarısız."
    }
}
