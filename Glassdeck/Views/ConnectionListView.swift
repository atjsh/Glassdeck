#if canImport(UIKit)
import GlassdeckCore
import SwiftUI

private enum ConnectionsSheet: Identifiable {
    case newConnection
    case editConnection(ConnectionProfile)
    case sshKeys
    case settings
    case help

    var id: String {
        switch self {
        case .newConnection:
            "new-connection"
        case .editConnection(let profile):
            "edit-\(profile.id.uuidString)"
        case .sshKeys:
            "ssh-keys"
        case .settings:
            "settings"
        case .help:
            "help"
        }
    }
}

struct ConnectionsRootView: View {
    @Binding var selectedTab: AppRootTab
    @Binding var sessionsPath: [UUID]

    @Environment(ConnectionStore.self) private var store
    @Environment(SessionManager.self) private var sessionManager

    @State private var searchText = ""
    @State private var activeSheet: ConnectionsSheet?
    @State private var passwordPromptProfile: ConnectionProfile?
    @State private var pendingPassword = ""
    @State private var profilePendingDeletion: ConnectionProfile?

    private var filteredConnections: [ConnectionProfile] {
        store.connections
            .filter { profile in
                searchText.isEmpty
                    || profile.name.localizedCaseInsensitiveContains(searchText)
                    || profile.host.localizedCaseInsensitiveContains(searchText)
                    || profile.username.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.name.isEmpty ? lhs.host : lhs.name
                let rhsName = rhs.name.isEmpty ? rhs.host : rhs.name
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
    }

    private var recentConnections: [ConnectionProfile] {
        let recentIDs = Set(
            filteredConnections
                .filter { $0.lastConnected != nil }
                .sorted { ($0.lastConnected ?? .distantPast) > ($1.lastConnected ?? .distantPast) }
                .prefix(5)
                .map(\.id)
        )
        return filteredConnections.filter { recentIDs.contains($0.id) }
    }

    private var allConnections: [ConnectionProfile] {
        let recentIDs = Set(recentConnections.map(\.id))
        return filteredConnections.filter { !recentIDs.contains($0.id) }
    }

    private var appBackgroundColor: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredConnections.isEmpty, searchText.isEmpty {
                    GlassdeckEmptyState(
                        title: "No Connections",
                        systemImage: "server.rack",
                        message: "Add a host to start a session or import your existing SSH key setup.",
                        actionTitle: "New Connection"
                    ) {
                        activeSheet = .newConnection
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("connections-empty-state")
                } else if filteredConnections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if searchText.isEmpty, !recentConnections.isEmpty {
                            Section("Recent") {
                                ForEach(recentConnections) { profile in
                                    connectionButton(for: profile)
                                }
                            }
                        }

                        Section(searchText.isEmpty ? "All Connections" : "Results") {
                            ForEach(searchText.isEmpty ? allConnections : filteredConnections) { profile in
                                connectionButton(for: profile)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(appBackgroundColor)
                    .listStyle(.insetGrouped)
                    .accessibilityIdentifier("connections-list")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(appBackgroundColor)
            .navigationTitle("Connections")
            .searchable(text: $searchText, prompt: "Search by name, host, or user")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .newConnection
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("new-connection-button")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            activeSheet = .sshKeys
                        } label: {
                            Label("SSH Keys", systemImage: "key")
                        }
                        .accessibilityIdentifier("connections-menu-ssh-keys")

                        Button {
                            activeSheet = .settings
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier("connections-menu-settings")

                        Button {
                            activeSheet = .help
                        } label: {
                            Label("SSH Reference", systemImage: "book")
                        }
                        .accessibilityIdentifier("connections-menu-help")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("connections-toolbar-menu")
                }
            }
        }
        .background(appBackgroundColor)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .newConnection:
                ConnectionFormView(mode: .create)
                    .presentationDetents([.large])
            case .editConnection(let profile):
                ConnectionFormView(mode: .edit(profile))
                    .presentationDetents([.large])
            case .sshKeys:
                NavigationStack {
                    SSHKeyListView(selectedKeyID: .constant(nil))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                DismissButton()
                            }
                        }
                }
                .presentationDetents([.large])
            case .settings:
                TerminalSettingsView()
                    .presentationDetents([.large])
            case .help:
                HelpBrowserView()
                    .presentationDetents([.large])
            }
        }
        .sheet(item: $passwordPromptProfile) { profile in
            ConnectionPasswordSheet(
                profile: profile,
                password: $pendingPassword
            ) {
                let capturedPassword = pendingPassword
                pendingPassword = ""
                passwordPromptProfile = nil
                Task {
                    await launch(profile: profile, password: capturedPassword)
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Delete Connection?",
            isPresented: Binding(
                get: { profilePendingDeletion != nil },
                set: { showing in
                    if !showing {
                        profilePendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let profilePendingDeletion {
                Button("Delete", role: .destructive) {
                    store.delete(profilePendingDeletion)
                    self.profilePendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) {
                profilePendingDeletion = nil
            }
        } message: {
            Text("This removes the saved host from Glassdeck.")
        }
    }

    @ViewBuilder
    private func connectionButton(for profile: ConnectionProfile) -> some View {
        Button {
            open(profile: profile, createNewSession: false)
        } label: {
            ConnectionRow(profile: profile)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                open(profile: profile, createNewSession: true)
            } label: {
                Label("New Session", systemImage: "plus.rectangle.on.rectangle")
            }

            Button {
                activeSheet = .editConnection(profile)
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }

            Button(role: .destructive) {
                profilePendingDeletion = profile
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                activeSheet = .editConnection(profile)
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                profilePendingDeletion = profile
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                open(profile: profile, createNewSession: true)
            } label: {
                Label("New Session", systemImage: "plus.rectangle.on.rectangle")
            }
            .tint(.green)
        }
        .accessibilityIdentifier(connectionAccessibilityIdentifier(for: profile))
    }

    private func open(profile: ConnectionProfile, createNewSession: Bool) {
        if !createNewSession, let session = sessionManager.existingSession(for: profile) {
            sessionManager.setActiveSession(
                id: session.id,
                focusSurface: !UITestLaunchSupport.exposesTerminalRenderSummary
            )
            selectedTab = .sessions
            sessionsPath = [session.id]
            return
        }

        if profile.authMethod == .password {
            pendingPassword = ""
            passwordPromptProfile = profile
        } else {
            Task {
                await launch(profile: profile, password: nil)
            }
        }
    }

    private func launch(profile: ConnectionProfile, password: String?) async {
        guard let session = await sessionManager.connect(to: profile, password: password) else { return }
        if session.isConnected {
            store.recordConnection(id: profile.id)
        }
        sessionManager.setActiveSession(
            id: session.id,
            focusSurface: !UITestLaunchSupport.exposesTerminalRenderSummary
        )
        selectedTab = .sessions
        sessionsPath = [session.id]
    }
}

private func connectionAccessibilityIdentifier(for profile: ConnectionProfile) -> String {
    let title = profile.name.isEmpty ? profile.host : profile.name
    return "connection-row-\(accessibilitySlug(title))-\(accessibilitySlug(profile.host))"
}

private func accessibilitySlug(_ value: String) -> String {
    let normalized = value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

struct ConnectionRow: View {
    let profile: ConnectionProfile

    private var title: String {
        profile.name.isEmpty ? profile.host : profile.name
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(profile.username)@\(profile.host):\(profile.port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if !profile.notes.characters.isEmpty {
                    Text(String(profile.notes.characters))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let lastConnected = profile.lastConnected {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Recent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(lastConnected, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ConnectionPasswordSheet: View {
    let profile: ConnectionProfile
    @Binding var password: String
    let onConnect: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Password") {
                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("connection-password-field")
                }

                Section {
                    LabeledContent("Host", value: profile.host)
                    LabeledContent("User", value: profile.username)
                }
            }
            .navigationTitle("Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect", action: onConnect)
                        .disabled(password.isEmpty)
                        .accessibilityIdentifier("connection-password-connect-button")
                }
            }
        }
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") { dismiss() }
            .accessibilityIdentifier("dismiss-button")
    }
}
#endif
