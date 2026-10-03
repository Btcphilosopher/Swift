```swift
//
//  SecurePasswordEngine.swift
//
//  Secure credential-management foundation for Apple platforms.
//
//  Features:
//  - Keychain-backed credential storage
//  - Service / website / username association
//  - Password generation
//  - Credential retrieval
//  - Credential deletion
//  - Login-session management
//  - Password-strength analysis
//  - Auto-fill-ready architecture
//  - Optional biometric unlock through LocalAuthentication
//
//  Security model:
//
//      User
//        │
//        ▼
//   Face ID / Touch ID
//        │
//        ▼
//   LocalAuthentication
//        │
//        ▼
//   Secure Credential Engine
//        │
//        ▼
//      Keychain
//        │
//        ▼
//   Encrypted credential
//
//  IMPORTANT:
//  Actual system-wide password autofill requires an Apple
//  Credential Provider Extension / AutoFill Credential Provider.
//  A normal application cannot arbitrarily inject credentials
//  into every other application.
//
//  The Keychain is used instead of storing passwords in:
//  - UserDefaults
//  - JSON
//  - SQLite
//  - plaintext files
//  - ordinary app databases
//

import Foundation
import Security
import LocalAuthentication


// ================================================================
// MARK: - Credential
// ================================================================

public struct StoredCredential: Codable, Identifiable {

    public let id: UUID

    public var serviceIdentifier: String

    public var username: String

    public var password: String

    public var displayName: String?

    public var notes: String?

    public var createdAt: Date

    public var modifiedAt: Date

    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        serviceIdentifier: String,
        username: String,
        password: String,
        displayName: String? = nil,
        notes: String? = nil
    ) {

        self.id = id
        self.serviceIdentifier = serviceIdentifier
        self.username = username
        self.password = password
        self.displayName = displayName
        self.notes = notes
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.lastUsedAt = nil
    }
}


// ================================================================
// MARK: - Credential Metadata
// ================================================================
//
// Metadata can be displayed without retrieving the password.
//

public struct CredentialMetadata: Identifiable {

    public let id: UUID

    public let serviceIdentifier: String

    public let username: String

    public let displayName: String?

    public let createdAt: Date

    public let modifiedAt: Date

    public let lastUsedAt: Date?
}


// ================================================================
// MARK: - Password Strength
// ================================================================

public enum PasswordStrength: String {

    case veryWeak
    case weak
    case moderate
    case strong
    case veryStrong
}


// ================================================================
// MARK: - Vault Error
// ================================================================

public enum PasswordEngineError: Error {

    case invalidCredential
    case encodingFailed
    case decodingFailed

    case keychainSaveFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    case credentialNotFound

    case authenticationFailed
    case authenticationCancelled

    case vaultLocked
}


// ================================================================
// MARK: - Password Generator
// ================================================================

public struct PasswordGenerator {

    public struct Configuration {

        public var length: Int

        public var uppercase: Bool
        public var lowercase: Bool
        public var numbers: Bool
        public var symbols: Bool

        public init(
            length: Int = 24,
            uppercase: Bool = true,
            lowercase: Bool = true,
            numbers: Bool = true,
            symbols: Bool = true
        ) {

            self.length = length
            self.uppercase = uppercase
            self.lowercase = lowercase
            self.numbers = numbers
            self.symbols = symbols
        }
    }


    public static func generate(
        configuration:
            Configuration = Configuration()
    ) -> String {

        var characters =
            Array("abcdefghijklmnopqrstuvwxyz")

        if configuration.uppercase {

            characters +=
                Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        }

        if configuration.numbers {

            characters +=
                Array("0123456789")
        }

        if configuration.symbols {

            characters +=
                Array("!@#$%^&*()-_=+[]{};:,.?")
        }


        guard !characters.isEmpty else {
            return ""
        }


        var result = ""

        result.reserveCapacity(
            configuration.length
        )


        for _ in 0..<configuration.length {

            let index =
                Int.random(
                    in: 0..<characters.count
                )

            result.append(
                characters[index]
            )
        }

        return result
    }
}


// ================================================================
// MARK: - Password Analyzer
// ================================================================

public struct PasswordAnalyzer {

    public static func strength(
        _ password: String
    ) -> PasswordStrength {

        let length =
            password.count

        var score = 0


        if length >= 8 {
            score += 1
        }

        if length >= 12 {
            score += 1
        }

        if length >= 20 {
            score += 1
        }


        if password.range(
            of: "[A-Z]",
            options: .regularExpression
        ) != nil {

            score += 1
        }


        if password.range(
            of: "[a-z]",
            options: .regularExpression
        ) != nil {

            score += 1
        }


        if password.range(
            of: "[0-9]",
            options: .regularExpression
        ) != nil {

            score += 1
        }


        if password.range(
            of: "[^A-Za-z0-9]",
            options: .regularExpression
        ) != nil {

            score += 1
        }


        switch score {

        case 0...1:
            return .veryWeak

        case 2...3:
            return .weak

        case 4...5:
            return .moderate

        case 6:
            return .strong

        default:
            return .veryStrong
        }
    }
}


// ================================================================
// MARK: - Keychain Vault
// ================================================================

public final class CredentialKeychain {

    private let accessGroup: String?

    public init(
        accessGroup: String? = nil
    ) {

        self.accessGroup =
            accessGroup
    }


    // ============================================================
    // MARK: - Save
    // ============================================================

    public func save(
        _ credential: StoredCredential
    ) throws {

        let encoder =
            JSONEncoder()

        let data =
            try encoder.encode(
                credential
            )


        var query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrAccount as String:
                    credential.id.uuidString,

                kSecAttrService as String:
                    credential.serviceIdentifier,

                kSecValueData as String:
                    data,

                kSecAttrAccessible as String:
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]


        if let accessGroup {

            query[
                kSecAttrAccessGroup as String
            ] = accessGroup
        }


        let status =
            SecItemAdd(
                query as CFDictionary,
                nil
            )


        if status == errSecDuplicateItem {

            try update(
                credential
            )

            return
        }


        guard status == errSecSuccess else {

            throw PasswordEngineError
                .keychainSaveFailed(status)
        }
    }


    // ============================================================
    // MARK: - Update
    // ============================================================

    public func update(
        _ credential: StoredCredential
    ) throws {

        var query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrAccount as String:
                    credential.id.uuidString
            ]


        if let accessGroup {

            query[
                kSecAttrAccessGroup as String
            ] = accessGroup
        }


        let encoder =
            JSONEncoder()

        let data =
            try encoder.encode(
                credential
            )


        let attributes:
            [String: Any] = [

                kSecValueData as String:
                    data,

                kSecAttrService as String:
                    credential.serviceIdentifier
            ]


        let status =
            SecItemUpdate(
                query as CFDictionary,
                attributes as CFDictionary
            )


        guard status == errSecSuccess else {

            throw PasswordEngineError
                .keychainSaveFailed(status)
        }
    }


    // ============================================================
    // MARK: - Read
    // ============================================================

    public func read(
        id: UUID
    ) throws -> StoredCredential {

        var query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrAccount as String:
                    id.uuidString,

                kSecReturnData as String:
                    true,

                kSecMatchLimit as String:
                    kSecMatchLimitOne
            ]


        if let accessGroup {

            query[
                kSecAttrAccessGroup as String
            ] = accessGroup
        }


        var result:
            CFTypeRef?


        let status =
            SecItemCopyMatching(
                query as CFDictionary,
                &result
            )


        guard status == errSecSuccess else {

            if status == errSecItemNotFound {

                throw PasswordEngineError
                    .credentialNotFound
            }

            throw PasswordEngineError
                .keychainReadFailed(status)
        }


        guard
            let data =
                result as? Data
        else {

            throw PasswordEngineError
                .decodingFailed
        }


        do {

            return try JSONDecoder()
                .decode(
                    StoredCredential.self,
                    from: data
                )

        } catch {

            throw PasswordEngineError
                .decodingFailed
        }
    }


    // ============================================================
    // MARK: - Delete
    // ============================================================

    public func delete(
        id: UUID
    ) throws {

        var query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrAccount as String:
                    id.uuidString
            ]


        if let accessGroup {

            query[
                kSecAttrAccessGroup as String
            ] = accessGroup
        }


        let status =
            SecItemDelete(
                query as CFDictionary
            )


        guard
            status == errSecSuccess ||
            status == errSecItemNotFound
        else {

            throw PasswordEngineError
                .keychainDeleteFailed(status)
        }
    }
}


// ================================================================
// MARK: - Secure Password Engine
// ================================================================

@MainActor
public final class SecurePasswordEngine {

    private let keychain:
        CredentialKeychain

    private(set) var unlocked =
        false

    public init(
        accessGroup: String? = nil
    ) {

        self.keychain =
            CredentialKeychain(
                accessGroup:
                    accessGroup
            )
    }


    // ============================================================
    // MARK: - Authentication
    // ============================================================

    public func authenticate(
        reason: String =
            "Unlock your saved passwords."
    ) async throws {

        let context =
            LAContext()

        context.localizedCancelTitle =
            "Cancel"


        var error: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        ) else {

            throw PasswordEngineError
                .authenticationFailed
        }


        do {

            let success =
                try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )


            guard success else {

                throw PasswordEngineError
                    .authenticationFailed
            }


            unlocked = true

        } catch {

            throw PasswordEngineError
                .authenticationFailed
        }
    }


    // ============================================================
    // MARK: - Lock
    // ============================================================

    public func lock() {

        unlocked = false
    }


    // ============================================================
    // MARK: - Save Credential
    // ============================================================

    public func save(
        service: String,
        username: String,
        password: String,
        displayName: String? = nil
    ) throws -> UUID {

        guard unlocked else {

            throw PasswordEngineError
                .vaultLocked
        }


        guard
            !service.isEmpty,
            !username.isEmpty,
            !password.isEmpty
        else {

            throw PasswordEngineError
                .invalidCredential
        }


        let credential =
            StoredCredential(
                serviceIdentifier:
                    service,
                username:
                    username,
                password:
                    password,
                displayName:
                    displayName
            )


        try keychain.save(
            credential
        )


        return credential.id
    }


    // ============================================================
    // MARK: - Retrieve
    // ============================================================

    public func credential(
        id: UUID
    ) throws -> StoredCredential {

        guard unlocked else {

            throw PasswordEngineError
                .vaultLocked
        }


        return try keychain.read(
            id: id
        )
    }


    // ============================================================
    // MARK: - Delete
    // ============================================================

    public func delete(
        id: UUID
    ) throws {

        guard unlocked else {

            throw PasswordEngineError
                .vaultLocked
        }


        try keychain.delete(
            id: id
        )
    }


    // ============================================================
    // MARK: - Generate
    // ============================================================

    public func generatePassword(
        length: Int = 24
    ) -> String {

        PasswordGenerator.generate(
            configuration:
                .init(
                    length: length
                )
        )
    }


    // ============================================================
    // MARK: - Strength
    // ============================================================

    public func passwordStrength(
        _ password: String
    ) -> PasswordStrength {

        PasswordAnalyzer.strength(
            password
        )
    }
}


// ================================================================
// MARK: - Login Session
// ================================================================

public struct LoginSession {

    public let credentialID: UUID

    public let serviceIdentifier: String

    public let username: String

    public let password: String

    public let createdAt: Date

    public init(
        credential:
            StoredCredential
    ) {

        self.credentialID =
            credential.id

        self.serviceIdentifier =
            credential.serviceIdentifier

        self.username =
            credential.username

        self.password =
            credential.password

        self.createdAt =
            Date()
    }
}


// ================================================================
// MARK: - AutoFill Representation
// ================================================================
//
// This is the data layer an actual Credential Provider Extension
// can use when constructing AutoFill results.
//

public struct AutoFillCredential {

    public let serviceIdentifier: String

    public let username: String

    public let password: String

    public let displayName: String?


    public init(
        credential:
            StoredCredential
    ) {

        self.serviceIdentifier =
            credential.serviceIdentifier

        self.username =
            credential.username

        self.password =
            credential.password

        self.displayName =
            credential.displayName
    }
}


// ================================================================
// MARK: - Credential Matching
// ================================================================

public struct CredentialMatcher {

    public static func normalize(
        _ identifier: String
    ) -> String {

        var value =
            identifier
                .lowercased()
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        if value.hasPrefix("https://") {

            value =
                String(
                    value.dropFirst(8)
                )
        }

        if value.hasPrefix("http://") {

            value =
                String(
                    value.dropFirst(7)
                )
        }

        if let slash =
            value.firstIndex(
                of: "/"
            ) {

            value =
                String(
                    value[..<slash]
                )
        }

        if value.hasPrefix("www.") {

            value =
                String(
                    value.dropFirst(4)
                )
        }

        return value
    }


    public static func matches(
        storedService: String,
        requestedService: String
    ) -> Bool {

        normalize(
            storedService
        ) ==
        normalize(
            requestedService
        )
    }
}


// ================================================================
// MARK: - Example
// ================================================================

@MainActor
public func passwordEngineExample()
    async {

    let engine =
        SecurePasswordEngine()


    do {

        // User authenticates with the device's
        // supported authentication mechanism.

        try await engine.authenticate(
            reason:
                "Unlock your secure password vault."
        )


        // Generate a strong password.

        let password =
            engine.generatePassword(
                length: 32
            )


        print(
            "Generated password:",
            password
        )


        print(
            "Strength:",
            engine.passwordStrength(
                password
            )
        )


        // Store securely in the Keychain.

        let id =
            try engine.save(
                service:
                    "example.com",
                username:
                    "user@example.com",
                password:
                    password,
                displayName:
                    "Example Account"
            )


        // Retrieve only when needed.

        let credential =
            try engine.credential(
                id: id
            )


        print(
            "Stored username:",
            credential.username
        )


        // The password should NOT normally be
        // printed or logged.

        print(
            "Credential retrieved securely."
        )


        // Lock when finished.

        engine.lock()

    } catch {

        print(
            "Password engine error:",
            error
        )
    }
}
```


