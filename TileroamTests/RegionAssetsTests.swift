import Foundation
import Testing
@testable import Tileroam

struct RegionAssetsTests {
    @Test func timeoutStopsWaiting() async {
        let start = ContinuousClock.now
        await #expect(throws: RegionAssets.TimeoutError.self) {
            // An operation that ignores cancellation, like a download that hangs: it waits for a
            // detached task, which the cancellation doesn't reach (and which ends by itself).
            try await RegionAssets.withTimeout(.milliseconds(200)) {
                await Task.detached { try? await Task.sleep(for: .seconds(10)) }.value
            }
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func passesResultsAndErrorsOn() async throws {
        try await RegionAssets.withTimeout(.seconds(5)) {}
        struct Failure: Error {}
        await #expect(throws: Failure.self) { try await RegionAssets.withTimeout(.seconds(5)) { throw Failure() } }
    }
}
