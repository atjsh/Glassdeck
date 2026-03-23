import Foundation
@testable import GlassdeckBuildCore

struct ScriptedResponse {
    let result: ProcessResult
    let error: Error?

    init(result: ProcessResult, error: Error? = nil) {
        self.result = result
        self.error = error
    }
}

final class ScriptedProcessRunner: ProcessRunner {
    let responses: [ScriptedResponse]
    private(set) var calls: [ProcessInvocation] = []

    init(responses: [ScriptedResponse]) {
        self.responses = responses
    }

    func run(_ invocation: ProcessInvocation) async throws -> ProcessResult {
        calls.append(invocation)
        guard let response = responses[safe: calls.count - 1] else {
            throw ProcessRunnerError.launchFailed(NSError(domain: "ScriptedProcessRunner", code: 1))
        }
        if let error = response.error {
            throw error
        }
        return response.result
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
