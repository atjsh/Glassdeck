import SwiftUI

/// Glass-effect overlay for AI assistant responses.
///
/// Shown as a sheet from the terminal view when the user taps
/// the AI sparkles button or long-presses selected text.
struct AIOverlayView: View {
    @State private var mode: AIMode = .suggestCommand
    @State private var inputText = ""
    @State private var result: String?
    @State private var isLoading = false

    enum AIMode: String, CaseIterable {
        case suggestCommand = "Suggest Command"
        case explainError = "Explain Error"
        case summarizeOutput = "Summarize Output"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Mode picker
                Picker("Mode", selection: $mode) {
                    ForEach(AIMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Input area
                VStack(alignment: .leading, spacing: 8) {
                    Text(inputPrompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $inputText)
                        .font(.body.monospaced())
                        .frame(minHeight: 80, maxHeight: 150)
                        .padding(8)
                        .glassEffect(.clear, in: .rect(cornerRadius: 12))
                }
                .padding(.horizontal)

                // Submit button
                Button {
                    Task { await runAI() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Ask AI")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .glassEffect(.regular.tint(.purple), in: .capsule)
                .padding(.horizontal)
                .disabled(inputText.isEmpty || isLoading)

                // Result area
                if let result {
                    ScrollView {
                        Text(result)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .padding()
                    }
                    .frame(maxHeight: .infinity)
                    .glassEffect(.clear, in: .rect(cornerRadius: 12))
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top)
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var inputPrompt: String {
        switch mode {
        case .suggestCommand: return "Describe what you want to do:"
        case .explainError: return "Paste the error output:"
        case .summarizeOutput: return "Paste the command output:"
        }
    }

    private func runAI() async {
        isLoading = true
        defer { isLoading = false }

        let assistant = AIAssistant()
        await assistant.prewarm()

        do {
            switch mode {
            case .suggestCommand:
                let suggestion = try await assistant.suggestCommand(from: inputText)
                result = "Command: \(suggestion.command)\n\nExplanation: \(suggestion.explanation)\n\nRisk: \(suggestion.riskLevel.rawValue)"
            case .explainError:
                let explanation = try await assistant.explainError(inputText)
                result = "Explanation: \(explanation.explanation)"
                if let fix = explanation.suggestedFix {
                    result! += "\n\nSuggested Fix: \(fix)"
                }
            case .summarizeOutput:
                result = try await assistant.summarizeOutput(inputText)
            }
        } catch {
            result = "Error: \(error.localizedDescription)"
        }
    }
}
