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
    @State private var selectedKeyID: String?
    @State private var notesText = ""

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
                            SSHKeyListView(selectedKeyID: $selectedKeyID)
                        }
                        if let keyID = selectedKeyID {
                            Label(keyID, systemImage: "key.fill")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notesText)
                        .font(.body)
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
            selectedKeyID = profile.sshKeyID
            notesText = String(profile.notes.characters)
        }
    }

    private func save() {
        let profile = ConnectionProfile(
            name: name,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authMethod: authMethod,
            sshKeyID: selectedKeyID,
            notes: AttributedString(notesText)
        )
        if isCreating {
            store.add(profile)
        } else {
            store.update(profile)
        }
    }
}

/// SSH key management list with generate, import, and select.
struct SSHKeyListView: View {
    @Binding var selectedKeyID: String?
    @State private var keys: [(id: String, publicKey: String)] = []
    @State private var showGenerateSheet = false

    var body: some View {
        List {
            Section {
                ForEach(keys, id: \.id) { key in
                    Button {
                        selectedKeyID = key.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key.id)
                                    .font(.body.weight(.medium))
                                Text(key.publicKey.prefix(44) + "…")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if selectedKeyID == key.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            } header: {
                Text("Stored Keys")
            }

            Section {
                Button {
                    showGenerateSheet = true
                } label: {
                    Label("Generate New Key", systemImage: "plus.circle")
                }

                Button {
                    // TODO: Import from clipboard or file
                } label: {
                    Label("Import from Clipboard", systemImage: "doc.on.clipboard")
                }
            }
        }
        .navigationTitle("SSH Keys")
        .onAppear(perform: loadKeys)
        .sheet(isPresented: $showGenerateSheet) {
            GenerateKeyView { id, publicKey in
                keys.append((id: id, publicKey: publicKey))
                selectedKeyID = id
            }
        }
    }

    private func loadKeys() {
        let keyIDs = SSHKeyManager.shared.listKeys()
        keys = keyIDs.compactMap { id in
            guard let data = SSHKeyManager.shared.loadPrivateKey(id: id) else { return nil }
            return (id: id, publicKey: "(Ed25519 key, \(data.count) bytes)")
        }
    }
}

/// Sheet for generating a new SSH keypair.
struct GenerateKeyView: View {
    let onGenerate: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var keyName = ""
    @State private var keyType = "ed25519"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Key Name", text: $keyName)
                    .textInputAutocapitalization(.never)
                Picker("Algorithm", selection: $keyType) {
                    Text("Ed25519 (Recommended)").tag("ed25519")
                    Text("ECDSA P-256").tag("p256")
                }
            }
            .navigationTitle("Generate SSH Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") {
                        let result: (publicKey: String, privateKeyData: Data)
                        if keyType == "ed25519" {
                            result = SSHAuthenticator.generateEd25519Key()
                        } else {
                            result = SSHAuthenticator.generateP256Key()
                        }
                        let id = keyName.isEmpty ? "key-\(UUID().uuidString.prefix(8))" : keyName
                        SSHKeyManager.shared.savePrivateKey(id: id, keyData: result.privateKeyData)
                        onGenerate(id, result.publicKey)
                        dismiss()
                    }
                    .disabled(keyName.isEmpty)
                }
            }
        }
    }
}
