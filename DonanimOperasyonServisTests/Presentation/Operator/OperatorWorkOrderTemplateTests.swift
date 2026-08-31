import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class OperatorWorkOrderTemplateTests: XCTestCase {

    private var container: DIContainer!
    private var deps: OperatorDependencies!
    private var operatorUser: User!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeOperatorDependencies()
        operatorUser = DomainFixtures.operatorUser()
        OperatorWorkOrderTemplateService.resetDefaultsSeed(for: operatorUser.id)
        try await deps.userRepository.save(operatorUser)
    }

    func testTemplateListSeedsDefaultsWhenEmpty() async throws {
        let listVM = WorkOrderTemplateListViewModel(
            actor: operatorUser,
            service: deps.workOrderTemplateService
        )
        await listVM.load()

        XCTAssertEqual(listVM.phase, .loaded)
        XCTAssertFalse(listVM.templates.isEmpty)
        XCTAssertTrue(listVM.templates.contains { $0.name == "POS Bakım" })
    }

    func testCreateEditDeleteTemplate() async throws {
        let created = try await deps.workOrderTemplateService.create(
            actor: operatorUser,
            name: "Özel Kurulum",
            summary: "Test şablonu",
            workType: .installation,
            deviceCategory: .tablet,
            deviceBrand: "Apple",
            deviceModel: "iPad",
            issueDescription: "Kurulum notu",
            priority: .high
        )

        var fetched = try await deps.workOrderTemplateService.fetch(actor: operatorUser, id: created.id)
        XCTAssertEqual(fetched.name, "Özel Kurulum")
        XCTAssertEqual(fetched.workType, .installation)

        fetched.summary = "Güncellendi"
        fetched.priority = .urgent
        let updated = try await deps.workOrderTemplateService.update(actor: operatorUser, template: fetched)
        XCTAssertEqual(updated.summary, "Güncellendi")
        XCTAssertEqual(updated.priority, .urgent)

        try await deps.workOrderTemplateService.delete(actor: operatorUser, id: created.id)
        do {
            _ = try await deps.workOrderTemplateService.fetch(actor: operatorUser, id: created.id)
            XCTFail("deleted template should not be found")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testDuplicateTemplate() async throws {
        let original = try await deps.workOrderTemplateService.create(
            actor: operatorUser,
            name: "POS Teslim",
            summary: nil,
            workType: .delivery,
            deviceCategory: .pos,
            deviceBrand: nil,
            deviceModel: nil,
            issueDescription: "Teslim",
            priority: .normal
        )

        let copy = try await deps.workOrderTemplateService.duplicate(actor: operatorUser, id: original.id)
        XCTAssertEqual(copy.workType, original.workType)
        XCTAssertEqual(copy.deviceCategory, original.deviceCategory)
        XCTAssertTrue(copy.name.contains("Kopya"))
        XCTAssertNotEqual(copy.id, original.id)
    }

    func testTemplateSelectionPopulatesWizard() async throws {
        let template = try await deps.workOrderTemplateService.create(
            actor: operatorUser,
            name: "Wizard Şablon",
            summary: "Wizard test",
            workType: .maintenance,
            deviceCategory: .pos,
            deviceBrand: "Ingenico",
            deviceModel: "iWL",
            issueDescription: "Periyodik bakım",
            priority: .high
        )

        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser()
        try await deps.customerRepository.save(customer)
        try await deps.userRepository.save(technician)

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.draft.customer = customer
        vm.draft.technician = technician
        vm.draft.serialNumber = "SN-KEEP"
        let originalDate = vm.draft.scheduledDate

        vm.applyTemplate(template)

        XCTAssertEqual(vm.draft.workType, .maintenance)
        XCTAssertEqual(vm.draft.deviceCategory, .pos)
        XCTAssertEqual(vm.draft.deviceBrand, "Ingenico")
        XCTAssertEqual(vm.draft.deviceModel, "iWL")
        XCTAssertEqual(vm.draft.issueDescription, "Periyodik bakım")
        XCTAssertEqual(vm.draft.priority, .high)
        XCTAssertEqual(vm.appliedTemplateName, "Wizard Şablon")
    }

    func testCustomerTechnicianDateNotOverriddenByTemplate() async throws {
        let template = try await deps.workOrderTemplateService.create(
            actor: operatorUser,
            name: "Koruma Testi",
            summary: nil,
            workType: .repair,
            deviceCategory: .printer,
            deviceBrand: "Epson",
            deviceModel: "TM-T88",
            issueDescription: "Arıza",
            priority: .urgent
        )

        let customer = DomainFixtures.customer(id: CustomerID("cust-template-guard"), createdByUserId: operatorUser.id)
        let technician = DomainFixtures.technicianUser(id: UserID("tech-template-guard"))
        try await deps.customerRepository.save(customer)
        try await deps.userRepository.save(technician)

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.draft.customer = customer
        vm.draft.technician = technician
        vm.draft.serialNumber = "SN-GUARD"
        let scheduledDate = Date(timeIntervalSince1970: 1_800_000_000)
        vm.draft.scheduledDate = scheduledDate
        vm.draft.scheduledStart = scheduledDate.addingTimeInterval(3600)
        vm.draft.scheduledEnd = scheduledDate.addingTimeInterval(7200)

        vm.applyTemplate(template)

        XCTAssertEqual(vm.draft.customer?.id, customer.id)
        XCTAssertEqual(vm.draft.technician?.id, technician.id)
        XCTAssertEqual(vm.draft.serialNumber, "SN-GUARD")
        XCTAssertEqual(vm.draft.scheduledDate.timeIntervalSince1970, scheduledDate.timeIntervalSince1970, accuracy: 1)
    }

    func testOfflineTemplateSelection() async throws {
        let reachability = FakeNetworkReachability(isReachable: false)
        let offlineDeps = makeDependencies(reachability: reachability)

        let listVM = WorkOrderTemplateListViewModel(
            actor: operatorUser,
            service: offlineDeps.workOrderTemplateService
        )
        await listVM.load()
        XCTAssertEqual(listVM.phase, .loaded)

        guard let template = listVM.templates.first else {
            XCTFail("expected seeded template")
            return
        }

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: offlineDeps)
        vm.applyTemplate(template)
        XCTAssertEqual(vm.draft.workType, template.workType)
    }

    func testEmptyTemplateStateAfterDeleteAll() async throws {
        var templates = try await deps.workOrderTemplateService.list(actor: operatorUser)
        for template in templates {
            try await deps.workOrderTemplateService.delete(actor: operatorUser, id: template.id)
        }

        let listVM = WorkOrderTemplateListViewModel(
            actor: operatorUser,
            service: deps.workOrderTemplateService
        )
        await listVM.load()
        XCTAssertEqual(listVM.phase, .empty)
    }

    func testInvalidDeletedTemplateHandling() async throws {
        let template = try await deps.workOrderTemplateService.create(
            actor: operatorUser,
            name: "Silinecek",
            summary: nil,
            workType: .maintenance,
            deviceCategory: .pos,
            deviceBrand: nil,
            deviceModel: nil,
            issueDescription: nil,
            priority: .normal
        )

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.applyTemplate(template)
        try await deps.workOrderTemplateService.delete(actor: operatorUser, id: template.id)

        await vm.validateAppliedTemplateAvailability()

        XCTAssertNil(vm.appliedTemplateName)
        XCTAssertNotNil(vm.templateUnavailableMessage)
    }

    func testTemplateListDoesNotNPlusOneFetch() async throws {
        OperatorWorkOrderTemplateService.resetDefaultsSeed(for: operatorUser.id)
        let countingRepo = CountingWorkOrderTemplateRepository(
            inner: container.workOrderTemplateRepository
        )
        let service = OperatorWorkOrderTemplateService(repository: countingRepo)
        UserDefaults.standard.set(true, forKey: "workOrderTemplateDefaultsSeeded.\(operatorUser.id.rawValue)")
        _ = try await service.create(
            actor: operatorUser,
            name: "N+1 Test",
            summary: nil,
            workType: .maintenance,
            deviceCategory: .pos,
            deviceBrand: nil,
            deviceModel: nil,
            issueDescription: nil,
            priority: .normal
        )

        let listBefore = await countingRepo.listCallCount
        _ = try await service.list(actor: operatorUser)
        let listAfter = await countingRepo.listCallCount
        XCTAssertEqual(listAfter, listBefore + 1)
    }

    private func makeDependencies(reachability: NetworkReachabilityProviding) -> OperatorDependencies {
        let base = container.makeOperatorDependencies()
        return OperatorDependencies(
            getWorkOrders: base.getWorkOrders,
            getWorkOrder: base.getWorkOrder,
            workOrderService: base.workOrderService,
            customerService: base.customerService,
            workOrderTemplateService: base.workOrderTemplateService,
            customerRepository: base.customerRepository,
            userRepository: base.userRepository,
            localDirectoryCacheRefresh: base.localDirectoryCacheRefresh,
            workOrderNoteRepository: base.workOrderNoteRepository,
            workOrderPhotoRepository: base.workOrderPhotoRepository,
            workOrderLocationRepository: base.workOrderLocationRepository,
            signatureRepository: base.signatureRepository,
            statusHistoryRepository: base.statusHistoryRepository,
            editRequestRepository: base.editRequestRepository,
            editRequestService: base.editRequestService,
            customerSatisfactionRepository: base.customerSatisfactionRepository,
            customerSatisfactionService: base.customerSatisfactionService,
            notificationRepository: base.notificationRepository,
            syncOperationRepository: base.syncOperationRepository,
            syncConflictRepository: base.syncConflictRepository,
            conflictResolver: base.conflictResolver,
            networkReachability: reachability,
            profileAccountService: base.profileAccountService,
            storageDataSource: base.storageDataSource
        )
    }
}

private actor CountingWorkOrderTemplateRepository: WorkOrderTemplateRepository {
    let inner: any WorkOrderTemplateRepository
    private(set) var listCallCount = 0

    init(inner: any WorkOrderTemplateRepository) { self.inner = inner }

    func fetch(id: WorkOrderTemplateID) async throws -> WorkOrderTemplate {
        try await inner.fetch(id: id)
    }

    func list(createdByUserId: UserID) async throws -> [WorkOrderTemplate] {
        listCallCount += 1
        return try await inner.list(createdByUserId: createdByUserId)
    }

    func save(_ template: WorkOrderTemplate) async throws {
        try await inner.save(template)
    }

    func delete(id: WorkOrderTemplateID) async throws {
        try await inner.delete(id: id)
    }
}
