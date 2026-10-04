import Foundation
import MapKit

/// A place the user chose to start a planned round trip from, instead of the current location.
struct StartPoint: Codable, Hashable, Sendable {
    var name: String
    var lat: Double
    var lon: Double

    init(name: String, lat: Double, lon: Double) {
        self.name = name
        self.lat = lat
        self.lon = lon
    }

    init(name: String, _ point: GeoPoint) {
        self.init(name: name, lat: point.lat, lon: point.lon)
    }

    var point: GeoPoint { GeoPoint(lat: lat, lon: lon) }

    /// "52.0907, 5.1214", for a pin without a known place name.
    static func coordinateName(_ point: GeoPoint) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(4))
        return "\(point.lat.formatted(style)), \(point.lon.formatted(style))"
    }

    /// A start dropped on the map, named after the address or place there when MapKit knows one.
    static func dropped(at point: GeoPoint) async -> StartPoint {
        let location = CLLocation(latitude: point.lat, longitude: point.lon)
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first,
           let name = item.address?.shortAddress ?? item.name {
            return StartPoint(name: name, point)
        }
        return StartPoint(name: coordinateName(point), point)
    }
}

/// The last starting points the user chose, kept on this device only.
enum RecentStarts {
    static let key = "recentStartPoints"
    static let limit = 5
    /// A new start closer than this to an earlier one replaces it.
    static let sameDistance = 100.0

    static func load(_ defaults: UserDefaults = .standard) -> [StartPoint] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([StartPoint].self, from: data)) ?? []
    }

    static func save(_ starts: [StartPoint], _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(starts), forKey: key)
    }

    /// `start` first, then the others without any near it, at most `limit`.
    static func adding(_ start: StartPoint, to starts: [StartPoint]) -> [StartPoint] {
        let others = starts.filter { Geo.distance($0.point, start.point) >= sameDistance }
        return Array(([start] + others).prefix(limit))
    }
}

/// Address and place suggestions while typing, biased to the routing countries.
@MainActor
@Observable
final class PlaceSearch: NSObject {
    private(set) var results: [MKLocalSearchCompletion] = []
    var query = "" {
        didSet {
            if query.isEmpty { results = [] }
            completer.queryFragment = query
        }
    }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    /// The Netherlands, Belgium, Luxembourg, Germany, France, Switzerland and Austria.
    static let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.2, longitude: 6.0),
                                           span: MKCoordinateSpan(latitudeDelta: 13.8, longitudeDelta: 22.4))

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = Self.region
    }

    /// The coordinate of a suggestion.
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> StartPoint? {
        let request = MKLocalSearch.Request(completion: completion)
        request.region = Self.region
        guard let item = try await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let c = item.location.coordinate
        return StartPoint(name: completion.title, lat: c.latitude, lon: c.longitude)
    }
}

// MapKit calls the completer's delegate on the main thread.
extension PlaceSearch: @MainActor MKLocalSearchCompleterDelegate {
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
