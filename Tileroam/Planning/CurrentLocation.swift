import CoreLocation

/// Gets the current location once, asking for permission if needed.
@MainActor
final class CurrentLocation: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case denied

        var errorDescription: String? {
            String(localized: "Location access is off. Allow Tileroam to use your location in Settings to plan a route from where you are.")
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func get() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted: throw LocationError.denied
        default: break
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization() // continues in didChangeAuthorization
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: finish(.failure(LocationError.denied))
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        MainActor.assumeIsolated {
            if let location {
                WidgetData.saveLocation(location.coordinate)
                finish(.success(location))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            finish(.failure(error))
        }
    }
}
