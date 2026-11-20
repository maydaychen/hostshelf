import Foundation
import HostShelfCore

final class InFlightExcerptGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseFirst = DispatchSemaphore(value: 0)
    private let expectedOldLine: String
    private var callCount = 0
    private var capturedOldResult = false
    private var released = false

    init(expectedOldLine: String) {
        self.expectedOldLine = expectedOldLine
    }

    var hasCapturedOldResult: Bool { lock.withLock { capturedOldResult } }
    var firstCallWasReleased: Bool { lock.withLock { released } }

    func read(host: HostEntry, sourceIdentities: [String: SourceIdentity], shouldCancel: () -> Bool) -> [SourceExcerpt] {
        let isFirst = lock.withLock {
            callCount += 1
            return callCount == 1
        }
        let result = SourceExcerptReader.read(for: host, sourceIdentities: sourceIdentities, shouldCancel: shouldCancel)
        if isFirst {
            lock.withLock { capturedOldResult = result.contains { $0.lines.contains { $0.text == expectedOldLine } } }
            // Keep the captured result even after cancellation to exercise the view's final guard.
            let outcome = releaseFirst.wait(timeout: .now() + 8)
            lock.withLock { released = outcome == .success }
        }
        return result
    }

    func releaseFirstCall() { releaseFirst.signal() }
}
