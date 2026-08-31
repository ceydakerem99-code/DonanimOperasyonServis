import CryptoKit
import Foundation

enum CustomerSatisfactionSurveyWebConfig {
    #if DEBUG
    static let baseURL = "https://internship-repair-drinking-strip.trycloudflare.com"
    #else
    static let baseURL = "https://survey.donanimoperasyon.example"
    #endif

    /// Must match `DEFAULT_SURVEY_TOKEN_SECRET` in `functions/src/survey/token.ts`.
    static let tokenSecret = "dops-survey-dev-secret"
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
