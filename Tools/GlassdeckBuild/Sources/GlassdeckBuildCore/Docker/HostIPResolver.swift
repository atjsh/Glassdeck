import Foundation

public enum HostIPResolverError: Error, LocalizedError {
    case missingInterface
    case unresolvedHost

    public var errorDescription: String? {
        switch self {
        case .missingInterface:
            "No default network interface could be detected."
        case .unresolvedHost:
            "Unable to resolve LAN IP for Docker SSH fixture."
        }
    }
}

public final class HostIPResolver {
    public let processRunner: ProcessRunner
    public let routeExecutable: String
    public let ipconfigExecutable: String
    public let ifconfigExecutable: String

    public init(
        processRunner: ProcessRunner = DefaultProcessRunner(),
        routeExecutable: String = "/usr/bin/env",
        ipconfigExecutable: String = "/usr/bin/env",
        ifconfigExecutable: String = "/usr/bin/env"
    ) {
        self.processRunner = processRunner
        self.routeExecutable = routeExecutable
        self.ipconfigExecutable = ipconfigExecutable
        self.ifconfigExecutable = ifconfigExecutable
    }

    public func resolveLANIP() async throws -> String {
        if let resolved = try await resolveFromDefaultRoute() {
            return resolved
        }
        if let resolved = try await resolveFromIfconfigScan() {
            return resolved
        }
        throw HostIPResolverError.unresolvedHost
    }

    public func resolveFromDefaultRoute() async throws -> String? {
        let routeInvocation = ProcessInvocation(
            executable: routeExecutable,
            arguments: ["route", "-n", "get", "default"]
        )
        let routeOutput = try await processRunner.run(routeInvocation).standardOutput
        guard let interface = parseDefaultInterface(from: routeOutput) else {
            return nil
        }
        let ipconfigInvocation = ProcessInvocation(
            executable: ipconfigExecutable,
            arguments: ["ipconfig", "getifaddr", interface]
        )
        let ipOutput = try await processRunner.run(ipconfigInvocation).standardOutput
        let candidate = ipOutput
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func resolveFromIfconfigScan() async throws -> String? {
        let ifconfigInvocation = ProcessInvocation(
            executable: ifconfigExecutable,
            arguments: ["ifconfig"]
        )
        let output = try await processRunner.run(ifconfigInvocation).standardOutput
        return parseIPv4Address(from: output)
    }

    private func parseDefaultInterface(from output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("interface:") {
                let parts = line.split(separator: ":")
                guard parts.count == 2 else { continue }
                let candidate = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }
        return nil
    }

    private func parseIPv4Address(from output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let fields = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            guard fields.first == "inet" else { continue }
            guard fields.count > 1 else { continue }
            let candidate = String(fields[1])
            if candidate != "127.0.0.1" && isLikelyIPv4(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func isLikelyIPv4(_ candidate: String) -> Bool {
        let pieces = candidate.split(separator: ".")
        guard pieces.count == 4 else { return false }
        return pieces.allSatisfy { piece in
            if let value = Int(piece), value >= 0, value <= 255 { return true }
            return false
        }
    }
}
