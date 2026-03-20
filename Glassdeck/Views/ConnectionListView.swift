import SwiftUI

/// Connection list with iOS 26 section indexes for alphabetical navigation.
struct ConnectionListView: View {
    @Binding var selection: ConnectionProfile?
    @Environment(ConnectionStore.self) private var store
    @State private var searchText = ""
    @State private var showingNewConnection = false

    private var groupedConnections: [(String, [ConnectionProfile])] {
        let filtered = store.connections.filter { profile in
            searchText.isEmpty ||
            profile.name.localizedCaseInsensitiveContains(searchText) ||
            profile.host.localizedCaseInsensitiveContains(searchText)
        }
        let grouped = Dictionary(grouping: filtered) { profile in
            String(profile.name.prefix(1)).uppercased()
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(groupedConnections, id: \.0) { letter, connections in
                Section(letter) {
                    ForEach(connections) { profile in
                        ConnectionRow(profile: profile)
                            .tag(profile)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search connections")
        .navigationTitle("Connections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewConnection = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewConnection) {
            ConnectionFormView(mode: .create)
        }
    }
}

struct ConnectionRow: View {
    let profile: ConnectionProfile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.medium))
                Text("\(profile.username)@\(profile.host):\(profile.port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastConnected = profile.lastConnected {
                Text(lastConnected, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
