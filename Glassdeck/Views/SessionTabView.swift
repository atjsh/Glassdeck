import SwiftUI

/// Multi-session tab view using iOS 26 enhanced TabView with
/// minimize-on-scroll and glass accessories.
struct SessionTabView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var selectedSessionID: UUID?

    var body: some View {
        TabView(selection: $selectedSessionID) {
            ForEach(sessionManager.sessions) { session in
                TerminalSurfaceView(session: session)
                    .tabItem {
                        Label(
                            session.displayName,
                            systemImage: session.isConnected
                                ? "terminal.fill"
                                : "terminal"
                        )
                    }
                    .tag(session.id)
            }
        }
        .onChange(of: selectedSessionID) { _, newValue in
            if let id = newValue {
                sessionManager.setActiveSession(id: id)
            }
        }
    }
}
