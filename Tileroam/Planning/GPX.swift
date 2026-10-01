import Foundation

/// Minimal GPX 1.1 writer and reader.
enum GPX {
    static func write(name: String, track: [GeoPoint], waypoints: [(point: GeoPoint, name: String)] = []) -> Data {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func coord(_ p: GeoPoint) -> String { String(format: "lat=\"%.6f\" lon=\"%.6f\"", p.lat, p.lon) }

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Tileroam" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(esc(name))</name><time>\(ISO8601DateFormatter().string(from: .now))</time></metadata>

        """
        for w in waypoints {
            xml += "  <wpt \(coord(w.point))><name>\(esc(w.name))</name></wpt>\n"
        }
        xml += "  <trk>\n    <name>\(esc(name))</name>\n    <type>cycling</type>\n    <trkseg>\n"
        for p in track {
            xml += "      <trkpt \(coord(p))/>\n"
        }
        xml += "    </trkseg>\n  </trk>\n</gpx>\n"
        return Data(xml.utf8)
    }

    struct Parsed {
        var name: String?
        /// Track points, or route points when the file has no track.
        var points: [GeoPoint]
        var waypoints: [GeoPoint]
    }

    static func parse(_ data: Data) -> Parsed? {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() || !delegate.track.isEmpty || !delegate.route.isEmpty else { return nil }
        let points = delegate.track.isEmpty ? delegate.route : delegate.track
        guard !points.isEmpty || !delegate.waypoints.isEmpty else { return nil }
        return Parsed(name: delegate.name, points: points.isEmpty ? delegate.waypoints : points, waypoints: delegate.waypoints)
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var track = [GeoPoint]()
        var route = [GeoPoint]()
        var waypoints = [GeoPoint]()
        var name: String?
        private var text = ""
        private var depthInPoint = 0

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            text = ""
            let local = element.split(separator: ":").last.map(String.init) ?? element
            guard ["trkpt", "rtept", "wpt"].contains(local) else {
                return
            }
            depthInPoint += 1
            guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) else { return }
            let p = GeoPoint(lat: lat, lon: lon)
            switch local {
            case "trkpt": track.append(p)
            case "rtept": route.append(p)
            default: waypoints.append(p)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            let local = element.split(separator: ":").last.map(String.init) ?? element
            if ["trkpt", "rtept", "wpt"].contains(local) { depthInPoint -= 1 }
            if local == "name", depthInPoint == 0, name == nil {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { name = trimmed }
            }
        }
    }
}
