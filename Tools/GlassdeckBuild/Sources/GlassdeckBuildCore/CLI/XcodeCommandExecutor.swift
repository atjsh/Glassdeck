import Foundation

public struct XcodeCommandExecutor {
    public let context: CommandExecutionContext
    public let outputMode: ProcessOutputMode

    public init(
        context: CommandExecutionContext,
        outputMode: ProcessOutputMode = .captureAndStreamTimestampedFiltered(.xcodebuild)
    ) {
        self.context = context
        self.outputMode = outputMode
    }

    public func previewInvocation(for request: XcodeCommandRequest) -> ProcessInvocation {
        let previewRun = context.artifactPaths.makeRun(
            command: request.action.artifactCommand,
            runId: request.scheme.artifactRunID
        )
        return makeInvoker().makeInvocation(
            for: request,
            resultBundlePath: context.artifactPaths.paths(for: previewRun).resultBundle
        )
    }

    public func execute(_ request: XcodeCommandRequest) async throws -> XcodeRunResult {
        try await makeInvoker().execute(request)
    }

    private func makeInvoker() -> XcodeInvoker {
        XcodeInvoker(
            projectContext: context.projectContext,
            processRunner: context.processRunner,
            artifactPaths: context.artifactPaths,
            outputMode: outputMode
        )
    }
}
