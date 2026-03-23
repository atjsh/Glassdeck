import Foundation

public enum SchemeSelector: Equatable, Sendable {
    case app
    case unit
    case ui
    case custom(String)

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "app", "glassdeckapp":
            self = .app
        case "unit", "glassdeckappunit":
            self = .unit
        case "ui", "glassdeckappui":
            self = .ui
        default:
            self = .custom(rawValue)
        }
    }

    public var schemeName: String {
        switch self {
        case .app:
            return "GlassdeckApp"
        case .unit:
            return "GlassdeckAppUnit"
        case .ui:
            return "GlassdeckAppUI"
        case let .custom(name):
            return name
        }
    }

    public var artifactRunID: String {
        switch self {
        case .app:
            return "app"
        case .unit:
            return "unit"
        case .ui:
            return "ui"
        case let .custom(name):
            return name
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
        }
    }
}
