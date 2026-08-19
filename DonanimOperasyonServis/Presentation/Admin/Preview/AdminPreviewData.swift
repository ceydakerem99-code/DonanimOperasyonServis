#if DEBUG
import Foundation

enum AdminPreviewData {
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    static let adminUser = User(
        id: UserID("user-admin-preview"),
        email: "admin@example.com",
        fullName: "Admin Kullanıcı",
        role: .admin,
        phoneNumber: PhoneNumber("+905551112233"),
        isActive: true,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static let operatorUser = User(
        id: UserID("user-operator-preview"),
        email: "operator@example.com",
        fullName: "Mehmet Kaya",
        role: .operator,
        isActive: true,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static let technicianUser = User(
        id: UserID("user-tech-preview"),
        email: "ahmet@example.com",
        fullName: "Ahmet Yılmaz",
        role: .technician,
        isActive: true,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static let passiveUser = User(
        id: UserID("user-passive-preview"),
        email: "passive@example.com",
        fullName: "Pasif Kullanıcı",
        role: .technician,
        isActive: false,
        createdAt: referenceDate,
        updatedAt: referenceDate
    )

    static func users() -> [User] {
        [adminUser, operatorUser, technicianUser, passiveUser]
    }
}
#endif
