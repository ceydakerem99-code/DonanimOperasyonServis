import MapKit
import SwiftUI

/// Read-only MapKit surface for customer / GPS context on technician detail.
struct WorkOrderMapSection: View {
    let customerName: String
    let address: String
    let city: String?
    let capturedLocations: [WorkOrderLocation]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var resolvedCoordinate: CLLocationCoordinate2D?

    private var query: String {
        [address, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Konum")
                .font(AppFont.subtitle)

            Map(position: $cameraPosition) {
                if let coordinate = resolvedCoordinate {
                    Annotation(customerName, coordinate: coordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppColor.danger)
                            .font(.title)
                    }
                }
                ForEach(capturedLocations, id: \.id) { location in
                    Marker(
                        location.event.displayName,
                        coordinate: CLLocationCoordinate2D(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                        )
                    )
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.divider)
            )

            Text(query)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)

            if let coordinate = resolvedCoordinate,
               let url = URL(string: "http://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)") {
                Link(destination: url) {
                    Label("Yol Tarifi", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.brandPrimary)
                        .frame(minHeight: AppSpacing.minimumTouchTarget)
                }
            }
        }
        .task(id: query) {
            await resolveAddress()
        }
    }

    @MainActor
    private func resolveAddress() async {
        if let last = capturedLocations.last {
            let coordinate = CLLocationCoordinate2D(
                latitude: last.coordinate.latitude,
                longitude: last.coordinate.longitude
            )
            resolvedCoordinate = coordinate
            cameraPosition = .region(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800)
            )
            return
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        do {
            let response = try await MKLocalSearch(request: request).start()
            if let item = response.mapItems.first {
                let coordinate = item.placemark.coordinate
                resolvedCoordinate = coordinate
                cameraPosition = .region(
                    MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200)
                )
            }
        } catch {
            // Keep map empty; address text still shown.
        }
    }
}
