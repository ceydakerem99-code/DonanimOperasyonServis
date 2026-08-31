import Foundation
import UIKit

/// Builds a multi-page PDF for a work-order service report (read-only export).
enum WorkOrderReportPDFExporter {
    struct MediaBundle: Sendable {
        var photoImages: [(title: String, data: Data)]
        var signatureImages: [(title: String, data: Data)]
    }

    private static let pageWidth: CGFloat = 595 // A4
    private static let pageHeight: CGFloat = 842
    private static let margin: CGFloat = 40
    private static let contentWidth: CGFloat = pageWidth - margin * 2

    private static let brand = UIColor(red: 17 / 255, green: 54 / 255, blue: 92 / 255, alpha: 1)
    private static let muted = UIColor(red: 90 / 255, green: 100 / 255, blue: 120 / 255, alpha: 1)
    private static let line = UIColor(red: 229 / 255, green: 232 / 255, blue: 238 / 255, alpha: 1)
    private static let surface = UIColor(red: 245 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1)

    static func makePDF(
        snapshot: WorkOrderReportSnapshot,
        media: MediaBundle
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            var y: CGFloat = 0
            var pageNumber = 0

            func beginFreshPage(drawHeaderBand: Bool) {
                context.beginPage()
                pageNumber += 1
                y = margin
                if drawHeaderBand {
                    drawPageChrome(in: context.cgContext, pageNumber: pageNumber)
                    y = 78
                } else {
                    drawFooter(pageNumber: pageNumber)
                    y = margin + 8
                }
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > pageHeight - 56 {
                    beginFreshPage(drawHeaderBand: false)
                }
            }

            func drawFooter(pageNumber: Int) {
                let footer = "\(snapshot.workOrder.workOrderNumber)  ·  Sayfa \(pageNumber)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9),
                    .foregroundColor: muted
                ]
                (footer as NSString).draw(
                    at: CGPoint(x: margin, y: pageHeight - 28),
                    withAttributes: attrs
                )
                brand.setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: pageHeight - 36))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: pageHeight - 36))
                path.lineWidth = 0.6
                path.stroke()
            }

            func drawPageChrome(in cg: CGContext, pageNumber: Int) {
                cg.setFillColor(brand.cgColor)
                cg.fill(CGRect(x: 0, y: 0, width: pageWidth, height: 56))
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                ("Servis Raporu" as NSString).draw(
                    at: CGPoint(x: margin, y: 18),
                    withAttributes: titleAttrs
                )
                let numberAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9)
                ]
                let number = snapshot.workOrder.workOrderNumber as NSString
                let numberSize = number.size(withAttributes: numberAttrs)
                number.draw(
                    at: CGPoint(x: pageWidth - margin - numberSize.width, y: 20),
                    withAttributes: numberAttrs
                )
                drawFooter(pageNumber: pageNumber)
            }

            func textHeight(_ text: String, font: UIFont, width: CGFloat = contentWidth) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                return ceil((text as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                ).height)
            }

            func drawText(
                _ text: String,
                font: UIFont,
                color: UIColor = .black,
                x: CGFloat = margin,
                width: CGFloat = contentWidth
            ) {
                let height = textHeight(text, font: font, width: width)
                ensureSpace(height + 4)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                (text as NSString).draw(
                    in: CGRect(x: x, y: y, width: width, height: height),
                    withAttributes: attrs
                )
                y += height + 4
            }

            func sectionTitle(_ title: String) {
                ensureSpace(36)
                y += 10
                brand.setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: 3, height: 16), cornerRadius: 1.5).fill()
                drawText(title, font: .systemFont(ofSize: 13, weight: .semibold), color: brand, x: margin + 10)
                y += 2
            }

            func keyValueRow(_ key: String, _ value: String) {
                let rowH = max(
                    textHeight(key, font: .systemFont(ofSize: 10, weight: .medium), width: 140),
                    textHeight(value, font: .systemFont(ofSize: 11), width: contentWidth - 150)
                ) + 8
                ensureSpace(rowH)
                let attrsKey: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: muted
                ]
                let attrsVal: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.black
                ]
                (key as NSString).draw(
                    in: CGRect(x: margin, y: y + 2, width: 140, height: rowH),
                    withAttributes: attrsKey
                )
                (value as NSString).draw(
                    in: CGRect(x: margin + 150, y: y + 2, width: contentWidth - 150, height: rowH),
                    withAttributes: attrsVal
                )
                y += rowH
                line.setStroke()
                let divider = UIBezierPath()
                divider.move(to: CGPoint(x: margin, y: y))
                divider.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                divider.lineWidth = 0.5
                divider.stroke()
                y += 2
            }

            func milestoneCard(_ rows: [(String, String)]) {
                let cardPadding: CGFloat = 12
                let colWidth = (contentWidth - 12) / 2
                let rowHeight: CGFloat = 44
                let rowsNeeded = ceil(Double(rows.count) / 2.0)
                let cardHeight = CGFloat(rowsNeeded) * rowHeight + cardPadding * 2
                ensureSpace(cardHeight + 8)
                surface.setFill()
                UIBezierPath(
                    roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: cardHeight),
                    cornerRadius: 8
                ).fill()

                for (index, row) in rows.enumerated() {
                    let col = index % 2
                    let rowIndex = index / 2
                    let x = margin + cardPadding + CGFloat(col) * (colWidth + 12)
                    let cellY = y + cardPadding + CGFloat(rowIndex) * rowHeight
                    let labelAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 9, weight: .medium),
                        .foregroundColor: muted
                    ]
                    let valueAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                        .foregroundColor: brand
                    ]
                    (row.0 as NSString).draw(at: CGPoint(x: x, y: cellY), withAttributes: labelAttrs)
                    (row.1 as NSString).draw(at: CGPoint(x: x, y: cellY + 16), withAttributes: valueAttrs)
                }
                y += cardHeight + 8
            }

            beginFreshPage(drawHeaderBand: true)

            // Meta
            sectionTitle("İş Emri Bilgileri")
            keyValueRow("Müşteri", snapshot.customerName)
            if let address = snapshot.customerAddress, !address.isEmpty {
                keyValueRow("Adres", address)
            }
            if let tech = snapshot.technicianName, !tech.isEmpty {
                keyValueRow("Teknisyen", tech)
            }
            keyValueRow("Durum", snapshot.workOrder.status.displayName)
            keyValueRow("İş Türü", snapshot.workOrder.workType.displayName)
            keyValueRow(
                "Cihaz",
                "\(snapshot.workOrder.deviceCategory.displayName) · \(snapshot.workOrder.deviceBrand) \(snapshot.workOrder.deviceModel)"
            )
            keyValueRow("Seri No", snapshot.workOrder.serialNumber)
            if let description = snapshot.workOrder.issueDescription, !description.isEmpty {
                keyValueRow("Yapılan İşlem", description)
            }

            // Timeline milestones
            sectionTitle("Saha Zamanları")
            let dash = "—"
            let milestones: [(String, String)] = [
                ("Kabul", format(snapshot.firstStatusTime(.accepted)) ?? dash),
                ("Yola Çıkış", format(
                    snapshot.milestoneTime(status: .enRoute, locationEvent: .enRoute)
                ) ?? dash),
                ("Varış", format(
                    snapshot.milestoneTime(status: .arrived, locationEvent: .arrived)
                ) ?? dash),
                ("İşe Başlama", format(snapshot.firstStatusTime(.inProgress)) ?? dash),
                ("Tamamlanma", format(
                    snapshot.workOrder.completedAt
                        ?? snapshot.milestoneTime(status: .completed, locationEvent: .completed)
                ) ?? dash),
                ("Rapor Tarihi", format(Date()) ?? dash)
            ]
            milestoneCard(milestones)

            // Full status timeline
            sectionTitle("Durum Geçmişi")
            if snapshot.timeline.isEmpty {
                drawText("Kayıt yok.", font: .systemFont(ofSize: 11), color: muted)
            } else {
                for entry in snapshot.timeline.sorted(by: { $0.occurredAt < $1.occurredAt }) {
                    var lineText = "\(format(entry.occurredAt) ?? "—")  ·  \(entry.toStatus.displayName)"
                    if let pause = entry.pauseReason {
                        lineText += " (\(pause.displayName))"
                    }
                    drawText(lineText, font: .systemFont(ofSize: 11))
                }
            }

            // GPS with times
            sectionTitle("GPS Kayıtları")
            if snapshot.locations.isEmpty {
                drawText("Kayıt yok.", font: .systemFont(ofSize: 11), color: muted)
            } else {
                for location in snapshot.locations.sorted(by: { $0.capturedAt < $1.capturedAt }) {
                    let coords = String(
                        format: "%.5f, %.5f",
                        location.coordinate.latitude,
                        location.coordinate.longitude
                    )
                    drawText(
                        "\(location.event.displayName)  ·  \(format(location.capturedAt) ?? "—")",
                        font: .systemFont(ofSize: 11, weight: .medium)
                    )
                    drawText(coords, font: .systemFont(ofSize: 10), color: muted)
                }
            }

            // Notes
            sectionTitle("Servis Notları")
            if snapshot.notes.isEmpty {
                drawText("Not yok.", font: .systemFont(ofSize: 11), color: muted)
            } else {
                for note in snapshot.notes.sorted(by: { $0.createdAt < $1.createdAt }) {
                    drawText(format(note.createdAt) ?? "", font: .systemFont(ofSize: 9), color: muted)
                    drawText(note.text, font: .systemFont(ofSize: 11))
                    y += 4
                }
            }

            // Photos
            sectionTitle("Fotoğraflar")
            if media.photoImages.isEmpty {
                drawText("Fotoğraf yok.", font: .systemFont(ofSize: 11), color: muted)
            } else {
                for item in media.photoImages {
                    drawText(item.title, font: .systemFont(ofSize: 11, weight: .medium))
                    if let image = UIImage(data: item.data) {
                        let maxH: CGFloat = 200
                        let maxW = contentWidth
                        let ratio = min(maxW / max(image.size.width, 1), maxH / max(image.size.height, 1), 1)
                        let drawSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                        ensureSpace(drawSize.height + 12)
                        let rect = CGRect(x: margin, y: y, width: drawSize.width, height: drawSize.height)
                        line.setStroke()
                        UIBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 4).stroke()
                        image.draw(in: rect)
                        y += drawSize.height + 12
                    }
                }
            }

            // Signatures
            sectionTitle("İmzalar")
            if media.signatureImages.isEmpty {
                drawText("İmza yok.", font: .systemFont(ofSize: 11), color: muted)
            } else {
                for item in media.signatureImages {
                    drawText(item.title, font: .systemFont(ofSize: 11, weight: .medium))
                    if let image = UIImage(data: item.data) {
                        let drawH: CGFloat = 72
                        let drawW = min(contentWidth, image.size.width * (drawH / max(image.size.height, 1)))
                        ensureSpace(drawH + 16)
                        surface.setFill()
                        let box = CGRect(x: margin, y: y, width: contentWidth, height: drawH + 8)
                        UIBezierPath(roundedRect: box, cornerRadius: 6).fill()
                        image.draw(in: CGRect(x: margin + 8, y: y + 4, width: drawW, height: drawH))
                        y += drawH + 16
                    }
                }
            }
        }
    }

    private static func format(_ date: Date?) -> String? {
        guard let date else { return nil }
        return WorkOrderPresentationMapping.formatDateTime(date)
    }

    static func collectMedia(
        snapshot: WorkOrderReportSnapshot,
        loader: WorkOrderMediaLoader
    ) async -> MediaBundle {
        var photos: [(String, Data)] = []
        for photo in snapshot.photos {
            if let data = await loader.loadPhoto(photo) {
                let when = WorkOrderPresentationMapping.formatDateTime(photo.capturedAt)
                photos.append(("\(photo.category.displayName)  ·  \(when)", data))
            }
        }
        var signatures: [(String, Data)] = []
        for signature in snapshot.signatures {
            if let data = await loader.loadSignature(signature) {
                let name = signature.signerName.map { " — \($0)" } ?? ""
                let when = WorkOrderPresentationMapping.formatDateTime(signature.capturedAt)
                signatures.append(("\(signature.kind.displayName)\(name)  ·  \(when)", data))
            }
        }
        return MediaBundle(photoImages: photos, signatureImages: signatures)
    }
}
