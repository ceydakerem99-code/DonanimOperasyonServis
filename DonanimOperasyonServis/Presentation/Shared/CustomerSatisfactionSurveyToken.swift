import CryptoKit
import Foundation

enum CustomerSatisfactionSurveyWebConfig {
    static let baseURL = "https://dopsanketsistemi.netlify.app"

    /// Reads `SurveyTokenSecret` from Info.plist (populated via
    /// gitignored `Config/SurveyProductionSecrets.xcconfig`).
    /// Falls back to local dev secret if unconfigured.
    static var tokenSecret: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "SurveyTokenSecret") as? String,
           !value.isEmpty,
           !value.contains("$(") {
            return value
        }
        return "dops-survey-dev-secret"
    }
}

enum CustomerSatisfactionSurveyToken {
    static func generate(
        satisfactionId: CustomerSatisfactionID,
        secret: String = CustomerSatisfactionSurveyWebConfig.tokenSecret
    ) -> String {
        let id = satisfactionId.rawValue
        let idPart = Data(id.utf8).base64URLEncodedString()
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(id.utf8), using: key)
        let sigPart = Data(signature).base64URLEncodedString()
        return "\(idPart).\(sigPart)"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
