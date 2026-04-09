import Foundation

public enum KeychainError: Error, Sendable, LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            "No API key found in the keychain for this account."
        case .duplicateItem:
            "A keychain entry already exists for this account."
        case .unexpectedStatus(let status):
            "Keychain operation failed with status \(status)."
        case .encodingFailed:
            "Failed to encode or decode the keychain data."
        }
    }
}
