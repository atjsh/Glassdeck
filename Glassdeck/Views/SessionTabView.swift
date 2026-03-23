import GlassdeckCore
import SwiftUI

struct SessionsRootView: View {
    @Binding var selectedTab: AppRootTab
    @Binding var sessionsPath: [UUID]

    @Environment(SessionManager.self) private var sessionManager

    private var activeSessions: [SSHSessionModel] {
        sessionManager.sessions
            .filter { session in
                switch session.status {
                case .connected, .connecting, .authenticating, .reconnecting:
                    true
                case .disconnected, .failed:
                    false
                }
            }
            .sorted(by: sortSessions)
    }

    private var inactiveSessions: [SSHSessionModel] {
        sessionManager.sessions
            .filter { session in
                switch session.status {
                case .disconnected, .failed:
                    true
                case .connected, .connecting, .authenticating, .reconnecting:
                    false
                }
            }
            .sorted(by: sortSessions)
    }

    var body: some View {
        NavigationStack(path: $sessionsPath) {
            Group {
                if sessionManager.sessions.isEmpty {
                    GlassdeckEmptyState(
                        title: "No Active Sessions",
                        systemImage: "rectangle.on.rectangle",
                        message: "Start from Connections and Glassdeck will keep your live sessions here.",
                        actionTitle: "Open Connections"
                    ) {
                        selectedTab = .connections
                    }
                    .accessibilityIdentifier("sessions-empty-state")
                } else {
                    List {
                        if !activeSessions.isEmpty {
                            Section("Active") {
                                ForEach(activeSessions) { session in
                                    sessionRow(for: session)
                                }
                            }
                        }

                        if !inactiveSessions.isEmpty {
                            Section("Inactive") {
                                ForEach(inactiveSessions) { session in
                                    sessionRow(for: session)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .accessibilityIdentifier("sessions-list")
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sessionManager.openNewTab()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("new-session-button")
                }
            }
            .navigationDestination(for: UUID.self) { sessionID in
                SessionDetailView(sessionID: sessionID)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(for session: SSHSessionModel) -> some View {
        NavigationLink(value: session.id) {
            SessionSummaryCard(
                session: session,
                isActive: session.id == sessionManager.activeSessionID
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                sessionManager.closeSession(id: session.id)
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if session.isConnected {
                Button {
                    sessionManager.disconnect(sessionID: session.id)
                } label: {
                    Label("Disconnect", systemImage: "bolt.slash")
                }
                .tint(.orange)
            } else {
                Button {
                    Task {
                        _ = await sessionManager.reconnect(sessionID: session.id)
                    }
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .tint(.green)
            }
        }
        .accessibilityIdentifier("session-card-\(session.id.uuidString)")
    }

    private func sortSessions(_ lhs: SSHSessionModel, _ rhs: SSHSessionModel) -> Bool {
        if lhs.isConnected != rhs.isConnected {
            return lhs.isConnected && !rhs.isConnected
        }
        return (lhs.connectedAt ?? .distantPast) > (rhs.connectedAt ?? .distantPast)
    }
}

private struct SessionSummaryCard: View {
    let session: SSHSessionModel
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(session.profile.username)@\(session.profile.host)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                SessionStatusBadge(
                    label: statusLabel,
                    systemImage: session.status.systemImage,
                    tint: statusTint
                )
            }

            HStack(spacing: 12) {
                Label("\(session.terminalSize.columns)x\(session.terminalSize.rows)", systemImage: "rectangle.split.3x1")
                if session.isOnExternalDisplay {
                    Label("External Display", systemImage: "display")
                }
                if let reconnect = session.reconnectState.label, !reconnect.isEmpty {
                    Label(reconnect, systemImage: "arrow.clockwise")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let message = session.connectionErrorMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isActive ? Color(uiColor: .secondarySystemGroupedBackground) : Color(uiColor: .systemBackground))
        )
        .accessibilityElement(children: .combine)
    }

    private var statusLabel: String {
        switch session.status {
        case .connected:
            "Connected"
        case .connecting:
            "Connecting"
        case .authenticating:
            "Authenticating"
        case .reconnecting:
            "Reconnecting"
        case .disconnected:
            "Disconnected"
        case .failed:
            "Failed"
        }
    }

    private var statusTint: Color {
        switch session.status {
        case .connected:
            .green
        case .connecting, .authenticating:
            .blue
        case .reconnecting:
            .orange
        case .disconnected:
            .secondary
        case .failed:
            .red
        }
    }
}
