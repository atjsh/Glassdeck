import Foundation

/// On-device AI assistant using the Foundation Models framework.
///
/// Provides "explain error", "suggest command", and "summarize output"
/// capabilities — fully private, runs on iPhone 15 Pro's neural engine.
///
/// NOTE: Requires iOS 26+ and Apple Intelligence enabled on device.
/// Import FoundationModels when building with Xcode 26 SDK.
actor AIAssistant {
    private var isPrewarmed = false

    /// Prewarm the language model for faster first-token response.
    /// Call when terminal view appears.
    func prewarm() async {
        guard !isPrewarmed else { return }

        // TODO: Uncomment when building with Xcode 26 SDK
        // import FoundationModels
        // try? await LanguageModelSession.prewarm()

        isPrewarmed = true
    }

    /// Check if on-device AI is available.
    var isAvailable: Bool {
        // TODO: Check SystemLanguageModel.default.availability
        // return SystemLanguageModel.default.availability == .available
        return false
    }

    /// Explain a terminal error message.
    func explainError(_ errorOutput: String) async throws -> ErrorExplanation {
        // TODO: Use LanguageModelSession with guided generation
        // let session = LanguageModelSession()
        // let response = try await session.respond(
        //     to: "Explain this terminal error and suggest a fix: \(errorOutput)",
        //     generating: ErrorExplanation.self
        // )
        // return response.content

        return ErrorExplanation(
            explanation: "AI features require iOS 26 with Apple Intelligence enabled.",
            suggestedFix: nil,
            severity: .info
        )
    }

    /// Generate a shell command from natural language.
    func suggestCommand(from description: String) async throws -> CommandSuggestion {
        // TODO: Use LanguageModelSession with guided generation
        // let session = LanguageModelSession()
        // let response = try await session.respond(
        //     to: "Generate a shell command for: \(description)",
        //     generating: CommandSuggestion.self
        // )
        // return response.content

        return CommandSuggestion(
            command: "# AI features require iOS 26",
            explanation: "On-device AI is not available in this build.",
            riskLevel: .safe
        )
    }

    /// Summarize long command output.
    func summarizeOutput(_ output: String) async throws -> String {
        // TODO: Use LanguageModelSession
        return "AI summarization requires iOS 26 with Apple Intelligence enabled."
    }
}

// MARK: - @Generable structs for structured AI output

/// Structured error explanation from AI.
/// TODO: Add @Generable macro when building with Xcode 26 SDK
struct ErrorExplanation: Sendable, Codable {
    let explanation: String
    let suggestedFix: String?
    let severity: Severity

    enum Severity: String, Sendable, Codable, CaseIterable {
        case critical
        case warning
        case info
    }
}

/// Structured command suggestion from AI.
/// TODO: Add @Generable macro when building with Xcode 26 SDK
struct CommandSuggestion: Sendable, Codable {
    let command: String
    let explanation: String
    let riskLevel: RiskLevel

    enum RiskLevel: String, Sendable, Codable, CaseIterable {
        case safe
        case moderate
        case dangerous
    }
}
