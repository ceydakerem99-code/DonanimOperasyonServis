import Foundation

enum LegacyDataBackfillDryRun {

    static func run(container: DIContainer) async {
        let logFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-dry-run.txt")

        func out(_ text: String) {
            print(text)
            let data = (text + "\n").data(using: .utf8)!
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logFile)
            }
        }

        try? "".write(to: logFile, atomically: true, encoding: .utf8)

        out("========== LEGACY DATA DRY RUN ==========")
        out("FIREBASE WRITE: NO")
        out("DELETE: NO")
        out("SYNC QUEUE: NO")
        out("")

        do {
            let filter = WorkOrderFilter(status: .completed)
            let completed = try await container.workOrderRepository.list(filter: filter)

            out("DRYRUN_RESULT completed=\(completed.count)")
            if let remote = try? await container.remoteWorkOrderRepository.fetch(id: WorkOrderID("demo-wo-assigned")) { out("FIREBASE_WORKORDER_FOUND status=\(remote.status.rawValue)") } else { out("FIREBASE_WORKORDER_NOT_FOUND") }
            out("")

            var totalNotes = 0
            var totalPhotos = 0
            var totalLocations = 0
            var totalSignatures = 0

            for order in completed {
                let id = order.id

                let notes = try await container.workOrderNoteRepository.list(for: id)
                let photos = try await container.workOrderPhotoRepository.list(for: id)
                let locations = try await container.workOrderLocationRepository.list(for: id)
                let signatures = try await container.signatureRepository.list(for: id)

                totalNotes += notes.count
                totalPhotos += photos.count
                totalLocations += locations.count
                totalSignatures += signatures.count

                let noteCount = notes.count
                let photoCount = photos.count
                let locationCount = locations.count
                let signatureCount = signatures.count

                out(
                    "ORDER \(id.rawValue) | " +
                    "notes=\(noteCount) | " +
                    "photos=\(photoCount) | " +
                    "locations=\(locationCount) | " +
                    "signatures=\(signatureCount)"
                )
            }

            out("")
            out("========== TOTAL ==========")
            out("Notes: \(totalNotes)")
            out("Photos: \(totalPhotos)")
            out("Locations: \(totalLocations)")
            out("Signatures: \(totalSignatures)")
            out("")
            out("DRY RUN COMPLETE")
            out("=========================================")

        } catch {
            out("DRY RUN ERROR: \(error)")
        }
    }
}
