import Foundation
import Valhalla

/// Cycling routes computed on the device by Valhalla (valhalla-mobile), from OpenStreetMap data
/// in `RoutingData`. Nothing leaves the device.
actor ValhallaRouter: CyclingRouter {
    private var engine: Valhalla?

    /// Bicycle costing: a hybrid bike that prefers cycle paths and quiet roads, like the
    /// "routed-bike" profile Tileroam used before.
    static var bicycle: [String: Any] {
        ["bicycle_type": "Hybrid", "use_roads": 0.3, "use_hills": 0.4, "avoid_bad_surfaces": 0.4]
    }

    /// Downloads the routing data if needed and starts the engine (slow the first time).
    func prepare() async throws {
        _ = try await valhalla()
    }

    private func valhalla() async throws -> Valhalla {
        if let engine { return engine }
        let tiles = try await RoutingData.tileExtract()
        let config = try RoutingData.writeConfig(tileExtract: tiles)
        do {
            let engine = try Valhalla(configPath: config.path(percentEncoded: false))
            self.engine = engine
            return engine
        } catch {
            throw RoutingError.dataUnavailable(error.localizedDescription)
        }
    }

    /// The visiting order from straight-line distances. Valhalla's cycling matrix gives nearly the
    /// same order in the dense Benelux network but takes tens of seconds for 30 stops on a phone.
    func tripOrder(_ points: [GeoPoint]) async throws -> [Int] {
        TripSolver.roundTrip(points.map { a in points.map { b in Geo.distance(a, b) } })
    }

    func route(_ points: [GeoPoint]) async throws -> RoutedPath {
        let request: [String: Any] = [
            "locations": points.map { ["lat": $0.lat, "lon": $0.lon, "type": "break"] },
            "costing": "bicycle", "costing_options": ["bicycle": Self.bicycle],
            "units": "kilometers", "directions_type": "none",
        ]
        let response = try await run(request) { try $0.route(rawRequest: $1) }
        return try Self.decodeRoute(response)
    }

    /// Runs a Valhalla action with a JSON request and returns the parsed JSON response.
    private func run(_ request: [String: Any], _ action: (Valhalla, String) throws -> String) async throws -> [String: Any] {
        let engine = try await valhalla()
        let json = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        let text: String
        do {
            text = try action(engine, json)
        } catch {
            throw RoutingError.engine(Self.message(error))
        }
        guard let response = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw RoutingError.engine("unreadable response")
        }
        if let message = response["error"] as? String { throw RoutingError.engine(message) }
        return response
    }

    private static func message(_ error: any Error) -> String {
        // Valhalla's errors carry its JSON ({"error_code": 171, "error": "No suitable edges near location"}).
        let text = String(describing: error)
        if let range = text.range(of: #""error":\s*"([^"]+)""#, options: .regularExpression) {
            return String(text[range]).replacingOccurrences(of: #""error":\s*""#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return error.localizedDescription
    }

    // MARK: Decoding (static, so it can be tested without tiles)

    static func decodeRoute(_ response: [String: Any]) throws -> RoutedPath {
        guard let trip = response["trip"] as? [String: Any],
              let legs = trip["legs"] as? [[String: Any]], !legs.isEmpty,
              let summary = trip["summary"] as? [String: Any] else { throw RoutingError.engine("no route") }
        var coordinates = [GeoPoint]()
        var snapped = [GeoPoint]()
        for leg in legs {
            let shape = decodePolyline6(leg["shape"] as? String ?? "")
            guard let first = shape.first else { continue }
            snapped.append(first)
            coordinates += coordinates.last == first ? Array(shape.dropFirst()) : shape
        }
        if let last = coordinates.last { snapped.append(last) }
        return RoutedPath(coordinates: coordinates,
                          distance: ((summary["length"] as? Double) ?? 0) * 1000,
                          duration: (summary["time"] as? Double) ?? 0,
                          snapped: snapped)
    }

    /// Valhalla's encoded polylines use six decimals.
    static func decodePolyline6(_ s: String) -> [GeoPoint] {
        var points = [GeoPoint]()
        var lat = 0, lon = 0
        var index = s.utf8.startIndex
        let bytes = s.utf8
        func next() -> Int? {
            var result = 0, shift = 0
            while index != bytes.endIndex {
                let b = Int(bytes[index]) - 63
                index = bytes.index(after: index)
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }
        while let dLat = next(), let dLon = next() {
            lat += dLat
            lon += dLon
            points.append(GeoPoint(lat: Double(lat) / 1e6, lon: Double(lon) / 1e6))
        }
        return points
    }
}
