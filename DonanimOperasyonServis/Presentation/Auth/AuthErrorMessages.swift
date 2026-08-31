import Foundation

/// Turkish user-facing copy for authentication errors. Presentation
/// maps `DomainError` here; Domain stays code-first.
enum AuthErrorMessages {

    static func title(for error: DomainError) -> String {
        switch error {
        case .authenticationFailed(let reason):
            switch reason {
            case .invalidCredentials, .userNotFound:
                return "Giriş başarısız"
            case .networkUnavailable:
                return "Bağlantı hatası"
            case .tooManyRequests:
                return "Çok fazla deneme"
            case .unauthorized:
                return "Yetkisiz hesap"
            case .userDocumentMissing:
                return "Kullanıcı profili bulunamadı"
            case .keychainUnavailable:
                return "Oturum deposu hatası"
            case .weakPassword:
                return "Şifre geçersiz"
            case .passwordsDoNotMatch:
                return "Şifreler eşleşmiyor"
            case .sameAsCurrentPassword:
                return "Şifre değişmedi"
            case .sessionInvalid:
                return "Oturum geçersiz"
            case .requiresRecentLogin:
                return "Yeniden doğrulama gerekli"
            case .unknown:
                return "Kimlik doğrulama hatası"
            }
        default:
            return "Bir hata oluştu"
        }
    }

    static func message(for error: DomainError) -> String? {
        switch error {
        case .authenticationFailed(let reason):
            switch reason {
            case .invalidCredentials, .userNotFound:
                return "E-posta veya şifre hatalı."
            case .networkUnavailable:
                return "İnternet bağlantınızı kontrol edip tekrar deneyin."
            case .tooManyRequests:
                return "Lütfen bir süre bekleyip tekrar deneyin."
            case .unauthorized:
                return "Hesabınız devre dışı veya bu uygulamaya erişemiyor."
            case .userDocumentMissing:
                return "Oturum açıldı ancak kullanıcı kaydı bulunamadı. Yöneticinizle iletişime geçin."
            case .keychainUnavailable:
                return "Uygulama oturumu kaydedemedi. Xcode’da Signing & Capabilities altında bir Development Team seçip yeniden çalıştırın."
            case .weakPassword:
                return "Yeni şifre en az \(PasswordPolicy.minimumLength) karakter olmalıdır."
            case .passwordsDoNotMatch:
                return "Yeni şifre ile tekrarı eşleşmiyor."
            case .sameAsCurrentPassword:
                return "Yeni şifre mevcut şifreyle aynı olamaz."
            case .sessionInvalid:
                return "Oturumunuz geçersiz. Lütfen yeniden giriş yapın."
            case .requiresRecentLogin:
                return "Güvenlik için mevcut şifrenizi tekrar girmeniz gerekiyor."
            case .unknown:
                return "Beklenmeyen bir hata oluştu."
            }
        default:
            return nil
        }
    }
}
