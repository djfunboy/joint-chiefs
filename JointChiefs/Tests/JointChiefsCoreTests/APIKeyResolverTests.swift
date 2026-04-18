import Testing
import Foundation
@testable import JointChiefsCore

@Suite("API Key Resolver Tests", .serialized)
struct APIKeyResolverTests {

    // MARK: - ProviderType helpers

    @Test("ProviderType maps to expected env var names")
    func envVarNames() {
        #expect(ProviderType.openAI.envVarName == "OPENAI_API_KEY")
        #expect(ProviderType.anthropic.envVarName == "ANTHROPIC_API_KEY")
        #expect(ProviderType.gemini.envVarName == "GEMINI_API_KEY")
        #expect(ProviderType.grok.envVarName == "GROK_API_KEY")
        #expect(ProviderType.ollama.envVarName == "OLLAMA_API_KEY")
    }

    @Test("Ollama has no keychain account (local-only, no credential)")
    func ollamaNoKeychainAccount() {
        #expect(ProviderType.ollama.keychainAccount == nil)
    }

    @Test("Remote providers map to stable keychain account names")
    func keychainAccountNames() {
        #expect(ProviderType.openAI.keychainAccount == "openai")
        #expect(ProviderType.anthropic.keychainAccount == "anthropic")
        #expect(ProviderType.gemini.keychainAccount == "gemini")
        #expect(ProviderType.grok.keychainAccount == "grok")
    }

    // MARK: - Env var precedence

    @Test("Env var value takes precedence over keygetter")
    func envVarPrecedence() throws {
        // Point keygetter at a script that ALWAYS prints a different value.
        // If env-var precedence works, that script never gets invoked.
        let fake = try makeFakeKeygetter(outputKey: "from-keygetter")
        defer { try? FileManager.default.removeItem(atPath: fake) }

        setenv("JOINTCHIEFS_KEYGETTER_PATH", fake, 1)
        setenv("OPENAI_API_KEY", "from-env", 1)
        defer {
            unsetenv("JOINTCHIEFS_KEYGETTER_PATH")
            unsetenv("OPENAI_API_KEY")
        }

        let key = try APIKeyResolver.resolve(.openAI)
        #expect(key == "from-env")
    }

    @Test("Resolver falls through to keygetter when env var is unset")
    func keygetterFallback() throws {
        let fake = try makeFakeKeygetter(outputKey: "sk-from-kg-12345")
        defer { try? FileManager.default.removeItem(atPath: fake) }

        unsetenv("OPENAI_API_KEY")
        setenv("JOINTCHIEFS_KEYGETTER_PATH", fake, 1)
        defer { unsetenv("JOINTCHIEFS_KEYGETTER_PATH") }

        let key = try APIKeyResolver.resolve(.openAI)
        #expect(key == "sk-from-kg-12345")
    }

    @Test("Empty env var is treated as unset and falls through to keygetter")
    func emptyEnvVarFallsThrough() throws {
        let fake = try makeFakeKeygetter(outputKey: "from-keygetter")
        defer { try? FileManager.default.removeItem(atPath: fake) }

        setenv("OPENAI_API_KEY", "", 1)
        setenv("JOINTCHIEFS_KEYGETTER_PATH", fake, 1)
        defer {
            unsetenv("OPENAI_API_KEY")
            unsetenv("JOINTCHIEFS_KEYGETTER_PATH")
        }

        let key = try APIKeyResolver.resolve(.openAI)
        #expect(key == "from-keygetter")
    }

    // MARK: - Keygetter exit code handling

    @Test("Keygetter exit 3 (item not found) returns nil, not an error")
    func keygetterItemNotFound() throws {
        let fake = try makeFakeKeygetter(exitCode: 3, stderr: "item not found")
        defer { try? FileManager.default.removeItem(atPath: fake) }

        unsetenv("OPENAI_API_KEY")
        setenv("JOINTCHIEFS_KEYGETTER_PATH", fake, 1)
        defer { unsetenv("JOINTCHIEFS_KEYGETTER_PATH") }

        let key = try APIKeyResolver.resolve(.openAI)
        #expect(key == nil)
    }

    @Test("Keygetter exit 4 (headless interaction) throws interactionNotAllowed")
    func keygetterInteractionNotAllowed() throws {
        let fake = try makeFakeKeygetter(exitCode: 4, stderr: "prompt required")
        defer { try? FileManager.default.removeItem(atPath: fake) }

        unsetenv("OPENAI_API_KEY")
        setenv("JOINTCHIEFS_KEYGETTER_PATH", fake, 1)
        defer { unsetenv("JOINTCHIEFS_KEYGETTER_PATH") }

        #expect(throws: APIKeyResolverError.self) {
            _ = try APIKeyResolver.resolve(.openAI)
        }
    }

    @Test("Keygetter exit 5 surfaces a keygetterFailed error with stderr")
    func keygetterGenericFailure() throws {
        let fake = try makeFakeKeygetter(exitCode: 5, stderr: "unexpected status -42")
        defer { try? FileManager.default.removeItem(atPath: fake) }

        unsetenv("OPENAI_API_KEY")
        setenv("JOINTCHIEFS_KEYGETTER_PATH", fake, 1)
        defer { unsetenv("JOINTCHIEFS_KEYGETTER_PATH") }

        do {
            _ = try APIKeyResolver.resolve(.openAI)
            Issue.record("expected a keygetterFailed error")
        } catch APIKeyResolverError.keygetterFailed(let code, let stderr) {
            #expect(code == 5)
            #expect(stderr.contains("unexpected status"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    // MARK: - Location discovery

    @Test("locateKeygetter returns nil when nothing is on disk")
    func locateReturnsNilWhenMissing() {
        unsetenv("JOINTCHIEFS_KEYGETTER_PATH")
        let bogus = "/var/empty/definitely-not-a-keygetter-\(UUID().uuidString)"
        setenv("JOINTCHIEFS_KEYGETTER_PATH", bogus, 1)
        defer { unsetenv("JOINTCHIEFS_KEYGETTER_PATH") }

        // Sibling-of-tests lookup also won't find a keygetter binary named
        // "jointchiefs-keygetter" next to xctest — it's named differently.
        #expect(APIKeyResolver.locateKeygetter() == nil)
    }

    @Test("locateKeygetter honors the env override when the path is executable")
    func locateHonorsEnvOverride() throws {
        let fake = try makeFakeKeygetter(outputKey: "unused")
        defer { try? FileManager.default.removeItem(atPath: fake) }

        setenv("JOINTCHIEFS_KEYGETTER_PATH", fake, 1)
        defer { unsetenv("JOINTCHIEFS_KEYGETTER_PATH") }

        #expect(APIKeyResolver.locateKeygetter() == fake)
    }

    // MARK: - Helpers

    /// Creates an executable shell script in a unique temp directory that mimics
    /// the keygetter contract: prints `outputKey` to stdout (no trailing newline),
    /// exits with the given code, optionally prints `stderr` to stderr.
    private func makeFakeKeygetter(
        outputKey: String = "",
        exitCode: Int32 = 0,
        stderr: String = ""
    ) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jc-resolver-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let path = dir.appendingPathComponent("fake-keygetter").path
        let script = """
            #!/bin/bash
            printf '%s' '\(outputKey)'
            if [ -n '\(stderr)' ]; then
                printf '%s\\n' '\(stderr)' 1>&2
            fi
            exit \(exitCode)
            """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }
}
