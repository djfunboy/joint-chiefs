import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Credential Store Tests")
struct CredentialStoreTests {

    /// A unique credentials-file URL inside a fresh temp directory, so tests
    /// never touch the real `~/Library/Application Support` store.
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jc-credstore-tests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("credentials.json")
    }

    // MARK: - Store and Retrieve

    @Test("Store then retrieve returns the stored key")
    func storeAndRetrieve() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CredentialStore.store(apiKey: "sk-test-12345", for: "openai", at: url)
        #expect(try CredentialStore.retrieve(for: "openai", at: url) == "sk-test-12345")
    }

    // MARK: - File Permissions

    @Test("Stored credentials file has 0600 permissions")
    func fileModeIs0600() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CredentialStore.store(apiKey: "sk-test", for: "openai", at: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
    }

    // MARK: - Atomic Multi-Account Write

    @Test("Storing a second account preserves the first")
    func storingSecondAccountKeepsFirst() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CredentialStore.store(apiKey: "openai-key", for: "openai", at: url)
        try CredentialStore.store(apiKey: "anthropic-key", for: "anthropic", at: url)

        #expect(try CredentialStore.retrieve(for: "openai", at: url) == "openai-key")
        #expect(try CredentialStore.retrieve(for: "anthropic", at: url) == "anthropic-key")
    }

    @Test("Re-storing the same account overwrites the value")
    func overwriteSameAccount() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CredentialStore.store(apiKey: "original", for: "grok", at: url)
        try CredentialStore.store(apiKey: "updated", for: "grok", at: url)

        #expect(try CredentialStore.retrieve(for: "grok", at: url) == "updated")
    }

    // MARK: - Missing File / Account

    @Test("Retrieve from a missing file throws itemNotFound")
    func retrieveMissingFile() {
        let url = tempURL()  // never created

        #expect(throws: CredentialStoreError.self) {
            try CredentialStore.retrieve(for: "openai", at: url)
        }
    }

    @Test("Retrieve a missing account throws itemNotFound")
    func retrieveMissingAccount() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CredentialStore.store(apiKey: "sk-test", for: "openai", at: url)
        do {
            _ = try CredentialStore.retrieve(for: "gemini", at: url)
            Issue.record("expected itemNotFound")
        } catch CredentialStoreError.itemNotFound {
            // expected — a missing account, not a damaged file
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Corrupt File

    @Test("Corrupt JSON throws ioFailed, not itemNotFound")
    func corruptFileThrowsIOFailed() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{ not valid json".utf8).write(to: url)

        do {
            _ = try CredentialStore.retrieve(for: "openai", at: url)
            Issue.record("expected ioFailed")
        } catch CredentialStoreError.ioFailed {
            // expected — a damaged file must be distinguishable from a missing key
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: - Delete

    @Test("Delete removes a key, leaving others intact")
    func deleteRemovesOnlyTheTargetKey() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CredentialStore.store(apiKey: "openai-key", for: "openai", at: url)
        try CredentialStore.store(apiKey: "grok-key", for: "grok", at: url)
        try CredentialStore.delete(for: "openai", at: url)

        #expect(CredentialStore.accountExists("openai", at: url) == false)
        #expect(try CredentialStore.retrieve(for: "grok", at: url) == "grok-key")
    }

    @Test("Deleting a missing account does not throw")
    func deleteMissingAccountIsNoOp() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CredentialStore.store(apiKey: "sk-test", for: "openai", at: url)
        try CredentialStore.delete(for: "gemini", at: url)  // no-op, no throw
    }

    // MARK: - accountExists

    @Test("accountExists reflects store and delete")
    func accountExistsTracksState() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(CredentialStore.accountExists("openai", at: url) == false)
        try CredentialStore.store(apiKey: "x", for: "openai", at: url)
        #expect(CredentialStore.accountExists("openai", at: url) == true)
        try CredentialStore.delete(for: "openai", at: url)
        #expect(CredentialStore.accountExists("openai", at: url) == false)
    }
}
