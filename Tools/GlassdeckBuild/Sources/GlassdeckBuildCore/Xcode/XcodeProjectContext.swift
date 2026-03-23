import Foundation

public struct XcodeProjectContext: Equatable, Sendable {
    public let workspace: WorkspaceContext
    public let projectPath: URL
    public let appBundleIdentifier: String
    public let appProductName: String
    public let defaultConfiguration: String
    public let defaultSimulatorName: String

    public init(
        workspace: WorkspaceContext = .current(),
        projectPath: URL? = nil,
        appBundleIdentifier: String = "com.atjsh.GlassdeckDev",
        appProductName: String = "Glassdeck",
        defaultConfiguration: String = "Debug",
        defaultSimulatorName: String = "iPhone 17"
    ) {
        self.workspace = workspace
        self.projectPath = projectPath ?? workspace.projectRoot.appendingPathComponent("GlassdeckApp.xcodeproj")
        self.appBundleIdentifier = appBundleIdentifier
        self.appProductName = appProductName
        self.defaultConfiguration = defaultConfiguration
        self.defaultSimulatorName = defaultSimulatorName
    }

    public func scheme(for selector: SchemeSelector) -> String {
        selector.schemeName
    }

    public func destinationSpecifier(simulatorIdentifier: String?) -> String {
        if let simulatorIdentifier, !simulatorIdentifier.isEmpty {
            return "platform=iOS Simulator,id=\(simulatorIdentifier)"
        }
        return "platform=iOS Simulator,name=\(defaultSimulatorName)"
    }

    public func builtAppPath(derivedDataPath: URL, configuration: String? = nil) -> URL {
        let resolvedConfiguration = configuration ?? defaultConfiguration
        return derivedDataPath
            .appendingPathComponent("Build/Products/\(resolvedConfiguration)-iphonesimulator")
            .appendingPathComponent("\(appProductName).app")
    }
}
