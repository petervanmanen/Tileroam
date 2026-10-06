import Foundation
import Testing
@testable import Tileroam

struct BoscafeTests {
    /// The list in the repository (AssetPacks/Boscafes), as uploaded to R2.
    static let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "AssetPacks/Boscafes/boscafes.json")

    @Test func repositoryData() throws {
        let list = try JSONDecoder().decode([Boscafe].self, from: Data(contentsOf: Self.file))
        #expect(list.count == 54)
        #expect(Set(list.map(\.id)).count == list.count)
        // All in the Netherlands, each with an emoji.
        #expect(list.allSatisfy { (50.7...53.6).contains($0.lat) && (3.3...7.3).contains($0.lon) && !$0.emoji.isEmpty })
    }

    @Test func boscafeAsAPlanTarget() throws {
        let boshut = Boscafe(id: "de-boshut-hilversum", name: "De Boshut", place: "Hilversum", emoji: "🌲", lat: 52.24173, lon: 5.1609)
        let target = try #require(TargetGeometry(.boscafe(boshut.id), regions: nil, boscafes: [boshut]))
        #expect(target.name == "De Boshut")
        #expect(target.candidates().first == boshut.point && target.candidates().allSatisfy(target.contains))
        #expect(TargetGeometry(.boscafe("unknown"), regions: nil, boscafes: [boshut]) == nil)
        let coverage = RouteCoverage(route: [GeoPoint(lat: 52.24173, lon: 5.15), GeoPoint(lat: 52.24173, lon: 5.17)],
                                     visitedTiles14: [], visitedMunicipalities: [], visitedPostcodes: [], regions: nil,
                                     boscafes: [boshut], visitedBoscafes: [])
        #expect(coverage.contains(.boscafe(boshut.id)) && coverage.newBoscafes == [boshut.id])
    }

    @Test func challengeIsOffByDefault() {
        #expect(MapMode.boscafes.isChallenge)
        #expect(!Challenges.visibleModes("").contains(.boscafes))
    }
}
