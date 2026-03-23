import Foundation

public struct ArtifactIndexBuilder {
    public let command: String
    public let worker: String
    public let run: ArtifactRun
    public let startedAt: Date
    public let clock: @Sendable () -> Date

    private var checkpoints: [ArtifactIndexEntry]

    public init(
        command: String,
        worker: String,
        run: ArtifactRun,
        startedAt: Date? = nil,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.command = command
        self.worker = worker
        self.run = run
        self.startedAt = startedAt ?? Date()
        self.clock = clock
        self.checkpoints = []
    }

    public mutating func record(
        phase: String,
        kind: String,
        relativePath: String,
        anomaly: String? = nil,
        timestamp: Date? = nil
    ) {
        checkpoints.append(
            ArtifactIndexEntry(
                phase: phase,
                kind: kind,
                path: relativePath,
                timestamp: timestamp ?? clock(),
                anomaly: anomaly
            )
        )
    }

    public mutating func merge(
        _ other: [ArtifactIndexEntry]
    ) {
        checkpoints.append(contentsOf: other)
    }

    public func build(completedAt: Date? = nil) -> ArtifactIndex {
        ArtifactIndex(
            command: command,
            worker: worker,
            runId: run.identifier,
            timestamp: startedAt,
            completedAt: completedAt,
            entries: checkpoints
        )
    }
}
