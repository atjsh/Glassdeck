import Foundation

public struct ArtifactIndexEntry: Codable, Sendable, Equatable {
    public let phase: String
    public let kind: String
    public let path: String
    public let timestamp: Date
    public let anomaly: String?

    public init(
        phase: String,
        kind: String,
        path: String,
        timestamp: Date,
        anomaly: String? = nil
    ) {
        self.phase = phase
        self.kind = kind
        self.path = path
        self.timestamp = timestamp
        self.anomaly = anomaly
    }
}

public struct ArtifactIndex: Codable, Sendable, Equatable {
    public static let currentVersion = "1.0"

    public let version: String
    public let command: String
    public let worker: String
    public let runId: String
    public let timestamp: Date
    public let completedAt: Date?
    public let entries: [ArtifactIndexEntry]

    public init(
        version: String = ArtifactIndex.currentVersion,
        command: String,
        worker: String,
        runId: String,
        timestamp: Date,
        completedAt: Date? = nil,
        entries: [ArtifactIndexEntry]
    ) {
        self.version = version
        self.command = command
        self.worker = worker
        self.runId = runId
        self.timestamp = timestamp
        self.completedAt = completedAt
        self.entries = entries
    }
}
