import Testing
import Foundation
@testable import JointChiefsCore

@Suite("Keychain Service Tests")
struct KeychainServiceTests {

    private let testPrefix = "com.jointchiefs.test"

    private func makeTestAccount() -> String {
        "\(testPrefix).\(UUID().uuidString)"
    }

    private func cleanup(account: String) {
        try? KeychainService.delete(for: account)
    }

    // MARK: - Store and Retrieve

    @Test("Store and retrieve returns the stored API key")
    func storeAndRetrieve() throws {
        let account = makeTestAccount()
        defer { cleanup(account: account) }

        try KeychainService.store(apiKey: "sk-test-12345", for: account)
        let retrieved = try KeychainService.retrieve(for: account)
        #expect(retrieved == "sk-test-12345")
    }

    // MARK: - Retrieve Non-Existent

    @Test("Retrieve non-existent account throws itemNotFound")
    func retrieveNonExistent() {
        let account = makeTestAccount()

        #expect(throws: KeychainError.self) {
            try KeychainService.retrieve(for: account)
        }
    }

    // MARK: - Delete

    @Test("Delete removes the stored key")
    func deleteRemovesKey() throws {
        let account = makeTestAccount()
        defer { cleanup(account: account) }

        try KeychainService.store(apiKey: "sk-to-delete", for: account)
        try KeychainService.delete(for: account)

        #expect(throws: KeychainError.self) {
            try KeychainService.retrieve(for: account)
        }
    }

    // MARK: - Overwrite

    @Test("Storing twice overwrites with the new value")
    func overwriteExistingKey() throws {
        let account = makeTestAccount()
        defer { cleanup(account: account) }

        try KeychainService.store(apiKey: "original-key", for: account)
        try KeychainService.store(apiKey: "updated-key", for: account)

        let retrieved = try KeychainService.retrieve(for: account)
        #expect(retrieved == "updated-key")
    }

    // MARK: - Delete Non-Existent

    @Test("Deleting non-existent account does not throw")
    func deleteNonExistent() throws {
        let account = makeTestAccount()
        try KeychainService.delete(for: account)
    }
}
