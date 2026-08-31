import Foundation
import Observation

@Observable
@MainActor
final class AdminCreateUserViewModel {
    enum Phase: Equatable {
        case form
        case saving
        case error(String)
        case created(UserID)
    }

    var email = ""
    var password = ""
    var fullName = ""
    var phoneNumber = ""
    var role: UserRole = .technician
    private(set) var phase: Phase = .form

    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && password.count >= 6
            && !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && phase != .saving
    }

    func create() async {
        phase = .saving
        do {
            let user = try await dependencies.userService.createUser(
                actor: actor,
                email: email,
                password: password,
                fullName: fullName,
                role: role,
                phoneNumber: phoneNumber
            )
            phase = .created(user.id)
        } catch is CancellationError {
            phase = .form
        } catch let error as DomainError {
            phase = .error(error.createUserMessage)
        } catch {
            phase = .error("Kullanıcı oluşturulamadı.")
        }
    }

    func clearError() {
        if case .error = phase {
            phase = .form
        }
    }
}

extension DomainError {
    fileprivate var createUserMessage: String {
        switch self {
        case .invalidData(let reason):
            if reason.hasPrefix("user.invalidEmail") {
                return "Geçerli bir e-posta girin."
            }
            if reason.hasPrefix("user.weakPassword") {
                return "Şifre en az 6 karakter olmalı."
            }
            if reason.hasPrefix("user.fullNameRequired") {
                return "Ad soyad zorunludur."
            }
            if reason.hasPrefix("user.invalidPhone") {
                return "Telefon numarası geçersiz."
            }
            if reason.hasPrefix("user.emailAlreadyExists") {
                return "Bu e-posta zaten kayıtlı."
            }
            return adminMessage
        case .unauthorized:
            return "Bu işlem için yetkiniz yok."
        case .infrastructure(let underlying):
            if underlying.contains("networkUnavailable") {
                return "İnternet bağlantısı gerekli. Kullanıcı oluşturmak için çevrimiçi olun."
            }
            if underlying.contains("remoteProfileWriteFailed") {
                return "Hesap açıldı ancak profil yazılamadı. Tekrar deneyin veya Console’dan kontrol edin."
            }
            if underlying.contains("emailPasswordDisabled") {
                return "Firebase’de E-posta/Şifre girişi kapalı."
            }
            return adminMessage
        case .authenticationFailed(.tooManyRequests):
            return "Çok fazla deneme. Bir süre sonra tekrar deneyin."
        default:
            return adminMessage
        }
    }
}
