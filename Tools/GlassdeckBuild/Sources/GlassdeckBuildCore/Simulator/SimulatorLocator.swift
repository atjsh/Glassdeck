import Foundation

public struct SimctlDevice: Sendable, Equatable {
    public let name: String
    public let identifier: String

    public init(name: String, identifier: String) {
        self.name = name
        self.identifier = identifier
    }
}

public enum SimulatorLocatorError: Error, Equatable {
    case noSimulatorFound(String)
    case ambiguousSimulatorName(String, [String])
    case invalidCommandOutput
}

extension SimulatorLocatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .noSimulatorFound(simulator):
            return "No simulator found for identifier or name: \(simulator)"
        case let .ambiguousSimulatorName(simulator, identifiers):
            return "Multiple simulators found for name \(simulator). Specify a UDID. Matches: \(identifiers.joined(separator: ", "))"
        case .invalidCommandOutput:
            return "Unable to parse simulator list from simctl output."
        }
    }
}

public struct SimulatorLocator {
    public let processRunner: ProcessRunner
    public let simctlExecutable: String

    public init(
        processRunner: ProcessRunner = DefaultProcessRunner(),
        simctlExecutable: String = "/usr/bin/env"
    ) {
        self.processRunner = processRunner
        self.simctlExecutable = simctlExecutable
    }

    public func availableDevices() async throws -> [SimctlDevice] {
        let invocation = ProcessInvocation(
            executable: simctlExecutable,
            arguments: ["xcrun", "simctl", "list", "devices", "available"]
        )
        let result = try await processRunner.run(invocation)

        let lines = result.standardOutput.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let parsed = parseDeviceLine(line)
            return parsed
        }
    }

    public func resolve(_ identifierOrName: String) async throws -> String {
        let devices = try await availableDevices()

        if isLikelyUDID(identifierOrName) {
            guard devices.contains(where: { $0.identifier == identifierOrName }) else {
                throw SimulatorLocatorError.noSimulatorFound(identifierOrName)
            }
            return identifierOrName
        }

        let exactMatches = devices
            .filter { $0.name == identifierOrName }
            .map(\.identifier)
        if exactMatches.count == 1, let match = exactMatches.first {
            return match
        }
        if exactMatches.count > 1 {
            throw SimulatorLocatorError.ambiguousSimulatorName(identifierOrName, exactMatches)
        }

        let lowered = identifierOrName.lowercased()
        if let fuzzy = devices.first(where: { $0.name.lowercased().contains(lowered) }) {
            return fuzzy.identifier
        }

        throw SimulatorLocatorError.noSimulatorFound(identifierOrName)
    }

    private func isLikelyUDID(_ identifier: String) -> Bool {
        let token = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 32 else { return false }
        let udidSet = CharacterSet(charactersIn: "0123456789abcdefABCDEF-")
        return token.unicodeScalars.allSatisfy { udidSet.contains($0) }
    }

    private func parseDeviceLine(_ line: String) -> SimctlDevice? {
        let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard candidate.first != "-" else { return nil }

        guard let opening = candidate.firstIndex(of: "("), let closing = candidate[opening...].firstIndex(of: ")") else {
            return nil
        }
        let name = String(candidate[..<opening]).trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return nil }

        let idToken = String(candidate[candidate.index(after: opening)..<closing])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyUDID(idToken) else { return nil }

        return SimctlDevice(name: name, identifier: idToken)
    }
}
