#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers
import GlassdeckCore

private struct SSHStoredKey: Identifiable {
    let id: String
    let name: String
    let publicKey: String

    var preview: String {
        let prefix = String(publicKey.prefix(44))
        return publicKey.count > 44 ? "\(prefix)…" : prefix
    }
}

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
                Section("Basics") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("connection-name-field")
                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("connection-host-field")
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("connection-port-field")
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("connection-username-field")
                }

                Section("Authentication") {
                    Picker("Method", selection: $authMethod) {
                        Text("Password").tag(AuthMethod.password)
                        Text("SSH Key").tag(AuthMethod.sshKey)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("connection-auth-method-picker")

                    if authMethod == .sshKey {
                        NavigationLink("Manage SSH Keys") {
                            SSHKeyListView(selectedKeyID: $selectedKeyID)
                        }
                        .accessibilityIdentifier("connection-manage-ssh-keys-button")
                        if let keyID = selectedKeyID {
                            Label(keyID, systemImage: "key.fill")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("connection-selected-ssh-key")
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
                    .accessibilityIdentifier("connection-save-button")
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
        if isCreating {
            let profile = ConnectionProfile(
                name: name,
                host: host,
                port: Int(port) ?? 22,
                username: username,
                authMethod: authMethod,
                sshKeyID: selectedKeyID,
                notes: AttributedString(notesText)
            )
            store.add(profile)
        } else {
            guard case .edit(let existingProfile) = mode else { return }
            let profile = ConnectionProfile(
                id: existingProfile.id,
                name: name,
                host: host,
                port: Int(port) ?? 22,
                username: username,
                authMethod: authMethod,
                sshKeyID: selectedKeyID,
                notes: AttributedString(notesText),
                lastConnected: existingProfile.lastConnected,
                createdAt: existingProfile.createdAt
            )
            store.update(profile)
        }
    }
}

/// SSH key management list with generate, import, and select.
struct SSHKeyListView: View {
    @Binding var selectedKeyID: String?
    @State private var keys: [SSHStoredKey] = []
    @State private var showGenerateSheet = false
    @State private var showFileImporter = false
    @State private var importError: String?

    var body: some View {
        List {
            Section {
                ForEach(keys) { key in
                    StoredKeyRow(
                        key: key,
                        isSelected: selectedKeyID == key.id
                    ) {
                        selectedKeyID = key.id
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
                .accessibilityIdentifier("ssh-key-generate-button")

                Button {
                    importFromClipboard()
                } label: {
                    Label("Import from Clipboard", systemImage: "doc.on.clipboard")
                }
                .accessibilityIdentifier("ssh-key-import-clipboard-button")

                Button {
                    showFileImporter = true
                } label: {
                    Label("Import from File", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("ssh-key-import-file-button")
            }
        }
        .navigationTitle("SSH Keys")
        .accessibilityIdentifier("ssh-key-list-view")
        .onAppear(perform: loadKeys)
        .sheet(isPresented: $showGenerateSheet) {
            GenerateKeyView { id, publicKey in
                keys.append(SSHStoredKey(id: id, name: id, publicKey: publicKey))
                selectedKeyID = id
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .plainText, .text]
        ) { result in
            switch result {
            case .success(let url):
                importFromFile(url)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert(
            "SSH Key Import Failed",
            isPresented: Binding(
                get: { importError != nil },
                set: { shown in
                    if !shown {
                        importError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                importError = nil
            }
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private func loadKeys() {
        let storedKeys = SSHKeyManager.shared.listKeysDetailed()
        keys = storedKeys.compactMap { key in
            guard let publicKey = try? SSHKeyManager.shared.publicKeyString(id: key.id) else { return nil }
            return SSHStoredKey(id: key.id, name: key.name, publicKey: publicKey)
        }
    }

    private func importFromClipboard() {
        guard let string = UIPasteboard.general.string else {
            importError = "Clipboard does not contain text."
            return
        }

        do {
            let result = try SSHKeyImportValidator.import(privateKeyData: Data(string.utf8))
            keys.append(SSHStoredKey(
                id: result.id,
                name: result.preview.name,
                publicKey: result.preview.publicKey
            ))
            selectedKeyID = result.id
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importFromFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let name = url.deletingPathExtension().lastPathComponent
            let result = try SSHKeyImportValidator.import(name: name, privateKeyData: data)
            keys.append(SSHStoredKey(
                id: result.id,
                name: result.preview.name,
                publicKey: result.preview.publicKey
            ))
            selectedKeyID = result.id
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct StoredKeyRow: View {
    let key: SSHStoredKey
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(key.name)
                        .font(.body.weight(.medium))
                    Text(key.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(key.preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
        .accessibilityIdentifier("ssh-key-row")
        .accessibilityElement(children: .combine)
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

#endif
