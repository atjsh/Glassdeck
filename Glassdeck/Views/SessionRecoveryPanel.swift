#if canImport(UIKit)
import SwiftUI

struct SessionRecoveryState {
    let title: String
    let message: String
    let tint: Color
    let systemImage: String
}

struct SessionRecoveryPanel: View {
    let state: SessionRecoveryState
    let reconnect: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: state.systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(state.tint)

            VStack(spacing: 8) {
                Text(state.title)
                    .font(.title3.weight(.semibold))
                Text(state.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Reconnect", action: reconnect)
                    .buttonStyle(.borderedProminent)
                Button("Close", role: .destructive, action: close)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityIdentifier("session-recovery-panel")
    }
}
#endif
