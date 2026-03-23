import XCTest
@testable import GlassdeckCore

final class MockKeychainProvider: KeychainProvider, @unchecked Sendable {
    var items: [String: Data] = [:]
    var addCallCount = 0
    var deleteCallCount = 0
    var shouldFailAdd = false
    var shouldFailCopy = false

    func add(query: [String: Any]) -> OSStatus {
        addCallCount += 1
        if shouldFailAdd { return errSecDuplicateItem }
        if let account = query[kSecAttrAccount as String] as? String,
           let data = query[kSecValueData as String] as? Data {
            items[account] = data
        }
        return errSecSuccess
    }

    func delete(query: [String: Any]) -> OSStatus {
        deleteCallCount += 1
        if let account = query[kSecAttrAccount as String] as? String {
            items.removeValue(forKey: account)
        }
        return errSecSuccess
    }

    func copyMatching(query: [String: Any]) -> (OSStatus, AnyObject?) {
        if shouldFailCopy { return (errSecItemNotFound, nil) }
        // Handle "return data" queries
        if let returnData = query[kSecReturnData as String] as? Bool, returnData,
           let account = query[kSecAttrAccount as String] as? String {
            if let data = items[account] {
                return (errSecSuccess, data as AnyObject)
            }
            return (errSecItemNotFound, nil)
        }
        // Handle "return attributes" (list) queries
        if let returnAttrs = query[kSecReturnAttributes as String] as? Bool, returnAttrs {
            let attrs: [[String: Any]] = items.map { key, _ in
                [kSecAttrAccount as String: key, kSecAttrLabel as String: key]
            }
            return (errSecSuccess, attrs as AnyObject)
        }
        return (errSecItemNotFound, nil)
    }
}

final class SSHKeyManagerTests: XCTestCase {
    private var mockKeychain: MockKeychainProvider!
    private var keyManager: SSHKeyManager!

    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainProvider()
        keyManager = SSHKeyManager(keychainProvider: mockKeychain)
    }

    // Test: generate key stores in keychain
    func testGenerateEd25519KeyStoresInKeychain() throws {
        let keyID = try keyManager.generateEd25519Key(name: "test-key")
        XCTAssertFalse(keyID.isEmpty)
        XCTAssertFalse(mockKeychain.items.isEmpty, "Key should be stored in keychain")
    }

    // Test: import key validates and stores
    func testImportKeyValidatesAndStores() throws {
        // Generate a valid key first to get valid PEM data
        let keypair = SSHAuthenticator.generateEd25519Key()
        let keyID = try keyManager.importKey(name: "imported", pemData: keypair.privateKeyData)
        XCTAssertFalse(keyID.isEmpty)
        XCTAssertGreaterThanOrEqual(mockKeychain.addCallCount, 1)
    }

    // Test: load non-existent key returns nil
    func testLoadNonExistentKeyReturnsNil() {
        XCTAssertNil(keyManager.loadPrivateKey(id: "nonexistent"))
    }

    // Test: save and load roundtrip
    func testSaveAndLoadRoundtrip() throws {
        let testData = Data("test-key-data".utf8)
        keyManager.savePrivateKey(id: "roundtrip-key", keyData: testData)
        let loaded = keyManager.loadPrivateKey(id: "roundtrip-key")
        XCTAssertEqual(loaded, testData)
    }

    // Test: delete key removes from keychain
    func testDeleteKeyRemovesFromKeychain() throws {
        keyManager.savePrivateKey(id: "to-delete", keyData: Data("key".utf8))
        try keyManager.deleteKey(id: "to-delete")
        XCTAssertNil(keyManager.loadPrivateKey(id: "to-delete"))
    }

    // Test: list keys returns stored IDs
    func testListKeysReturnsStoredIDs() {
        keyManager.savePrivateKey(id: "key-1", keyData: Data("k1".utf8))
        keyManager.savePrivateKey(id: "key-2", keyData: Data("k2".utf8))
        let keys = keyManager.listKeys()
        XCTAssertTrue(keys.contains("key-1"))
        XCTAssertTrue(keys.contains("key-2"))
    }

    // Test: list keys detailed returns names
    func testListKeysDetailedReturnsNames() {
        keyManager.savePrivateKey(id: "named-key", keyData: Data("k".utf8))
        let detailed = keyManager.listKeysDetailed()
        XCTAssertFalse(detailed.isEmpty)
    }

    // Test: public key string from stored key
    func testPublicKeyStringFromStoredKey() throws {
        let keypair = SSHAuthenticator.generateEd25519Key()
        keyManager.savePrivateKey(id: "pub-test", keyData: keypair.privateKeyData)
        let pubKey = try keyManager.publicKeyString(id: "pub-test")
        XCTAssertFalse(pubKey.isEmpty)
    }

    // Test: public key for non-existent key throws
    func testPublicKeyForNonExistentKeyThrows() {
        XCTAssertThrowsError(try keyManager.publicKeyString(id: "no-such-key"))
    }

    // Test: keychain add failure
    func testKeychainAddFailurePropagates() {
        mockKeychain.shouldFailAdd = true
        // savePrivateKey should not crash (it logs instead of throwing)
        keyManager.savePrivateKey(id: "fail-key", keyData: Data("x".utf8))
        // The mock returns errSecDuplicateItem, storePrivateKey throws
    }

    // Test: overwrite existing key
    func testOverwriteExistingKey() {
        keyManager.savePrivateKey(id: "overwrite", keyData: Data("v1".utf8))
        keyManager.savePrivateKey(id: "overwrite", keyData: Data("v2".utf8))
        let loaded = keyManager.loadPrivateKey(id: "overwrite")
        XCTAssertEqual(loaded, Data("v2".utf8))
    }

    // Test: empty list when no keys
    func testEmptyListWhenNoKeys() {
        XCTAssertTrue(keyManager.listKeys().isEmpty)
    }

    // Test: delete non-existent key succeeds (errSecItemNotFound is OK)
    func testDeleteNonExistentKeySucceeds() {
        XCTAssertNoThrow(try keyManager.deleteKey(id: "ghost-key"))
    }

    // Additional edge case tests
    func testGenerateMultipleKeysHaveUniqueIDs() throws {
        let id1 = try keyManager.generateEd25519Key(name: "key-a")
        let id2 = try keyManager.generateEd25519Key(name: "key-b")
        XCTAssertNotEqual(id1, id2)
    }

    func testImportInvalidPEMDataThrows() {
        let invalidData = Data("not-a-valid-key".utf8)
        XCTAssertThrowsError(try keyManager.importKey(name: "bad", pemData: invalidData))
    }

    func testSavePrivateKeyWithEmptyData() {
        keyManager.savePrivateKey(id: "empty", keyData: Data())
        let loaded = keyManager.loadPrivateKey(id: "empty")
        XCTAssertEqual(loaded, Data())
    }

    func testCopyMatchingFailureReturnsNil() {
        mockKeychain.shouldFailCopy = true
        XCTAssertNil(keyManager.loadPrivateKey(id: "any"))
    }

    func testListKeysWhenCopyFails() {
        mockKeychain.shouldFailCopy = true
        XCTAssertTrue(keyManager.listKeys().isEmpty)
    }

    func testDeleteCallsKeychainDelete() throws {
        keyManager.savePrivateKey(id: "tracked", keyData: Data("x".utf8))
        let countBefore = mockKeychain.deleteCallCount
        try keyManager.deleteKey(id: "tracked")
        XCTAssertGreaterThan(mockKeychain.deleteCallCount, countBefore)
    }

    func testStoreCallsDeleteFirst() {
        // storePrivateKey deletes before adding (upsert)
        keyManager.savePrivateKey(id: "upsert", keyData: Data("v1".utf8))
        XCTAssertGreaterThanOrEqual(mockKeychain.deleteCallCount, 1)
    }

    func testListKeysDetailedWhenEmpty() {
        XCTAssertTrue(keyManager.listKeysDetailed().isEmpty)
    }
}
