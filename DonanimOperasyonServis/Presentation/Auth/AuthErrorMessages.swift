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
            case .unknown:
                return "Beklenmeyen bir hata oluştu."
            }
        default:
            return nil
        }
    }
}
