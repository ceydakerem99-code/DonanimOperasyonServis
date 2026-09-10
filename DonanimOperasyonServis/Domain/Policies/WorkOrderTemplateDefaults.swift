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
,
            
            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-tablet-maintenance"),
                name: "Tablet Bakım",
                summary: "Tablet periyodik bakım ve kontrolü",
                workType: .maintenance,
                deviceCategory: .tablet,
                deviceBrand: "Samsung",
                deviceModel: "Galaxy Tab",
                issueDescription: "Tablet genel bakım ve donanım kontrolü",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-printer-repair"),
                name: "Yazıcı Arızası",
                summary: "Yazıcı arıza tespit ve müdahalesi",
                workType: .repair,
                deviceCategory: .printer,
                deviceBrand: "HP",
                deviceModel: "LaserJet",
                issueDescription: "Yazdırma problemi ve donanım kontrolü",
                priority: .high,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-barcode-installation"),
                name: "Barkod Okuyucu Kurulum",
                summary: "Yeni barkod okuyucu kurulumu",
                workType: .installation,
                deviceCategory: .barcodeScanner,
                deviceBrand: "Zebra",
                deviceModel: "DS2208",
                issueDescription: "Barkod okuyucu kurulumu ve bağlantı testi",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-computer-repair"),
                name: "Bilgisayar Arızası",
                summary: "Bilgisayar arıza tespit ve müdahalesi",
                workType: .repair,
                deviceCategory: .computer,
                deviceBrand: "Dell",
                deviceModel: "OptiPlex",
                issueDescription: "Bilgisayar donanım arızasının tespiti ve giderilmesi",
                priority: .urgent,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-cash-register-maintenance"),
                name: "Kasa Bakımı",
                summary: "Kasa sistemi periyodik bakım işlemi",
                workType: .maintenance,
                deviceCategory: .cashRegister,
                deviceBrand: "NCR",
                deviceModel: "POS Kasa",
                issueDescription: "Kasa sistemi genel bakım ve kontrolü",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-tablet-installation"),
                name: "Tablet Kurulum",
                summary: "Yeni tablet cihaz kurulumu",
                workType: .installation,
                deviceCategory: .tablet,
                deviceBrand: "Samsung",
                deviceModel: "Galaxy Tab",
                issueDescription: "Tablet kurulumu, yapılandırma ve test işlemleri",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            ),

            WorkOrderTemplate(
                id: WorkOrderTemplateID("template-default-printer-maintenance"),
                name: "Yazıcı Bakım",
                summary: "Yazıcı periyodik bakım işlemi",
                workType: .maintenance,
                deviceCategory: .printer,
                deviceBrand: "HP",
                deviceModel: "LaserJet",
                issueDescription: "Yazıcı temizliği, bakım ve çıktı testi",
                priority: .normal,
                createdByUserId: userId,
                createdAt: now,
                updatedAt: now
            )        ]
    }
}
