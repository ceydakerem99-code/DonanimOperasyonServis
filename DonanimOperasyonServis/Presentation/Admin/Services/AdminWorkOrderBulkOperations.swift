import Foundation

enum AdminWorkOrderBulkOperations {
    static func delete(
        orderIds: [WorkOrderID],
        ordersByID: [WorkOrderID: WorkOrder],
        actor: User,
        service: AdminWorkOrderService,
        at now: Date = Date()
    ) async -> BulkWorkOrderMutationResult {
        await apply(orderIds: orderIds, ordersByID: ordersByID, actor: actor) { orderId in
            try await service.deleteWithSync(actor: actor, orderId: orderId, at: now)
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

            guard WorkOrderBulkMutationPolicy.supportsBulkDelete(order) else {
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
            return error.adminMessage
        }
        if order.status == .completed {
            return DomainError.workOrderLocked(order.id).adminMessage
        }
        return "Silme başarısız."
    }
}
