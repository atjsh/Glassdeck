#if canImport(UIKit)
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import GlassdeckCore

struct SFTPPreviewDocument: Identifiable, Equatable {
    let path: String
    let name: String
    let text: String
    let isTruncated: Bool
    var exportURL: URL?

    var id: String { path }
}

private enum SFTPBrowserRoute: Hashable {
    case directory(path: String)
}

@MainActor
@Observable
final class SFTPBrowserModel {
    let profile: ConnectionProfile
    private let manager: any SFTPManaging

    var connectionID: UUID?
    var connectionStatus: SFTPConnectionStatus = .disconnected
    var currentPath = "."
    var entries: [SFTPBrowserEntry] = []
    var password = ""
    var isLoading = false
    var errorMessage: String?
    var previewDocument: SFTPPreviewDocument?

    var title: String {
        profile.name.isEmpty ? profile.host : profile.name
    }

    var requiresPassword: Bool {
        profile.authMethod == .password && connectionID == nil
    }

    var canGoUp: Bool {
        Self.parentPath(of: currentPath) != nil
    }

    init(
        profile: ConnectionProfile,
        password: String = "",
        manager: any SFTPManaging = SFTPManager()
    ) {
        self.profile = profile
        self.password = password
        self.manager = manager
    }

    func bootstrap() async {
        guard connectionID == nil else { return }
        guard profile.authMethod == .sshKey || !password.isEmpty else { return }
        await connect()
    }

    func connect() async {
        isLoading = true
        errorMessage = nil
        connectionStatus = .connecting

        do {
            let id = try await manager.connect(to: profile, password: password.isEmpty ? nil : password)
            connectionID = id
            currentPath = "."
            password = ""
            try await load(path: currentPath)
        } catch {
            connectionStatus = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func load(path: String) async throws {
        guard let connectionID else {
            throw SFTPManagerError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        let listing = try await manager.browse(connectionID: connectionID, at: path)
        currentPath = listing.path
        entries = listing.entries
        if let status = await manager.status(for: connectionID) {
            connectionStatus = status
        }
    }

    func open(_ entry: SFTPBrowserEntry) async {
        if entry.isDirectory {
            do {
                try await load(path: entry.path)
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        await preview(entry)
    }

    func preview(_ entry: SFTPBrowserEntry) async {
        guard let connectionID else {
            errorMessage = SFTPManagerError.notConnected.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let preview = try await manager.previewText(
                connectionID: connectionID,
                at: entry.path,
                maxBytes: 8_192
            )
            previewDocument = SFTPPreviewDocument(
                path: entry.path,
                name: entry.name,
                text: preview.text,
                isTruncated: preview.isTruncated,
                exportURL: nil
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func goUp() async {
        guard let parent = Self.parentPath(of: currentPath) else { return }
        do {
            try await load(path: parent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            try await load(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() async {
        guard let connectionID else { return }
        await manager.disconnect(id: connectionID)
        await manager.remove(id: connectionID)
        self.connectionID = nil
        connectionStatus = .disconnected
        entries = []
        currentPath = "."
        previewDocument = nil
    }

    func uploadFile(from url: URL) async {
        guard let connectionID else {
            errorMessage = SFTPManagerError.notConnected.localizedDescription
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: url)
            let destinationPath = Self.remotePath(
                in: currentPath,
                child: url.lastPathComponent
            )
            try await manager.upload(
                connectionID: connectionID,
                data: data,
                to: destinationPath
            )
            try await load(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: SFTPBrowserEntry) async {
        guard let connectionID else {
            errorMessage = SFTPManagerError.notConnected.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await manager.delete(
                connectionID: connectionID,
                at: entry.path,
                isDirectory: entry.isDirectory
            )
            if previewDocument?.path == entry.path {
                previewDocument = nil
            }
            try await load(path: currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareExportForPreview() async {
        guard let connectionID, let previewDocument else {
            errorMessage = SFTPManagerError.notConnected.localizedDescription
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let blob = try await manager.download(
                connectionID: connectionID,
                at: previewDocument.path
            )
            self.previewDocument?.exportURL = try Self.writeTemporaryFile(
                data: blob.data,
                suggestedName: previewDocument.name
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearPreview() {
        previewDocument = nil
    }

    private static func parentPath(of path: String) -> String? {
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.isEmpty || path == "/" || path == "." {
            return nil
        }

        if path.hasSuffix("/") {
            return parentPath(of: String(path.dropLast()))
        }

        if path.hasPrefix("/") {
            guard let slash = normalized.lastIndex(of: "/") else { return "/" }
            let parent = String(normalized[..<slash])
            return parent.isEmpty ? "/" : "/\(parent)"
        }

        guard let slash = normalized.lastIndex(of: "/") else {
            return "."
        }

        let parent = String(normalized[..<slash])
        return parent.isEmpty ? "." : parent
    }

    private static func remotePath(in directory: String, child: String) -> String {
        if directory.isEmpty || directory == "." {
            return child
        }

        if directory == "/" {
            return "/\(child)"
        }

        if directory.hasSuffix("/") {
            return directory + child
        }

        return "\(directory)/\(child)"
    }

    private static func writeTemporaryFile(
        data: Data,
        suggestedName: String
    ) throws -> URL {
        let safeName = suggestedName.isEmpty ? "download" : suggestedName
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassdeckSFTP", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let finalURL = directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")

        try data.write(to: finalURL, options: .atomic)
        return finalURL
    }
}

struct SFTPBrowserView: View {
    @State private var model: SFTPBrowserModel
    @State private var showUploadImporter = false
    @State private var navigationPath: [SFTPBrowserRoute] = []
    private let initialPath: String
    private let shouldBootstrap: Bool

    init(
        profile: ConnectionProfile,
        password: String = "",
        manager: any SFTPManaging = SFTPManager()
    ) {
        _model = State(initialValue: SFTPBrowserModel(profile: profile, password: password, manager: manager))
        initialPath = "."
        shouldBootstrap = true
    }

    private init(model: SFTPBrowserModel, path: String) {
        _model = State(initialValue: model)
        initialPath = path
        shouldBootstrap = false
    }

    private func restorePathIfNeeded() {
        guard shouldBootstrap || model.connectionID != nil else { return }
        guard model.currentPath != initialPath else { return }

        Task {
            do {
                try await model.load(path: initialPath)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    statusHeader
                }

                if model.connectionID == nil {
                    connectSection
                } else {
                    currentPathSection
                    if model.isLoading {
                        loadingSection
                    }
                    contentSection
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("sftp-browser-view")
            .navigationDestination(for: SFTPBrowserRoute.self, destination: destinationView)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showUploadImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(model.connectionID == nil)

                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.connectionID == nil)

                    Button {
                        Task { await model.goUp() }
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(!model.canGoUp)

                    Button(role: .destructive) {
                        Task { await model.disconnect() }
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(model.connectionID == nil)
                }
            }
            .task {
                if shouldBootstrap {
                    await model.bootstrap()
                }
                restorePathIfNeeded()
            }
            .fileImporter(
                isPresented: $showUploadImporter,
                allowedContentTypes: [.data, .content, .item]
            ) { result in
                switch result {
                case .success(let url):
                    Task { await model.uploadFile(from: url) }
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { model.previewDocument != nil },
                    set: { shown in
                        if !shown {
                            model.clearPreview()
                        }
                    }
                )
            ) {
                NavigationStack {
                    if let preview = model.previewDocument {
                        ScrollView {
                            Text(preview.text)
                                .font(.body.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()

                            if preview.isTruncated {
                                Text("Preview truncated to the first 8 KB.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                            }
                        }
                        .navigationTitle(preview.name)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    model.clearPreview()
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                if let exportURL = preview.exportURL {
                                    ShareLink(item: exportURL) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                } else {
                                    Button {
                                        Task { await model.prepareExportForPreview() }
                                    } label: {
                                        Image(systemName: "square.and.arrow.down")
                                    }
                                }
                            }
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .alert(
                "SFTP Error",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { shown in
                        if !shown {
                            model.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.errorMessage = nil
                }
            } message: {
                Text(model.errorMessage ?? "Unknown error")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sftp-browser-view")
    }

    @ViewBuilder
    private var connectSection: some View {
        Section("Connect") {
            if model.requiresPassword {
                SecureField("Password", text: $model.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Connect") {
                    Task { await model.connect() }
                }
                .disabled(model.password.isEmpty)
            } else {
                Button {
                    Task { await model.connect() }
                } label: {
                    Label("Connect", systemImage: "network")
                }
            }
        }
    }

    @ViewBuilder
    private var currentPathSection: some View {
        Section("Current Path") {
            Text(model.currentPath)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        Section {
            ProgressView("Loading directory")
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        Section("Contents") {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    "Empty Directory",
                    systemImage: "folder",
                    description: Text("No files were returned for this path.")
                )
            } else {
                ForEach(model.entries) { entry in
                    entryRow(for: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(for entry: SFTPBrowserEntry) -> some View {
        Group {
            if entry.isDirectory {
                NavigationLink(value: SFTPBrowserRoute.directory(path: entry.path)) {
                    SFTPBrowserRow(entry: entry)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await model.open(entry) }
                } label: {
                    SFTPBrowserRow(entry: entry)
                }
                .buttonStyle(.plain)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await model.delete(entry) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func destinationView(for route: SFTPBrowserRoute) -> some View {
        switch route {
        case .directory(let path):
            SFTPBrowserView(model: model, path: path)
        }
    }

    @ViewBuilder
    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusTint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.body.weight(.medium))
                Text("\(model.profile.username)@\(model.profile.host):\(model.profile.port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var statusIcon: String {
        switch model.connectionStatus {
        case .connecting, .authenticating:
            return "hourglass"
        case .connected:
            return "folder.fill"
        case .disconnecting:
            return "arrow.right.circle"
        case .disconnected:
            return "network.slash"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var statusText: String {
        switch model.connectionStatus {
        case .connecting:
            return "Connecting"
        case .authenticating:
            return "Authenticating"
        case .connected:
            return "Connected"
        case .disconnecting:
            return "Disconnecting"
        case .disconnected:
            return "Disconnected"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    private var statusTint: Color {
        switch model.connectionStatus {
        case .connected:
            return .green
        case .failed:
            return .red
        case .connecting, .authenticating, .disconnecting:
            return .orange
        case .disconnected:
            return .secondary
        }
    }
}

private struct SFTPBrowserRow: View {
    let entry: SFTPBrowserEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body.weight(.medium))

                if let size = entry.fileSize {
                    Text(detailText(for: size))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else if !entry.longName.isEmpty {
                    Text(entry.longName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let date = entry.modificationDate {
                Text(date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func detailText(for size: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

#endif
