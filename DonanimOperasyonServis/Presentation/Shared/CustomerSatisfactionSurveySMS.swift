import Foundation
import os
import SwiftUI

struct CustomerSatisfactionSMSPreviewContent: Equatable, Sendable {
    let senderName: String
    let customerName: String
    let workOrderNumber: String
    let surveyLink: String
    let ctaLabel: String

    static func make(
        customerName: String,
        workOrderNumber: String,
        satisfactionId: CustomerSatisfactionID
    ) -> CustomerSatisfactionSMSPreviewContent {
        CustomerSatisfactionSMSPreviewContent(
            senderName: "Donanım Operasyon Servis",
            customerName: customerName,
            workOrderNumber: workOrderNumber,
            surveyLink: CustomerSatisfactionSurveySMS.surveyWebURL(satisfactionId: satisfactionId),
            ctaLabel: "Değerlendirmeye Git"
        )
    }

    var greetingLine: String {
        "Merhaba \(customerName),"
    }

    var bodyLines: [String] {
        [
            "\(workOrderNumber) numaralı servis işleminiz tamamlanmıştır.",
            "Hizmetimizden ne kadar memnun kaldığınızı öğrenmek isteriz.",
            "Değerlendirmenizi yapmak için aşağıdaki bağlantıya tıklayabilirsiniz:"
        ]
    }

    var closingLine: String {
        "Teşekkür ederiz."
    }

    var plainTextMessage: String {
        ([senderName, "", greetingLine]
            + bodyLines
            + ["", surveyLink, "", closingLine])
            .joined(separator: "\n")
    }
}

enum CustomerSatisfactionSurveySMS {
    static func surveyLink(for satisfactionId: CustomerSatisfactionID) -> String {
        surveyWebURL(satisfactionId: satisfactionId)
    }

    static func surveyWebURL(satisfactionId: CustomerSatisfactionID) -> String {
        let token = CustomerSatisfactionSurveyToken.generate(satisfactionId: satisfactionId)
        return "\(CustomerSatisfactionSurveyWebConfig.baseURL)/survey/\(token)"
    }

    static func nativeDeepLink(for satisfactionId: CustomerSatisfactionID) -> String {
        "dops://survey/\(satisfactionId.rawValue)"
    }

    static func previewContent(
        customerName: String,
        workOrderNumber: String,
        satisfactionId: CustomerSatisfactionID
    ) -> CustomerSatisfactionSMSPreviewContent {
        CustomerSatisfactionSMSPreviewContent.make(
            customerName: customerName,
            workOrderNumber: workOrderNumber,
            satisfactionId: satisfactionId
        )
    }

    static func messageBody(
        customerName: String,
        workOrderNumber: String,
        satisfactionId: CustomerSatisfactionID
    ) -> String {
        previewContent(
            customerName: customerName,
            workOrderNumber: workOrderNumber,
            satisfactionId: satisfactionId
        ).plainTextMessage
    }
}

enum CustomerSatisfactionSMSSimulator {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "DonanimOperasyonServis",
        category: "CustomerSatisfactionSMS"
    )
    private static let sentRegistry = CustomerSatisfactionSMSSentRegistry()

    static func simulateSend(
        customerName: String,
        workOrderNumber: String,
        satisfactionId: CustomerSatisfactionID,
        recipientPhone: String?
    ) {
        markSent(satisfactionId)
        let content = CustomerSatisfactionSurveySMS.previewContent(
            customerName: customerName,
            workOrderNumber: workOrderNumber,
            satisfactionId: satisfactionId
        )
        let recipient = recipientPhone ?? "telefon kaydı yok"
        logger.info(
            "SMS simulation → \(recipient, privacy: .public) link=\(content.surveyLink, privacy: .public)"
        )
        #if DEBUG
        print(
            """
            [CustomerSatisfaction SMS Simulation]
            Alıcı: \(recipient)
            Mesaj:
            \(content.plainTextMessage)
            """
        )
        #endif
    }

    static func wasSent(satisfactionId: CustomerSatisfactionID) -> Bool {
        sentRegistry.wasSent(satisfactionId)
    }

    static func markSent(_ satisfactionId: CustomerSatisfactionID) {
        sentRegistry.markSent(satisfactionId)
    }
}

private final class CustomerSatisfactionSMSSentRegistry: @unchecked Sendable {
    private var sentSatisfactionIds: Set<String> = []
    private let lock = NSLock()

    func markSent(_ satisfactionId: CustomerSatisfactionID) {
        lock.lock()
        sentSatisfactionIds.insert(satisfactionId.rawValue)
        lock.unlock()
    }

    func wasSent(_ satisfactionId: CustomerSatisfactionID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sentSatisfactionIds.contains(satisfactionId.rawValue)
    }
}

struct CustomerSatisfactionSMSMessagePreview: View {
    let content: CustomerSatisfactionSMSPreviewContent
    var onOpenSurvey: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Mesajlar")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.bottom, AppSpacing.xs)

            HStack(alignment: .bottom, spacing: AppSpacing.s) {
                Circle()
                    .fill(AppColor.brandPrimary.opacity(0.15))
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "building.2.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColor.brandPrimary)
                    }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(content.senderName)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)

                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Text(content.greetingLine)
                            .font(AppFont.body)

                        ForEach(content.bodyLines, id: \.self) { line in
                            Text(line)
                                .font(AppFont.body)
                        }

                        if let onOpenSurvey {
                            Button(action: onOpenSurvey) {
                                Text(content.ctaLabel)
                                    .font(AppFont.label)
                                    .foregroundStyle(AppColor.brandPrimary)
                                    .padding(.horizontal, AppSpacing.m)
                                    .padding(.vertical, AppSpacing.s)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(AppColor.brandPrimary.opacity(0.12))
                                    )
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(content.ctaLabel)
                                .font(AppFont.label)
                                .foregroundStyle(AppColor.brandPrimary)
                                .padding(.horizontal, AppSpacing.m)
                                .padding(.vertical, AppSpacing.s)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(AppColor.brandPrimary.opacity(0.12))
                                )
                        }

                        Text(content.surveyLink)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(AppColor.secondaryText)
                            .textSelection(.enabled)

                        Text(content.closingLine)
                            .font(AppFont.body)
                    }
                    .foregroundStyle(AppColor.primaryText)
                    .padding(AppSpacing.m)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(red: 0.90, green: 0.90, blue: 0.92))
                    )
                }

                Spacer(minLength: AppSpacing.xl)
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.neutralBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.divider.opacity(0.6), lineWidth: 1)
        )
    }
}
