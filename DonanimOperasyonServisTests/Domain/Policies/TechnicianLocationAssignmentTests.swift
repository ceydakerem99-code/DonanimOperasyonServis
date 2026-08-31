import XCTest
@testable import DonanimOperasyonServis

final class TechnicianLocationAssignmentTests: XCTestCase {
    private let site = LocationCoordinate(latitude: 41.0082, longitude: 28.9784)
    private let near = LocationCoordinate(latitude: 41.0100, longitude: 28.9800)
    private let far = LocationCoordinate(latitude: 41.1000, longitude: 29.0000)

    private let techNear = DomainFixtures.technicianUser(id: UserID("tech-near"), fullName: "Near Tech")
    private let techFar = DomainFixtures.technicianUser(id: UserID("tech-far"), fullName: "Far Tech")
    private let techBusyNear = DomainFixtures.technicianUser(id: UserID("tech-busy-near"), fullName: "Busy Near")
    private let customer = DomainFixtures.customer()

    func testTechnicianDistanceFromWorkOrder() {
        let meters = near.distanceMeters(to: site)
        XCTAssertGreaterThan(meters, 200)
        XCTAssertLessThan(meters, 400)
        XCTAssertEqual(site.formattedDistance(to: near), String(format: "%.0f m", meters))
        XCTAssertTrue(far.formattedDistance(to: site).contains("km"))
    }

    func testTechniciansSortedByDistanceAfterStatusAndWorkload() {
        let orders: [WorkOrder] = []
        let context = makeContext(
            technicians: [techFar, techNear],
            locations: [
                location(for: techNear.id, coordinate: near),
                location(for: techFar.id, coordinate: far)
            ]
        )

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [techFar, techNear],
            orders: orders,
            locationContext: context
        )
        XCTAssertEqual(sorted.map(\.id), [techNear.id, techFar.id])
    }

    func testMissingWorkOrderLocationFallsBackToExistingAssignmentOrder() {
        let orders = [
            DomainFixtures.workOrder(
                assignedTechnicianId: techNear.id,
                customerId: customer.id,
                status: .assigned
            )
        ]
        let withoutLocation = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [techFar, techNear],
            orders: orders,
            locationContext: nil
        )
        let withUnknownSite = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [techFar, techNear],
            orders: orders,
            locationContext: TechnicianAssignmentLocationContext(workOrderSite: nil, technicianLocations: [:])
        )
        XCTAssertEqual(withoutLocation.map(\.id), withUnknownSite.map(\.id))
    }

    func testMissingTechnicianLocationDoesNotBreakAssignment() {
        let context = TechnicianAssignmentLocationContext(
            workOrderSite: site,
            technicianLocations: [
                techNear.id: TechnicianLocationInfo(
                    coordinate: near,
                    capturedAt: Date(),
                    freshness: .current
                )
            ]
        )
        XCTAssertEqual(context.displayLabel(for: techFar.id), "Konum bilinmiyor")
        XCTAssertEqual(context.assignmentLocationLabel(for: techFar.id), "Konum bilinmiyor")
        XCTAssertNil(context.sortableDistanceMeters(for: techFar.id))

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [techFar, techNear],
            orders: [],
            locationContext: context
        )
        XCTAssertEqual(sorted.first?.id, techNear.id)
    }

    func testAssignmentLocationLabelWithoutWorkOrderSite() {
        let context = TechnicianAssignmentLocationContext(
            workOrderSite: nil,
            technicianLocations: [
                techNear.id: TechnicianLocationInfo(
                    coordinate: near,
                    capturedAt: Date(),
                    freshness: .current
                )
            ]
        )
        XCTAssertEqual(context.assignmentLocationLabel(for: techNear.id), "Konum mevcut")
        XCTAssertEqual(context.assignmentLocationLabel(for: techFar.id), "Konum bilinmiyor")
    }

    func testBulkAssignmentSiteResolutionUsesPrimarySelectedOrder() {
        let orderA = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-site-a"),
            customerId: customer.id,
            scheduledDate: DomainFixtures.referenceDate.addingTimeInterval(-86_400)
        )
        let orderB = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-site-b"),
            workOrderNumber: "WO-SITE-B",
            customerId: CustomerID("other-customer"),
            scheduledDate: DomainFixtures.referenceDate
        )
        let locations: [WorkOrderID: [WorkOrderLocation]] = [
            orderB.id: [
                WorkOrderLocation(
                    id: "site-b",
                    workOrderId: orderB.id,
                    event: .arrived,
                    coordinate: site,
                    capturedByUserId: techNear.id,
                    capturedAt: Date()
                )
            ]
        ]

        let resolved = TechnicianAssignmentLocationBuilder.resolveBulkAssignmentSite(
            selectedOrders: [orderA, orderB],
            locationsByWorkOrderId: locations
        )
        XCTAssertEqual(resolved, site)
    }

    func testStaleTechnicianLocationIsNotTreatedAsCurrent() {
        let staleDate = Date().addingTimeInterval(-5 * 3600)
        let context = TechnicianAssignmentLocationContext(
            workOrderSite: site,
            technicianLocations: [
                techNear.id: TechnicianLocationInfo(
                    coordinate: near,
                    capturedAt: staleDate,
                    freshness: .stale
                )
            ]
        )
        XCTAssertEqual(context.displayLabel(for: techNear.id), "Konum güncel değil")
        XCTAssertNil(context.sortableDistanceMeters(for: techNear.id))
    }

    func testRecommendedTechnicianCombinesDistanceAndWorkload() {
        let lowLoadNear = DomainFixtures.technicianUser(id: UserID("tech-low-near"), fullName: "Low Near")
        let lowLoadFar = DomainFixtures.technicianUser(id: UserID("tech-low-far"), fullName: "Low Far")
        let orders = [
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-near"),
                assignedTechnicianId: lowLoadNear.id,
                customerId: customer.id,
                priority: .normal,
                status: .assigned
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-far"),
                assignedTechnicianId: lowLoadFar.id,
                customerId: customer.id,
                priority: .normal,
                status: .assigned
            )
        ]
        let context = makeContext(
            technicians: [lowLoadFar, lowLoadNear],
            locations: [
                location(for: lowLoadNear.id, coordinate: near),
                location(for: lowLoadFar.id, coordinate: far)
            ]
        )

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [lowLoadFar, lowLoadNear],
            orders: orders,
            locationContext: context
        )
        XCTAssertEqual(sorted.first?.id, lowLoadNear.id)

        let recommended = TechnicianAssignmentSupport.recommendedTechnicianIDs(
            from: [lowLoadFar, lowLoadNear],
            orders: orders,
            locationContext: context
        )
        XCTAssertTrue(recommended.contains(lowLoadNear.id))
    }

    func testLocationDoesNotOverrideAvailabilityPriority() {
        let orders = [
            DomainFixtures.workOrder(
                assignedTechnicianId: techBusyNear.id,
                customerId: customer.id,
                status: .inProgress
            )
        ]
        let context = makeContext(
            technicians: [techBusyNear, techFar],
            locations: [
                location(for: techBusyNear.id, coordinate: near),
                location(for: techFar.id, coordinate: far)
            ]
        )

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [techBusyNear, techFar],
            orders: orders,
            locationContext: context
        )
        XCTAssertEqual(sorted.first?.id, techFar.id)
    }

    func testNoNPlusOneLocationFetches() async {
        let repo = CountingLocationRepository(
            seed: [
                location(for: techNear.id, workOrderId: WorkOrderID("wo-1"), coordinate: near),
                location(for: techFar.id, workOrderId: WorkOrderID("wo-2"), coordinate: far)
            ]
        )
        _ = await TechnicianAssignmentLocationLoader.loadLocations(
            for: [WorkOrderID("wo-1"), WorkOrderID("wo-2"), WorkOrderID("wo-3")],
            repository: repo
        )
        let callCount = await repo.listCallCount
        XCTAssertEqual(callCount, 3)
    }

    func testLocationPermissionDeniedKeepsAssignmentWorking() {
        let orders = [
            DomainFixtures.workOrder(
                assignedTechnicianId: techBusyNear.id,
                customerId: customer.id,
                status: .inProgress
            )
        ]
        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [techBusyNear, techFar],
            orders: orders,
            locationContext: nil
        )
        XCTAssertEqual(sorted.first?.id, techFar.id)
    }

    func testOfflineUsesCachedLocation() async {
        let repo = InMemoryLocationRepository(seed: [
            location(for: techNear.id, workOrderId: WorkOrderID("wo-cache"), coordinate: near)
        ])
        let loaded = await TechnicianAssignmentLocationLoader.loadLocations(
            for: [WorkOrderID("wo-cache")],
            repository: repo
        )
        let siteCoordinate = TechnicianAssignmentLocationBuilder.resolveWorkOrderSite(
            customerId: customer.id,
            workOrderId: WorkOrderID("wo-cache"),
            orders: [
                DomainFixtures.workOrder(
                    id: WorkOrderID("wo-cache"),
                    customerId: customer.id,
                    status: .assigned
                )
            ],
            locationsByWorkOrderId: loaded
        )
        XCTAssertEqual(siteCoordinate, near)
    }

    func testResolveWorkOrderSitePrefersTargetWorkOrderLocation() {
        let workOrderId = WorkOrderID("wo-target")
        let customerOrderId = WorkOrderID("wo-other")
        let locations: [WorkOrderID: [WorkOrderLocation]] = [
            workOrderId: [location(for: techNear.id, workOrderId: workOrderId, coordinate: near)],
            customerOrderId: [location(for: techFar.id, workOrderId: customerOrderId, coordinate: far)]
        ]
        let siteCoordinate = TechnicianAssignmentLocationBuilder.resolveWorkOrderSite(
            customerId: customer.id,
            workOrderId: workOrderId,
            orders: [
                DomainFixtures.workOrder(id: workOrderId, customerId: customer.id),
                DomainFixtures.workOrder(id: customerOrderId, customerId: customer.id)
            ],
            locationsByWorkOrderId: locations
        )
        XCTAssertEqual(siteCoordinate, near)
    }

    func testBuilderMarksFreshAndStaleLocations() {
        let now = Date()
        let fresh = location(
            for: techNear.id,
            coordinate: near,
            capturedAt: now.addingTimeInterval(-1800)
        )
        let stale = location(
            for: techFar.id,
            coordinate: far,
            capturedAt: now.addingTimeInterval(-5 * 3600)
        )
        let context = TechnicianAssignmentLocationBuilder.buildContext(
            workOrderSite: site,
            technicians: [techNear, techFar],
            locationsByWorkOrderId: [
                WorkOrderID("wo-1"): [fresh],
                WorkOrderID("wo-2"): [stale]
            ],
            now: now
        )
        XCTAssertEqual(context.locationInfo(for: techNear.id)?.freshness, .current)
        XCTAssertEqual(context.locationInfo(for: techFar.id)?.freshness, .stale)
    }

    private func makeContext(
        technicians: [User],
        locations: [WorkOrderLocation]
    ) -> TechnicianAssignmentLocationContext {
        var byOrder: [WorkOrderID: [WorkOrderLocation]] = [:]
        for location in locations {
            byOrder[location.workOrderId, default: []].append(location)
        }
        return TechnicianAssignmentLocationBuilder.buildContext(
            workOrderSite: site,
            technicians: technicians,
            locationsByWorkOrderId: byOrder
        )
    }

    private func location(
        for technicianId: UserID,
        workOrderId: WorkOrderID = WorkOrderID("wo-loc"),
        coordinate: LocationCoordinate,
        capturedAt: Date = Date()
    ) -> WorkOrderLocation {
        WorkOrderLocation(
            id: "\(workOrderId.rawValue)-\(technicianId.rawValue)",
            workOrderId: workOrderId,
            event: .enRoute,
            coordinate: coordinate,
            capturedByUserId: technicianId,
            capturedAt: capturedAt
        )
    }
}

actor CountingLocationRepository: WorkOrderLocationRepository {
    private let wrapped: InMemoryLocationRepository
    private(set) var listCallCount = 0

    init(seed: [WorkOrderLocation] = []) {
        self.wrapped = InMemoryLocationRepository(seed: seed)
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderLocation] {
        listCallCount += 1
        return try await wrapped.list(for: workOrderId)
    }

    func save(_ location: WorkOrderLocation) async throws {
        try await wrapped.save(location)
    }
}
