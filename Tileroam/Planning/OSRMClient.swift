import Foundation

/// Client for the public OSRM cycling router of openstreetmap.de (fair use, no key).
struct OSRMClient: Sendable {
    var baseURL = URL(string: "https://routing.openstreetmap.de/routed-bike")!

    struct Route: Sendable {
        var coordinates: [GeoPoint]
        /// Meters.
        var distance: Double
        /// Seconds.
        var duration: Double
        /// Input points snapped to the road network, in input order.
        var snapped: [GeoPoint]
    }

    enum OSRMError: LocalizedError {
        case server(String)

        var errorDescription: String? {
            switch self {
            case .server(let message): String(localized: "Route planning failed: \(message)")
            }
        }
    }

    /// Visiting order for a round trip starting at `points[0]`: indices into `points`, starting with 0.
    func tripOrder(_ points: [GeoPoint]) async throws -> [Int] {
        let data = try await get("trip/v1/bike/\(Self.path(points))",
                                 ["roundtrip": "true", "source": "first", "overview": "false"])
        return try Self.decodeTripOrder(data)
    }

    func route(_ points: [GeoPoint]) async throws -> Route {
        let data = try await get("route/v1/bike/\(Self.path(points))",
                                 ["overview": "full", "geometries": "geojson"])
        return try Self.decodeRoute(data)
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> Data {
        var c = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: c.url!)
        request.setValue("Tileroam/1.0 (iOS; personal route planning)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(Status.self, from: data))?.message ?? "HTTP \(http.statusCode)"
            throw OSRMError.server(message)
        }
        return data
    }

    static func path(_ points: [GeoPoint]) -> String {
        points.map { String(format: "%.6f,%.6f", $0.lon, $0.lat) }.joined(separator: ";")
    }

    // MARK: Decoding

    private struct Status: Decodable {
        let code: String
        let message: String?
    }

    static func decodeTripOrder(_ data: Data) throws -> [Int] {
        struct Response: Decodable {
            struct Waypoint: Decodable { let waypoint_index: Int }
            let code: String
            let message: String?
            let waypoints: [Waypoint]?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        guard r.code == "Ok", let waypoints = r.waypoints else { throw OSRMError.server(r.message ?? r.code) }
        // waypoint_index is the position of each input in the trip.
        return waypoints.indices.sorted { waypoints[$0].waypoint_index < waypoints[$1].waypoint_index }
    }

    static func decodeRoute(_ data: Data) throws -> Route {
        struct Response: Decodable {
            struct R: Decodable {
                struct Geometry: Decodable { let coordinates: [[Double]] }
                let distance: Double
                let duration: Double
                let geometry: Geometry
            }
            struct Waypoint: Decodable { let location: [Double] }
            let code: String
            let message: String?
            let routes: [R]?
            let waypoints: [Waypoint]?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        guard r.code == "Ok", let route = r.routes?.first else { throw OSRMError.server(r.message ?? r.code) }
        return Route(coordinates: route.geometry.coordinates.compactMap { $0.count >= 2 ? GeoPoint(lat: $0[1], lon: $0[0]) : nil },
                     distance: route.distance,
                     duration: route.duration,
                     snapped: (r.waypoints ?? []).compactMap { $0.location.count >= 2 ? GeoPoint(lat: $0.location[1], lon: $0.location[0]) : nil })
    }
}
