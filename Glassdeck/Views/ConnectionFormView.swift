import SwiftUI

/// Form for creating or editing a connection profile.
/// Uses iOS 26 rich TextEditor for connection notes.
struct ConnectionFormView: View {
    enum Mode {
        case create
        case edit(ConnectionProfile)
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionStore.self) private var store

    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod: AuthMethod = .password
    @State private var notes = AttributedString()

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name)
                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                }

                Section("Authentication") {
                    Picker("Method", selection: $authMethod) {
                        Text("Password").tag(AuthMethod.password)
                        Text("SSH Key").tag(AuthMethod.sshKey)
                    }

                    if authMethod == .sshKey {
                        NavigationLink("Manage SSH Keys") {
                            SSHKeyListView()
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle(isCreating ? "New Connection" : "Edit Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreating ? "Add" : "Save") {
                        save()
                        dismiss()
                    }
                    .disabled(name.isEmpty || host.isEmpty || username.isEmpty)
                }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private func loadExisting() {
        if case .edit(let profile) = mode {
            name = profile.name
            host = profile.host
            port = String(profile.port)
            username = profile.username
            authMethod = profile.authMethod
            notes = profile.notes
        }
    }

    private func save() {
        let profile = ConnectionProfile(
            name: name,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authMethod: authMethod,
            notes: notes
        )
        if isCreating {
            store.add(profile)
        } else {
            store.update(profile)
        }
    }
}

/// Placeholder for SSH key management view
struct SSHKeyListView: View {
    var body: some View {
        Text("SSH Key Management")
            .navigationTitle("SSH Keys")
    }
}
