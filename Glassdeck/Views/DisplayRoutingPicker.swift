#if canImport(UIKit)
import GlassdeckCore
import SwiftUI

struct DisplayRoutingPicker: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Route to External Display") {
                    ForEach(sessionManager.sessions) { session in
                        Button {
                            sessionManager.routeToExternalDisplay(sessionID: session.id)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: session.isOnExternalDisplay ? "display" : "terminal")
                                Text(session.displayName)
                                Spacer()
                                if session.isOnExternalDisplay {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                if sessionManager.externalDisplaySessionID != nil {
                    Section {
                        Button("Clear External Display", role: .destructive) {
                            sessionManager.clearExternalDisplay()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("External Display")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetDismissButton()
                }
            }
        }
    }
}
#endif
