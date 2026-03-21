import Foundation
@testable import GlassdeckCore
import XCTest

final class SSHReconnectManagerTests: XCTestCase {
    func testReconnectEventuallySucceeds() async throws {
        let manager = SSHReconnectManager(
            config: .init(
                maxAttempts: 3,
                initialDelay: 0.01,
                maxDelay: 0.01,
                backoffMultiplier: 1
            )
        )
        let recorder = ReconnectRecorder()
        let attempts = AttemptCounter(succeedOnAttempt: 2)
        let sessionID = UUID()

        await manager.startReconnecting(
            sessionID: sessionID,
            reconnect: {
                await attempts.performAttempt()
            },
            onStatusChange: { status in
                Task { await recorder.append(status) }
            }
        )

        try await Task.sleep(nanoseconds: 80_000_000)

        let recorded = await recorder.values
        XCTAssertEqual(
            recorded,
            [
                .attempting(attempt: 1, maxAttempts: 3),
                .attempting(attempt: 2, maxAttempts: 3),
                .reconnected,
            ]
        )
    }

    func testCancelStopsFurtherAttempts() async throws {
        let manager = SSHReconnectManager(
            config: .init(
                maxAttempts: 5,
                initialDelay: 0.1,
                maxDelay: 0.1,
                backoffMultiplier: 1
            )
        )
        let recorder = ReconnectRecorder()
        let attempted = AttemptCounter(succeedOnAttempt: nil)
        let sessionID = UUID()

        await manager.startReconnecting(
            sessionID: sessionID,
            reconnect: {
                await attempted.performAttempt()
            },
            onStatusChange: { status in
                Task { await recorder.append(status) }
            }
        )

        try await Task.sleep(nanoseconds: 20_000_000)
        await manager.cancelReconnecting(sessionID: sessionID)
        try await Task.sleep(nanoseconds: 40_000_000)

        let recorded = await recorder.values
        let performedAttempts = await attempted.performedAttempts
        XCTAssertEqual(recorded, [.attempting(attempt: 1, maxAttempts: 5)])
        XCTAssertEqual(performedAttempts, 0)
    }
}

private actor ReconnectRecorder {
    private var statuses: [SSHReconnectManager.ReconnectStatus] = []

    func append(_ status: SSHReconnectManager.ReconnectStatus) {
        statuses.append(status)
    }

    var values: [SSHReconnectManager.ReconnectStatus] {
        statuses
    }
}

private actor AttemptCounter {
    private let succeedOnAttempt: Int?
    private var attempts = 0

    init(succeedOnAttempt: Int?) {
        self.succeedOnAttempt = succeedOnAttempt
    }

    func performAttempt() -> Bool {
        attempts += 1
        return succeedOnAttempt == attempts
    }

    var performedAttempts: Int {
        attempts
    }
}
