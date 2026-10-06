import Foundation
import Testing
@testable import Tileroam

struct RegionAssetsTests {
    @Test func timeoutStopsWaiting() async {
        let start = ContinuousClock.now
        await #expect(throws: RegionAssets.TimeoutError.self) {
            // An operation that ignores cancellation, like a download that hangs.
            try await RegionAssets.withTimeout(.milliseconds(200)) { while true { try? await Task.sleep(for: .seconds(60)) } }
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func passesResultsAndErrorsOn() async throws {
        try await RegionAssets.withTimeout(.seconds(5)) {}
        struct Failure: Error {}
        await #expect(throws: Failure.self) { try await RegionAssets.withTimeout(.seconds(5)) { throw Failure() } }
    }
}
