import Foundation

public struct WorkerScope: Equatable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String? = nil) {
        self.id = max(id, 0)
        self.name = name ?? "worker-\(id)"
    }

    public static let `default` = WorkerScope(id: 0)

    public var slug: String {
        name.isEmpty ? "worker-\(id)" : name
    }
}
