import Foundation

enum WorkOrderTemplateDefaults {

    static func templates(for userId: UserID, at now: Date) -> [WorkOrderTemplate] {

        [
            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-pos-maintenance"),
                name: "POS Bakım",
                summary: "Periyodik POS bakım işleri",
                workType: .maintenance,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "Move 5000",
                issueDescription: "Periyodik bakım ve kontrol",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-pos-installation"),
                name: "POS Kurulum",
                summary: "Yeni POS cihaz kurulumu",
                workType: .installation,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "Desk 5000",
                issueDescription: "Yeni kurulum ve aktivasyon",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-pos-repair"),
                name: "POS Arıza",
                summary: "Acil POS arıza müdahalesi",
                workType: .repair,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "Move 5000",
                issueDescription: "Arıza bildirimi ve müdahale",
                priority: .urgent,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-pos-software"),
                name: "POS Yazılım Güncelleme",
                summary: "POS yazılım güncelleme işlemi",
                workType: .maintenance,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "Desk 5000",
                issueDescription: "Yazılım sürüm kontrolü ve güncelleme",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-pos-network"),
                name: "POS Bağlantı Sorunu",
                summary: "POS internet ve bağlantı problemi",
                workType: .repair,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "Move 5000",
                issueDescription: "POS ağ bağlantısının kontrol edilmesi",
                priority: .urgent,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-pos-printer"),
                name: "POS Yazıcı Sorunu",
                summary: "POS fiş yazdırma problemi",
                workType: .repair,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "Move 5000",
                issueDescription: "Termal yazıcı ve fiş yazdırma kontrolü",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-pos-activation"),
                name: "POS Aktivasyon",
                summary: "POS cihaz aktivasyon işlemi",
                workType: .installation,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "Desk 5000",
                issueDescription: "Cihaz aktivasyonu ve test işlemleri",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-pos-terminal-change"),
                name: "POS Terminal Değişimi",
                summary: "Arızalı POS terminalinin değiştirilmesi",
                workType: .repair,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "Move 5000",
                issueDescription: "Arızalı terminalin yeni terminal ile değiştirilmesi",
                priority: .urgent,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            )
        ]
    }
}
