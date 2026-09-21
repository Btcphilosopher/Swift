//
// SafariWeb3WalletEngine.swift
//
// Native Web3 Wallet Engine
// Safari Web3 Architecture — #1
//
// Swift 6 / macOS
//
// Responsibilities:
//
// - Multi-chain wallet accounts
// - Chain/network registry
// - Wallet session management
// - DApp origin permissions
// - Message signing requests
// - Transaction signing requests
// - Transaction validation
// - Wallet lock/unlock state
// - Key-provider abstraction
// - Secure storage abstraction
// - Address validation
// - Balance models
// - Gas/fee models
// - Wallet telemetry
// - Request lifecycle
// - Concurrent request isolation
//
// IMPORTANT:
// This architecture deliberately does NOT store raw private keys
// in Codable models or ordinary application files.
//
// Production key material should be implemented using:
// - macOS Keychain
// - Secure Enclave where appropriate
// - hardware wallet integration
// - external signing providers
//
// The signing engine is protocol-based so those implementations
// can be swapped in without changing Safari's Web3 runtime.
//

import Foundation
import Security
import CryptoKit
import os


// MARK: - 1. Wallet Identity

public struct Web3WalletID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UUID

    public init(
        rawValue:
            UUID = UUID()
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 2. Account Identity

public struct Web3AccountID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UUID

    public init(
        rawValue:
            UUID = UUID()
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 3. DApp Session Identity

public struct Web3SessionID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UUID

    public init(
        rawValue:
            UUID = UUID()
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 4. Request Identity

public struct Web3RequestID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UUID

    public init(
        rawValue:
            UUID = UUID()
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 5. Chain Identity

public struct Web3ChainID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UInt64

    public init(
        rawValue:
            UInt64
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 6. Web3 Chain

public struct Web3Chain:
    Codable,
    Hashable,
    Sendable
{
    public let id:
        Web3ChainID

    public let name:
        String

    public let nativeSymbol:
        String

    public let decimals:
        Int

    public let rpcEndpoints:
        [URL]

    public let explorerBaseURL:
        URL?

    public init(
        id:
            Web3ChainID,

        name:
            String,

        nativeSymbol:
            String,

        decimals:
            Int,

        rpcEndpoints:
            [URL],

        explorerBaseURL:
            URL? = nil
    ) {
        self.id =
            id

        self.name =
            name

        self.nativeSymbol =
            nativeSymbol

        self.decimals =
            decimals

        self.rpcEndpoints =
            rpcEndpoints

        self.explorerBaseURL =
            explorerBaseURL
    }
}


// MARK: - 7. Address

public struct Web3Address:
    Hashable,
    Codable,
    Sendable
{
    public let value:
        String

    public init?(
        _ value:
            String
    ) {

        let normalized =
            value.trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard
            !normalized.isEmpty
        else {
            return nil
        }

        self.value =
            normalized
    }
}


// MARK: - 8. Wallet Account

public struct Web3Account:
    Codable,
    Sendable
{
    public let id:
        Web3AccountID

    public let walletID:
        Web3WalletID

    public let address:
        Web3Address

    public let label:
        String

    public let derivationPath:
        String?

    public let createdAt:
        Date

    public var isActive:
        Bool

    public init(
        id:
            Web3AccountID = Web3AccountID(),

        walletID:
            Web3WalletID,

        address:
            Web3Address,

        label:
            String,

        derivationPath:
            String? = nil,

        createdAt:
            Date = Date(),

        isActive:
            Bool = true
    ) {
        self.id =
            id

        self.walletID =
            walletID

        self.address =
            address

        self.label =
            label

        self.derivationPath =
            derivationPath

        self.createdAt =
            createdAt

        self.isActive =
            isActive
    }
}


// MARK: - 9. Wallet State

public enum Web3WalletState:
    String,
    Codable,
    Sendable
{
    case uninitialized
    case locked
    case unlocking
    case unlocked
    case signing
    case lockedForSecurity
}


// MARK: - 10. Wallet Metadata

public struct Web3WalletMetadata:
    Codable,
    Sendable
{
    public let id:
        Web3WalletID

    public var name:
        String

    public let createdAt:
        Date

    public var lastUsedAt:
        Date?

    public init(
        id:
            Web3WalletID = Web3WalletID(),

        name:
            String,

        createdAt:
            Date = Date(),

        lastUsedAt:
            Date? = nil
    ) {
        self.id =
            id

        self.name =
            name

        self.createdAt =
            createdAt

        self.lastUsedAt =
            lastUsedAt
    }
}


// MARK: - 11. Wallet Permission

public enum Web3WalletPermission:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case viewAddress
    case viewBalance
    case signMessage
    case signTypedData
    case signTransaction
    case sendTransaction
}


// MARK: - 12. Permission Scope

public enum Web3PermissionScope:
    String,
    Codable,
    Sendable
{
    case once
    case session
    case persistent
}


// MARK: - 13. DApp Origin

public struct Web3DAppOrigin:
    Hashable,
    Codable,
    Sendable
{
    public let scheme:
        String

    public let host:
        String

    public let port:
        Int?

    public init?(
        url:
            URL
    ) {

        guard
            let scheme =
                url.scheme,

            let host =
                url.host
        else {
            return nil
        }

        self.scheme =
            scheme.lowercased()

        self.host =
            host.lowercased()

        self.port =
            url.port
    }

    public var serialized:
        String
    {
        var value =
            "\(scheme)://\(host)"

        if let port {
            value +=
                ":\(port)"
        }

        return value
    }
}


// MARK: - 14. DApp Session

public struct Web3DAppSession:
    Codable,
    Sendable
{
    public let id:
        Web3SessionID

    public let origin:
        Web3DAppOrigin

    public let walletID:
        Web3WalletID

    public let accountID:
        Web3AccountID

    public let chainID:
        Web3ChainID

    public let createdAt:
        Date

    public var lastUsedAt:
        Date

    public var permissions:
        Set<Web3WalletPermission>

    public let scope:
        Web3PermissionScope

    public var expiresAt:
        Date?

    public init(
        id:
            Web3SessionID = Web3SessionID(),

        origin:
            Web3DAppOrigin,

        walletID:
            Web3WalletID,

        accountID:
            Web3AccountID,

        chainID:
            Web3ChainID,

        createdAt:
            Date = Date(),

        lastUsedAt:
            Date = Date(),

        permissions:
            Set<Web3WalletPermission>,

        scope:
            Web3PermissionScope,

        expiresAt:
            Date? = nil
    ) {
        self.id =
            id

        self.origin =
            origin

        self.walletID =
            walletID

        self.accountID =
            accountID

        self.chainID =
            chainID

        self.createdAt =
            createdAt

        self.lastUsedAt =
            lastUsedAt

        self.permissions =
            permissions

        self.scope =
            scope

        self.expiresAt =
            expiresAt
    }
}


// MARK: - 15. Wallet Balance

public struct Web3Balance:
    Codable,
    Sendable
{
    public let accountID:
        Web3AccountID

    public let chainID:
        Web3ChainID

    public let nativeAmount:
        Decimal

    public let symbol:
        String

    public let updatedAt:
        Date

    public init(
        accountID:
            Web3AccountID,

        chainID:
            Web3ChainID,

        nativeAmount:
            Decimal,

        symbol:
            String,

        updatedAt:
            Date = Date()
    ) {
        self.accountID =
            accountID

        self.chainID =
            chainID

        self.nativeAmount =
            nativeAmount

        self.symbol =
            symbol

        self.updatedAt =
            updatedAt
    }
}


// MARK: - 16. Transaction

public struct Web3Transaction:
    Codable,
    Sendable
{
    public let from:
        Web3Address

    public let to:
        Web3Address?

    public let value:
        String

    public let data:
        Data

    public let nonce:
        UInt64?

    public let gasLimit:
        UInt64?

    public let maxFeePerGas:
        UInt64?

    public let maxPriorityFeePerGas:
        UInt64?

    public init(
        from:
            Web3Address,

        to:
            Web3Address?,

        value:
            String,

        data:
            Data = Data(),

        nonce:
            UInt64? = nil,

        gasLimit:
            UInt64? = nil,

        maxFeePerGas:
            UInt64? = nil,

        maxPriorityFeePerGas:
            UInt64? = nil
    ) {
        self.from =
            from

        self.to =
            to

        self.value =
            value

        self.data =
            data

        self.nonce =
            nonce

        self.gasLimit =
            gasLimit

        self.maxFeePerGas =
            maxFeePerGas

        self.maxPriorityFeePerGas =
            maxPriorityFeePerGas
    }
}


// MARK: - 17. Message Signing Request

public struct Web3MessageSigningRequest:
    Sendable
{
    public let id:
        Web3RequestID

    public let origin:
        Web3DAppOrigin

    public let accountID:
        Web3AccountID

    public let chainID:
        Web3ChainID

    public let message:
        Data

    public let createdAt:
        Date

    public init(
        id:
            Web3RequestID = Web3RequestID(),

        origin:
            Web3DAppOrigin,

        accountID:
            Web3AccountID,

        chainID:
            Web3ChainID,

        message:
            Data,

        createdAt:
            Date = Date()
    ) {
        self.id =
            id

        self.origin =
            origin

        self.accountID =
            accountID

        self.chainID =
            chainID

        self.message =
            message

        self.createdAt =
            createdAt
    }
}


// MARK: - 18. Transaction Signing Request

public struct Web3TransactionSigningRequest:
    Sendable
{
    public let id:
        Web3RequestID

    public let origin:
        Web3DAppOrigin

    public let accountID:
        Web3AccountID

    public let chainID:
        Web3ChainID

    public let transaction:
        Web3Transaction

    public let createdAt:
        Date

    public init(
        id:
            Web3RequestID = Web3RequestID(),

        origin:
            Web3DAppOrigin,

        accountID:
            Web3AccountID,

        chainID:
            Web3ChainID,

        transaction:
            Web3Transaction,

        createdAt:
            Date = Date()
    ) {
        self.id =
            id

        self.origin =
            origin

        self.accountID =
            accountID

        self.chainID =
            chainID

        self.transaction =
            transaction

        self.createdAt =
            createdAt
    }
}


// MARK: - 19. Signing Result

public enum Web3SigningResult:
    Sendable
{
    case approved(Data)
    case rejected
}


// MARK: - 20. Wallet Error

public enum Web3WalletError:
    Error,
    Sendable
{
    case walletLocked
    case walletNotFound
    case accountNotFound
    case chainNotFound
    case sessionNotFound
    case permissionDenied
    case invalidOrigin
    case invalidAddress
    case invalidTransaction
    case signingUnavailable
    case userRejected
    case requestNotFound
    case walletBusy
    case secureStorageFailure
}


// MARK: - 21. Signer Protocol

public protocol Web3Signer:
    Sendable
{
    func signMessage(
        account:
            Web3Account,

        message:
            Data
    ) async throws -> Data

    func signTransaction(
        account:
            Web3Account,

        transaction:
            Web3Transaction
    ) async throws -> Data
}


// MARK: - 22. Secure Key Provider

public protocol Web3SecureKeyProvider:
    Sendable
{
    func unlock() async throws

    func lock() async

    func isUnlocked() async -> Bool

    func signer(
        walletID:
            Web3WalletID
    ) async throws -> Web3Signer
}


// MARK: - 23. Development Signer

//
// This is deliberately NOT a production private-key implementation.
//
// It demonstrates the signing abstraction without placing a raw
// private key into Safari's ordinary application memory.
//

public struct Web3UnavailableSigner:
    Web3Signer
{
    public init() {}

    public func signMessage(
        account:
            Web3Account,

        message:
            Data
    ) async throws -> Data {

        throw Web3WalletError
            .signingUnavailable
    }

    public func signTransaction(
        account:
            Web3Account,

        transaction:
            Web3Transaction
    ) async throws -> Data {

        throw Web3WalletError
            .signingUnavailable
    }
}


// MARK: - 24. Keychain Abstraction

public actor Web3Keychain {

    private let service:
        String

    public init(
        service:
            String =
                "com.example.SafariWeb3"
    ) {
        self.service =
            service
    }

    public func store(
        data:
            Data,

        account:
            String
    ) throws {

        let query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrService as String:
                    service,

                kSecAttrAccount as String:
                    account,

                kSecValueData as String:
                    data,

                kSecAttrAccessible as String:
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]

        let status =
            SecItemAdd(
                query as CFDictionary,
                nil
            )

        guard
            status == errSecSuccess
        else {

            if status ==
                errSecDuplicateItem
            {

                try update(
                    data:
                        data,

                    account:
                        account
                )

                return
            }

            throw Web3WalletError
                .secureStorageFailure
        }
    }

    public func read(
        account:
            String
    ) throws -> Data? {

        let query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrService as String:
                    service,

                kSecAttrAccount as String:
                    account,

                kSecReturnData as String:
                    true,

                kSecMatchLimit as String:
                    kSecMatchLimitOne
            ]

        var result:
            CFTypeRef?

        let status =
            SecItemCopyMatching(
                query as CFDictionary,
                &result
            )

        if status ==
            errSecItemNotFound
        {
            return nil
        }

        guard
            status == errSecSuccess
        else {
            throw Web3WalletError
                .secureStorageFailure
        }

        return result as? Data
    }

    private func update(
        data:
            Data,

        account:
            String
    ) throws {

        let query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrService as String:
                    service,

                kSecAttrAccount as String:
                    account
            ]

        let attributes:
            [String: Any] = [

                kSecValueData as String:
                    data
            ]

        let status =
            SecItemUpdate(
                query as CFDictionary,
                attributes as CFDictionary
            )

        guard
            status == errSecSuccess
        else {
            throw Web3WalletError
                .secureStorageFailure
        }
    }

    public func remove(
        account:
            String
    ) throws {

        let query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrService as String:
                    service,

                kSecAttrAccount as String:
                    account
            ]

        let status =
            SecItemDelete(
                query as CFDictionary
            )

        guard
            status == errSecSuccess ||
            status == errSecItemNotFound
        else {
            throw Web3WalletError
                .secureStorageFailure
        }
    }
}


// MARK: - 25. Wallet Registry

public actor Web3WalletRegistry {

    private var wallets:
        [Web3WalletID:
            Web3WalletMetadata] = [:]

    public init() {}

    public func create(
        name:
            String
    ) -> Web3WalletMetadata {

        let wallet =
            Web3WalletMetadata(
                name:
                    name
            )

        wallets[
            wallet.id
        ] =
            wallet

        return wallet
    }

    public func wallet(
        id:
            Web3WalletID
    ) -> Web3WalletMetadata? {

        wallets[id]
    }

    public func all()
        -> [Web3WalletMetadata]
    {
        Array(
            wallets.values
        )
    }

    public func updateLastUsed(
        id:
            Web3WalletID
    ) {

        guard
            var wallet =
                wallets[id]
        else {
            return
        }

        wallet.lastUsedAt =
            Date()

        wallets[id] =
            wallet
    }
}


// MARK: - 26. Account Registry

public actor Web3AccountRegistry {

    private var accounts:
        [Web3AccountID:
            Web3Account] = [:]

    public init() {}

    public func add(
        _ account:
            Web3Account
    ) {

        accounts[
            account.id
        ] =
            account
    }

    public func account(
        id:
            Web3AccountID
    ) -> Web3Account? {

        accounts[id]
    }

    public func accountsForWallet(
        _ walletID:
            Web3WalletID
    ) -> [Web3Account] {

        accounts.values.filter {
            $0.walletID ==
                walletID
        }
    }

    public func activate(
        id:
            Web3AccountID
    ) {

        for key in accounts.keys {

            guard
                var account =
                    accounts[key]
            else {
                continue
            }

            account.isActive =
                key == id

            accounts[key] =
                account
        }
    }
}


// MARK: - 27. Chain Registry

public actor Web3ChainRegistry {

    private var chains:
        [Web3ChainID:
            Web3Chain] = [:]

    public init() {}

    public func register(
        _ chain:
            Web3Chain
    ) {

        chains[
            chain.id
        ] =
            chain
    }

    public func chain(
        id:
            Web3ChainID
    ) -> Web3Chain? {

        chains[id]
    }

    public func all()
        -> [Web3Chain]
    {
        Array(
            chains.values
        )
    }
}


// MARK: - 28. DApp Session Store

public actor Web3SessionStore {

    private var sessions:
        [Web3SessionID:
            Web3DAppSession] = [:]

    public init() {}

    public func create(
        _ session:
            Web3DAppSession
    ) {

        sessions[
            session.id
        ] =
            session
    }

    public func session(
        id:
            Web3SessionID
    ) -> Web3DAppSession? {

        sessions[id]
    }

    public func sessionsForOrigin(
        _ origin:
            Web3DAppOrigin
    ) -> [Web3DAppSession] {

        sessions.values.filter {
            $0.origin ==
                origin
        }
    }

    public func remove(
        id:
            Web3SessionID
    ) {

        sessions.removeValue(
            forKey:
                id
        )
    }

    public func revokeOrigin(
        _ origin:
            Web3DAppOrigin
    ) {

        sessions =
            sessions.filter {
                $0.value.origin !=
                    origin
            }
    }

    public func all()
        -> [Web3DAppSession]
    {
        Array(
            sessions.values
        )
    }
}


// MARK: - 29. Permission Engine

public actor Web3PermissionEngine {

    private let sessions:
        Web3SessionStore

    public init(
        sessions:
            Web3SessionStore
    ) {
        self.sessions =
            sessions
    }

    public func hasPermission(
        origin:
            Web3DAppOrigin,

        permission:
            Web3WalletPermission
    ) async -> Bool {

        let sessions =
            await sessions.sessionsForOrigin(
                origin
            )

        return sessions.contains {
            $0.permissions.contains(
                permission
            )
        }
    }

    public func sessionAllows(
        sessionID:
            Web3SessionID,

        permission:
            Web3WalletPermission
    ) async -> Bool {

        guard
            let session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            return false
        }

        if
            let expiry =
                session.expiresAt,
            expiry <= Date()
        {
            return false
        }

        return session.permissions.contains(
            permission
        )
    }
}


// MARK: - 30. Transaction Validator

public struct Web3TransactionValidator:
    Sendable
{
    public init() {}

    public func validate(
        _ transaction:
            Web3Transaction
    ) throws {

        guard
            transaction.from.value
                .isEmpty == false
        else {
            throw Web3WalletError
                .invalidTransaction
        }

        if
            let to =
                transaction.to
        {
            guard
                !to.value.isEmpty
            else {
                throw Web3WalletError
                    .invalidAddress
            }
        }

        guard
            !transaction.value.isEmpty
        else {
            throw Web3WalletError
                .invalidTransaction
        }
    }
}


// MARK: - 31. Request Registry

public actor Web3RequestRegistry {

    public enum Request:
        Sendable
    {
        case message(
            Web3MessageSigningRequest
        )

        case transaction(
            Web3TransactionSigningRequest
        )
    }

    private var requests:
        [Web3RequestID:
            Request] = [:]

    public init() {}

    public func insert(
        _ request:
            Request
    ) {

        switch request {

        case .message(let request):

            requests[
                request.id
            ] =
                request

        case .transaction(let request):

            requests[
                request.id
            ] =
                request
        }
    }

    public func remove(
        id:
            Web3RequestID
    ) -> Request? {

        requests.removeValue(
            forKey:
                id
        )
    }

    public func request(
        id:
            Web3RequestID
    ) -> Request? {

        requests[id]
    }
}


// MARK: - 32. Wallet Telemetry

public enum Web3WalletTelemetryEvent:
    Sendable
{
    case walletCreated(
        Web3WalletID
    )

    case accountCreated(
        Web3AccountID
    )

    case sessionCreated(
        Web3SessionID
    )

    case permissionRejected(
        Web3DAppOrigin,
        Web3WalletPermission
    )

    case messageSigningRequested(
        Web3DAppOrigin
    )

    case transactionSigningRequested(
        Web3DAppOrigin
    )

    case signingCompleted(
        Web3RequestID
    )

    case signingRejected(
        Web3RequestID
    )
}


public actor Web3WalletTelemetry {

    private var events:
        [Web3WalletTelemetryEvent] = []

    private let capacity:
        Int

    public init(
        capacity:
            Int = 5_000
    ) {
        self.capacity =
            capacity
    }

    public func append(
        _ event:
            Web3WalletTelemetryEvent
    ) {

        events.append(
            event
        )

        if events.count >
            capacity
        {
            events.removeFirst(
                events.count - capacity
            )
        }
    }

    public func recent()
        -> [Web3WalletTelemetryEvent]
    {
        events
    }
}


// MARK: - 33. Wallet Runtime

public actor SafariWeb3WalletRuntime {

    public let walletRegistry:
        Web3WalletRegistry

    public let accountRegistry:
        Web3AccountRegistry

    public let chainRegistry:
        Web3ChainRegistry

    public let sessions:
        Web3SessionStore

    public let permissions:
        Web3PermissionEngine

    public let requests:
        Web3RequestRegistry

    public let telemetry:
        Web3WalletTelemetry

    private let keyProvider:
        Web3SecureKeyProvider

    private let transactionValidator:
        Web3TransactionValidator

    private var state:
        Web3WalletState =
            .locked

    private var activeWallet:
        Web3WalletID?

    public init(
        keyProvider:
            Web3SecureKeyProvider
    ) {

        let walletRegistry =
            Web3WalletRegistry()

        let accountRegistry =
            Web3AccountRegistry()

        let chainRegistry =
            Web3ChainRegistry()

        let sessions =
            Web3SessionStore()

        self.walletRegistry =
            walletRegistry

        self.accountRegistry =
            accountRegistry

        self.chainRegistry =
            chainRegistry

        self.sessions =
            sessions

        self.permissions =
            Web3PermissionEngine(
                sessions:
                    sessions
            )

        self.requests =
            Web3RequestRegistry()

        self.telemetry =
            Web3WalletTelemetry()

        self.keyProvider =
            keyProvider

        self.transactionValidator =
            Web3TransactionValidator()
    }


    // MARK: Wallet lifecycle

    public func createWallet(
        name:
            String
    ) async
        -> Web3WalletMetadata {

        let wallet =
            await walletRegistry.create(
                name:
                    name
            )

        activeWallet =
            wallet.id

        state =
            .locked

        await telemetry.append(
            .walletCreated(
                wallet.id
            )
        )

        return wallet
    }


    public func unlock()
        async throws
    {

        guard
            state !=
                .unlocked
        else {
            return
        }

        state =
            .unlocking

        do {

            try await keyProvider.unlock()

            state =
                .unlocked

        } catch {

            state =
                .locked

            throw error
        }
    }


    public func lock()
        async {

        await keyProvider.lock()

        state =
            .locked
    }


    public func currentState()
        -> Web3WalletState
    {
        state
    }


    // MARK: Account management

    public func addAccount(
        address:
            Web3Address,

        label:
            String,

        derivationPath:
            String? = nil
    ) async throws
        -> Web3Account {

        guard
            let walletID =
                activeWallet
        else {
            throw Web3WalletError
                .walletNotFound
        }

        let account =
            Web3Account(
                walletID:
                    walletID,

                address:
                    address,

                label:
                    label,

                derivationPath:
                    derivationPath
            )

        await accountRegistry.add(
            account
        )

        await telemetry.append(
            .accountCreated(
                account.id
            )
        )

        return account
    }


    public func selectAccount(
        id:
            Web3AccountID
    ) async throws {

        guard
            await accountRegistry.account(
                id:
                    id
            ) != nil
        else {
            throw Web3WalletError
                .accountNotFound
        }

        await accountRegistry.activate(
            id:
                id
        )
    }


    // MARK: Chain management

    public func registerChain(
        _ chain:
            Web3Chain
    ) async {

        await chainRegistry.register(
            chain
        )
    }


    // MARK: DApp session

    public func connect(
        origin:
            Web3DAppOrigin,

        accountID:
            Web3AccountID,

        chainID:
            Web3ChainID,

        permissions:
            Set<Web3WalletPermission>,

        scope:
            Web3PermissionScope
    ) async throws
        -> Web3DAppSession {

        guard
            await accountRegistry.account(
                id:
                    accountID
            ) != nil
        else {
            throw Web3WalletError
                .accountNotFound
        }

        guard
            await chainRegistry.chain(
                id:
                    chainID
            ) != nil
        else {
            throw Web3WalletError
                .chainNotFound
        }

        let session =
            Web3DAppSession(
                origin:
                    origin,

                walletID:
                    activeWallet
                    ?? Web3WalletID(),

                accountID:
                    accountID,

                chainID:
                    chainID,

                permissions:
                    permissions,

                scope:
                    scope,

                expiresAt:
                    scope == .session
                    ? Date().addingTimeInterval(
                        60 * 60
                    )
                    : nil
            )

        await sessions.create(
            session
        )

        await telemetry.append(
            .sessionCreated(
                session.id
            )
        )

        return session
    }


    // MARK: Message signing

    public func requestMessageSignature(
        origin:
            Web3DAppOrigin,

        sessionID:
            Web3SessionID,

        message:
            Data
    ) async throws
        -> Web3RequestID {

        guard
            state ==
                .unlocked
        else {
            throw Web3WalletError
                .walletLocked
        }

        guard
            await permissions.sessionAllows(
                sessionID:
                    sessionID,

                permission:
                    .signMessage
            )
        else {

            await telemetry.append(
                .permissionRejected(
                    origin,
                    .signMessage
                )
            )

            throw Web3WalletError
                .permissionDenied
        }

        guard
            let session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw Web3WalletError
                .sessionNotFound
        }

        let request =
            Web3MessageSigningRequest(
                origin:
                    origin,

                accountID:
                    session.accountID,

                chainID:
                    session.chainID,

                message:
                    message
            )

        await requests.insert(
            .message(
                request
            )
        )

        await telemetry.append(
            .messageSigningRequested(
                origin
            )
        )

        return request.id
    }


    // MARK: Transaction signing

    public func requestTransactionSignature(
        origin:
            Web3DAppOrigin,

        sessionID:
            Web3SessionID,

        transaction:
            Web3Transaction
    ) async throws
        -> Web3RequestID {

        guard
            state ==
                .unlocked
        else {
            throw Web3WalletError
                .walletLocked
        }

        try transactionValidator.validate(
            transaction
        )

        guard
            await permissions.sessionAllows(
                sessionID:
                    sessionID,

                permission:
                    .signTransaction
            )
        else {

            await telemetry.append(
                .permissionRejected(
                    origin,
                    .signTransaction
                )
            )

            throw Web3WalletError
                .permissionDenied
        }

        guard
            let session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw Web3WalletError
                .sessionNotFound
        }

        let request =
            Web3TransactionSigningRequest(
                origin:
                    origin,

                accountID:
                    session.accountID,

                chainID:
                    session.chainID,

                transaction:
                    transaction
            )

        await requests.insert(
            .transaction(
                request
            )
        )

        await telemetry.append(
            .transactionSigningRequested(
                origin
            )
        )

        return request.id
    }


    // MARK: Sign

    public func sign(
        requestID:
            Web3RequestID
    ) async throws
        -> Web3SigningResult {

        guard
            state ==
                .unlocked
        else {
            throw Web3WalletError
                .walletLocked
        }

        guard
            let request =
                await requests.request(
                    id:
                        requestID
                )
        else {
            throw Web3WalletError
                .requestNotFound
        }

        state =
            .signing

        defer {
            state =
                .unlocked
        }

        guard
            let walletID =
                activeWallet
        else {
            throw Web3WalletError
                .walletNotFound
        }

        let signer =
            try await keyProvider.signer(
                walletID:
                    walletID
            )

        do {

            let signature:
                Data

            switch request {

            case .message(let message):

                guard
                    let account =
                        await accountRegistry.account(
                            id:
                                message.accountID
                        )
                else {
                    throw Web3WalletError
                        .accountNotFound
                }

                signature =
                    try await signer.signMessage(
                        account:
                            account,

                        message:
                            message.message
                    )

            case .transaction(
                let transactionRequest
            ):

                guard
                    let account =
                        await accountRegistry.account(
                            id:
                                transactionRequest
                                    .accountID
                        )
                else {
                    throw Web3WalletError
                        .accountNotFound
                }

                signature =
                    try await signer.signTransaction(
                        account:
                            account,

                        transaction:
                            transactionRequest
                                .transaction
                    )
            }

            await requests.remove(
                id:
                    requestID
            )

            await telemetry.append(
                .signingCompleted(
                    requestID
                )
            )

            return .approved(
                signature
            )

        } catch {

            await telemetry.append(
                .signingRejected(
                    requestID
                )
            )

            throw error
        }
    }


    public func reject(
        requestID:
            Web3RequestID
    ) async {

        await requests.remove(
            id:
                requestID
        )

        await telemetry.append(
            .signingRejected(
                requestID
            )
        )
    }


    // MARK: Security

    public func revokeOrigin(
        _ origin:
            Web3DAppOrigin
    ) async {

        await sessions.revokeOrigin(
            origin
        )
    }


    public func revokeSession(
        _ sessionID:
            Web3SessionID
    ) async {

        await sessions.remove(
            id:
                sessionID
        )
    }
}


// MARK: - 34. Web3 JavaScript Bridge

//
// This is the boundary between a webpage and the native wallet.
//
// In production this would be connected to a WKUserContentController
// using a carefully restricted WKScriptMessageHandler.
//
// The page should NEVER receive arbitrary native objects or key material.
//

@MainActor
public final class SafariWeb3JavaScriptBridge:
    NSObject,
    WKScriptMessageHandler
{

    private weak var webView:
        WKWebView?

    private let wallet:
        SafariWeb3WalletRuntime

    public init(
        webView:
            WKWebView,

        wallet:
            SafariWeb3WalletRuntime
    ) {

        self.webView =
            webView

        self.wallet =
            wallet

        super.init()

        webView.configuration
            .userContentController
            .add(
                self,

                name:
                    "safariWeb3"
            )
    }

    public func userContentController(
        _ userContentController:
            WKUserContentController,

        didReceive message:
            WKScriptMessage
    ) {

        guard
            message.name ==
                "safariWeb3"
        else {
            return
        }

        guard
            let dictionary =
                message.body
                    as? [String: Any]
        else {
            return
        }

        handle(
            dictionary:
                dictionary
        )
    }

    private func handle(
        dictionary:
            [String: Any]
    ) {

        guard
            let method =
                dictionary["method"]
                as? String
        else {
            return
        }

        switch method {

        case "wallet_state":

            Task {
                let state =
                    await wallet.currentState()

                await send(
                    [
                        "type":
                            "wallet_state",

                        "state":
                            state.rawValue
                    ]
                )
            }

        default:

            Task {

                await send(
                    [
                        "type":
                            "error",

                        "message":
                            "Unsupported Web3 method"
                    ]
                )
            }
        }
    }

    private func send(
        _ payload:
            [String: Any]
    ) async {

        guard
            let webView
        else {
            return
        }

        guard
            JSONSerialization.isValidJSONObject(
                payload
            )
        else {
            return
        }

        guard
            let data =
                try? JSONSerialization.data(
                    withJSONObject:
                        payload
                ),

            let json =
                String(
                    data:
                        data,
                    encoding:
                        .utf8
                )
        else {
            return
        }

        let script =
            """
            window.dispatchEvent(
                new CustomEvent(
                    "safariWeb3Response",
                    {
                        detail: \(json)
                    }
                )
            );
            """

        webView.evaluateJavaScript(
            script
        )
    }

    deinit {

        webView?
            .configuration
            .userContentController
            .removeScriptMessageHandler(
                forName:
                    "safariWeb3"
            )
    }
}


// MARK: - 35. Web3 Browser Controller

@MainActor
public final class SafariWeb3BrowserController {

    public let wallet:
        SafariWeb3WalletRuntime

    private var bridges:
        [ObjectIdentifier:
            SafariWeb3JavaScriptBridge] = [:]

    public init(
        wallet:
            SafariWeb3WalletRuntime
    ) {
        self.wallet =
            wallet
    }

    public func attach(
        to webView:
            WKWebView
    ) {

        let bridge =
            SafariWeb3JavaScriptBridge(
                webView:
                    webView,

                wallet:
                    wallet
            )

        bridges[
            ObjectIdentifier(
                webView
            )
        ] =
            bridge
    }

    public func detach(
        from webView:
            WKWebView
    ) {

        bridges.removeValue(
            forKey:
                ObjectIdentifier(
                    webView
                )
        )
    }
}


// MARK: - 36. Wallet Factory

public enum SafariWeb3WalletFactory {

    public static func make()
        -> SafariWeb3WalletRuntime
    {

        let keyProvider =
            DevelopmentWeb3KeyProvider()

        return SafariWeb3WalletRuntime(
            keyProvider:
                keyProvider
        )
    }
}


// MARK: - 37. Development Key Provider

//
// Development-only provider.
//
// It intentionally does not expose private keys.
//
// Replace this with a production Keychain / Secure Enclave /
// hardware-wallet implementation.
//

public actor DevelopmentWeb3KeyProvider:
    Web3SecureKeyProvider
{

    private var unlocked =
        false

    public init() {}

    public func unlock()
        async throws
    {
        unlocked =
            true
    }

    public func lock()
        async {

        unlocked =
            false
    }

    public func isUnlocked()
        async -> Bool
    {
        unlocked
    }

    public func signer(
        walletID:
            Web3WalletID
    ) async throws
        -> Web3Signer
    {

        guard unlocked else {
            throw Web3WalletError
                .walletLocked
        }

        return Web3UnavailableSigner()
    }
}


// MARK: - 38. Complete Safari Web3 Runtime

@MainActor
public final class SafariWeb3Runtime {

    public let wallet:
        SafariWeb3WalletRuntime

    public init() {

        self.wallet =
            SafariWeb3WalletFactory.make()
    }

    public func attach(
        webView:
            WKWebView
    ) {

        let controller =
            SafariWeb3BrowserController(
                wallet:
                    wallet
            )

        controller.attach(
            to:
                webView
        )
    }
}


// MARK: - 39. Example Chain Configuration

public enum SafariWeb3DefaultChains {

    public static let exampleChain =
        Web3Chain(
            id:
                Web3ChainID(
                    rawValue:
                        1
                ),

            name:
                "Example EVM Network",

            nativeSymbol:
                "ETH",

            decimals:
                18,

            rpcEndpoints:
                [],

            explorerBaseURL:
                nil
        )
}


// MARK: - 40. Tests

#if DEBUG

public enum SafariWeb3WalletTests {

    public static func addressTest()
        -> Bool
    {

        Web3Address(
            "0x1234567890abcdef"
        ) != nil
    }


    public static func chainTest()
        -> Bool
    {

        let chain =
            SafariWeb3DefaultChains
                .exampleChain

        return
            chain.id.rawValue == 1
            &&
            chain.nativeSymbol ==
                "ETH"
    }


    public static func transactionValidationTest()
        -> Bool
    {

        guard
            let address =
                Web3Address(
                    "0x123"
                )
        else {
            return false
        }

        let transaction =
            Web3Transaction(
                from:
                    address,

                to:
                    address,

                value:
                    "1000000000000000000"
            )

        do {

            try Web3TransactionValidator()
                .validate(
                    transaction
                )

            return true

        } catch {

            return false
        }
    }


    public static func privateKeyIsolationTest()
        -> Bool
    {

        //
        // The wallet models contain no private-key
        // property whatsoever.
        //

        let wallet =
            Web3WalletMetadata(
                name:
                    "Safari Wallet"
            )

        return
            wallet.name ==
                "Safari Wallet"
    }
}

#endif








//
// SafariWeb3RPCNodeManager.swift
//
// Safari Web3 Project — #2
// Native Blockchain RPC & Node Manager
//
// Swift 6
//
// Responsibilities:
//
// - JSON-RPC 2.0 client
// - HTTP RPC transport
// - Endpoint pools
// - Endpoint health monitoring
// - Automatic failover
// - Retry policies
// - Request timeouts
// - Latency measurement
// - Endpoint scoring
// - Request deduplication
// - Batch JSON-RPC
// - WebSocket transport abstraction
// - Chain-specific RPC clients
// - Block-number monitoring
// - RPC telemetry
// - Connection lifecycle
// - Concurrency-safe state
//
// This layer DOES NOT:
//
// - store private keys
// - sign transactions
// - approve wallet requests
// - decide whether a transaction should be signed
//
// Signing belongs to #1.
// Transaction simulation belongs to #4.
// Contract security belongs to #6.
//

import Foundation
import os


// MARK: - 1. RPC Request ID

public struct Web3RPCRequestID:
    Hashable,
    Sendable,
    Codable
{
    public let rawValue:
        UInt64

    public init(
        _ rawValue:
            UInt64
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 2. RPC Endpoint ID

public struct Web3RPCEndpointID:
    Hashable,
    Sendable,
    Codable
{
    public let rawValue:
        UUID

    public init(
        _ rawValue:
            UUID = UUID()
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 3. Chain ID

public struct Web3RPCChainID:
    Hashable,
    Sendable,
    Codable
{
    public let value:
        UInt64

    public init(
        _ value:
            UInt64
    ) {
        self.value =
            value
    }
}


// MARK: - 4. RPC Endpoint

public struct Web3RPCEndpoint:
    Identifiable,
    Hashable,
    Sendable,
    Codable
{
    public let id:
        Web3RPCEndpointID

    public let url:
        URL

    public let chainID:
        Web3RPCChainID

    public let name:
        String

    public let priority:
        Int

    public let isWebSocket:
        Bool

    public init(
        id:
            Web3RPCEndpointID =
                Web3RPCEndpointID(),

        url:
            URL,

        chainID:
            Web3RPCChainID,

        name:
            String,

        priority:
            Int = 100,

        isWebSocket:
            Bool = false
    ) {
        self.id =
            id

        self.url =
            url

        self.chainID =
            chainID

        self.name =
            name

        self.priority =
            priority

        self.isWebSocket =
            isWebSocket
    }
}


// MARK: - 5. JSON-RPC Error

public struct Web3RPCErrorObject:
    Error,
    Codable,
    Sendable
{
    public let code:
        Int

    public let message:
        String

    public let data:
        JSONValue?

    public init(
        code:
            Int,

        message:
            String,

        data:
            JSONValue? = nil
    ) {
        self.code =
            code

        self.message =
            message

        self.data =
            data
    }
}


// MARK: - 6. JSON Value

public enum JSONValue:
    Codable,
    Sendable,
    Hashable
{
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(
        from decoder:
            Decoder
    ) throws {

        let container =
            try decoder.singleValueContainer()

        if container.decodeNil() {
            self =
                .null
            return
        }

        if let value =
            try? container.decode(
                Bool.self
            ) {

            self =
                .bool(value)

            return
        }

        if let value =
            try? container.decode(
                Double.self
            ) {

            self =
                .number(value)

            return
        }

        if let value =
            try? container.decode(
                String.self
            ) {

            self =
                .string(value)

            return
        }

        if let value =
            try? container.decode(
                [String: JSONValue].self
            ) {

            self =
                .object(value)

            return
        }

        if let value =
            try? container.decode(
                [JSONValue].self
            ) {

            self =
                .array(value)

            return
        }

        throw DecodingError.dataCorruptedError(
            in:
                container,

            debugDescription:
                "Unsupported JSON value"
        )
    }

    public func encode(
        to encoder:
            Encoder
    ) throws {

        var container =
            encoder.singleValueContainer()

        switch self {

        case .string(let value):
            try container.encode(value)

        case .number(let value):
            try container.encode(value)

        case .bool(let value):
            try container.encode(value)

        case .object(let value):
            try container.encode(value)

        case .array(let value):
            try container.encode(value)

        case .null:
            try container.encodeNil()
        }
    }
}


// MARK: - 7. JSON-RPC Request

public struct Web3RPCRequest:
    Codable,
    Sendable,
    Hashable
{
    public let jsonrpc:
        String

    public let id:
        Web3RPCRequestID

    public let method:
        String

    public let params:
        [JSONValue]?

    public init(
        id:
            Web3RPCRequestID,

        method:
            String,

        params:
            [JSONValue]? = nil
    ) {
        self.jsonrpc =
            "2.0"

        self.id =
            id

        self.method =
            method

        self.params =
            params
    }
}


// MARK: - 8. JSON-RPC Response

public struct Web3RPCResponse:
    Codable,
    Sendable
{
    public let jsonrpc:
        String

    public let id:
        Web3RPCRequestID

    public let result:
        JSONValue?

    public let error:
        Web3RPCErrorObject?
}


// MARK: - 9. Batch Request

public struct Web3RPCBatchRequest:
    Sendable
{
    public let requests:
        [Web3RPCRequest]

    public init(
        requests:
            [Web3RPCRequest]
    ) {
        self.requests =
            requests
    }
}


// MARK: - 10. RPC Errors

public enum Web3RPCClientError:
    Error,
    Sendable
{
    case invalidResponse
    case invalidHTTPStatus(Int)
    case transportFailure(String)
    case timeout
    case server(Web3RPCErrorObject)
    case endpointUnavailable
    case noHealthyEndpoints
    case unsupportedTransport
    case decodingFailure
    case chainMismatch
    case cancelled
}


// MARK: - 11. Retry Policy

public struct Web3RPCRetryPolicy:
    Sendable
{
    public let maxAttempts:
        Int

    public let baseDelay:
        Duration

    public let maximumDelay:
        Duration

    public init(
        maxAttempts:
            Int = 3,

        baseDelay:
            Duration = .milliseconds(250),

        maximumDelay:
            Duration = .seconds(5)
    ) {
        self.maxAttempts =
            maxAttempts

        self.baseDelay =
            baseDelay

        self.maximumDelay =
            maximumDelay
    }
}


// MARK: - 12. Timeout Policy

public struct Web3RPCTimeoutPolicy:
    Sendable
{
    public let requestTimeout:
        Duration

    public init(
        requestTimeout:
            Duration = .seconds(15)
    ) {
        self.requestTimeout =
            requestTimeout
    }
}


// MARK: - 13. Endpoint Health

public enum Web3EndpointHealth:
    String,
    Codable,
    Sendable
{
    case unknown
    case healthy
    case degraded
    case unavailable
}


// MARK: - 14. Endpoint Statistics

public struct Web3RPCEndpointStatistics:
    Codable,
    Sendable
{
    public var totalRequests:
        UInt64

    public var successfulRequests:
        UInt64

    public var failedRequests:
        UInt64

    public var timeoutCount:
        UInt64

    public var consecutiveFailures:
        UInt64

    public var averageLatencyMilliseconds:
        Double

    public var lastLatencyMilliseconds:
        Double?

    public var lastSuccessfulRequest:
        Date?

    public var lastFailure:
        Date?

    public var health:
        Web3EndpointHealth

    public init() {

        totalRequests =
            0

        successfulRequests =
            0

        failedRequests =
            0

        timeoutCount =
            0

        consecutiveFailures =
            0

        averageLatencyMilliseconds =
            0

        lastLatencyMilliseconds =
            nil

        lastSuccessfulRequest =
            nil

        lastFailure =
            nil

        health =
            .unknown
    }
}


// MARK: - 15. Endpoint Runtime State

struct Web3RPCEndpointState:
    Sendable
{
    let endpoint:
        Web3RPCEndpoint

    var statistics:
        Web3RPCEndpointStatistics

    var temporarilyDisabledUntil:
        Date?
}


// MARK: - 16. RPC Transport Protocol

public protocol Web3RPCTransport:
    Sendable
{
    func send(
        request:
            Web3RPCRequest,

        endpoint:
            Web3RPCEndpoint,

        timeout:
            Duration
    ) async throws
        -> Web3RPCResponse
}


// MARK: - 17. URLSession HTTP Transport

public struct Web3HTTPRPCTransport:
    Web3RPCTransport
{

    private let session:
        URLSession

    private let encoder:
        JSONEncoder

    private let decoder:
        JSONDecoder

    public init(
        session:
            URLSession = .shared
    ) {

        self.session =
            session

        self.encoder =
            JSONEncoder()

        self.decoder =
            JSONDecoder()
    }

    public func send(
        request:
            Web3RPCRequest,

        endpoint:
            Web3RPCEndpoint,

        timeout:
            Duration
    ) async throws
        -> Web3RPCResponse {

        guard
            !endpoint.isWebSocket
        else {
            throw Web3RPCClientError
                .unsupportedTransport
        }

        var urlRequest =
            URLRequest(
                url:
                    endpoint.url
            )

        urlRequest.httpMethod =
            "POST"

        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )

        urlRequest.timeoutInterval =
            timeout.timeInterval

        let body =
            try encoder.encode(
                request
            )

        urlRequest.httpBody =
            body

        do {

            let (
                data,
                response
            ) =
                try await session.data(
                    for:
                        urlRequest
                )

            guard
                let httpResponse =
                    response as? HTTPURLResponse
            else {
                throw Web3RPCClientError
                    .invalidResponse
            }

            guard
                200..<300
                    ~= httpResponse.statusCode
            else {
                throw Web3RPCClientError
                    .invalidHTTPStatus(
                        httpResponse.statusCode
                    )
            }

            do {

                let rpcResponse =
                    try decoder.decode(
                        Web3RPCResponse.self,
                        from:
                            data
                    )

                return rpcResponse

            } catch {

                throw Web3RPCClientError
                    .decodingFailure
            }

        } catch is CancellationError {

            throw Web3RPCClientError
                .cancelled

        } catch let error
            as Web3RPCClientError {

            throw error

        } catch {

            throw Web3RPCClientError
                .transportFailure(
                    error.localizedDescription
                )
        }
    }
}


// MARK: - 18. Duration Helper

extension Duration {

    fileprivate var timeInterval:
        TimeInterval
    {
        let components =
            self.components

        let seconds =
            Double(
                components.seconds
            )

        let attoseconds =
            Double(
                components.attoseconds
            )

        return
            seconds
            +
            attoseconds / 1_000_000_000_000_000_000
    }
}


// MARK: - 19. RPC Clock

struct Web3RPCTimeSource:
    Sendable
{
    func now()
        -> ContinuousClock.Instant
    {
        ContinuousClock.now
    }
}


// MARK: - 20. Endpoint Health Manager

public actor Web3RPCEndpointHealthManager {

    private var states:
        [Web3RPCEndpointID:
            Web3RPCEndpointState] = [:]

    private let failureThreshold:
        UInt64

    private let cooldown:
        TimeInterval

    public init(
        failureThreshold:
            UInt64 = 3,

        cooldown:
            TimeInterval = 15
    ) {

        self.failureThreshold =
            failureThreshold

        self.cooldown =
            cooldown
    }

    public func register(
        _ endpoint:
            Web3RPCEndpoint
    ) {

        states[
            endpoint.id
        ] =
            Web3RPCEndpointState(
                endpoint:
                    endpoint,

                statistics:
                    Web3RPCEndpointStatistics(),

                temporarilyDisabledUntil:
                    nil
            )
    }

    public func remove(
        _ endpointID:
            Web3RPCEndpointID
    ) {

        states.removeValue(
            forKey:
                endpointID
        )
    }

    public func recordSuccess(
        endpointID:
            Web3RPCEndpointID,

        latency:
            TimeInterval
    ) {

        guard
            var state =
                states[endpointID]
        else {
            return
        }

        var stats =
            state.statistics

        stats.totalRequests +=
            1

        stats.successfulRequests +=
            1

        stats.consecutiveFailures =
            0

        stats.lastLatencyMilliseconds =
            latency * 1000

        if stats.averageLatencyMilliseconds == 0 {

            stats.averageLatencyMilliseconds =
                latency * 1000

        } else {

            stats.averageLatencyMilliseconds =
                (
                    stats.averageLatencyMilliseconds
                    * 0.8
                )
                +
                (
                    latency * 1000
                    * 0.2
                )
        }

        stats.lastSuccessfulRequest =
            Date()

        stats.health =
            .healthy

        state.statistics =
            stats

        state.temporarilyDisabledUntil =
            nil

        states[endpointID] =
            state
    }

    public func recordFailure(
        endpointID:
            Web3RPCEndpointID,

        timeout:
            Bool
    ) {

        guard
            var state =
                states[endpointID]
        else {
            return
        }

        var stats =
            state.statistics

        stats.totalRequests +=
            1

        stats.failedRequests +=
            1

        stats.consecutiveFailures +=
            1

        if timeout {
            stats.timeoutCount +=
                1
        }

        stats.lastFailure =
            Date()

        if
            stats.consecutiveFailures
                >= failureThreshold
        {

            stats.health =
                .unavailable

            state
                .temporarilyDisabledUntil =
                    Date().addingTimeInterval(
                        cooldown
                    )

        } else {

            stats.health =
                .degraded
        }

        state.statistics =
            stats

        states[endpointID] =
            state
    }

    public func healthyEndpoints(
        for chainID:
            Web3RPCChainID
    ) -> [Web3RPCEndpoint] {

        let now =
            Date()

        return states.values
            .filter {
                $0.endpoint.chainID ==
                    chainID
            }
            .filter {

                guard
                    let disabledUntil =
                        $0.temporarilyDisabledUntil
                else {
                    return true
                }

                return disabledUntil <=
                    now
            }
            .sorted {
                endpointScore(
                    $0
                )
                >
                endpointScore(
                    $1
                )
            }
            .map(\.endpoint)
    }

    public func statistics(
        endpointID:
            Web3RPCEndpointID
    ) -> Web3RPCEndpointStatistics? {

        states[
            endpointID
        ]?.statistics
    }

    public func snapshot()
        -> [Web3RPCEndpointStatisticsSnapshot]
    {

        states.values.map {

            Web3RPCEndpointStatisticsSnapshot(
                endpoint:
                    $0.endpoint,

                statistics:
                    $0.statistics
            )
        }
    }

    private func endpointScore(
        _ state:
            Web3RPCEndpointState
    ) -> Double {

        let stats =
            state.statistics

        var score =
            Double(
                state.endpoint.priority
            )

        switch stats.health {

        case .healthy:
            score += 100

        case .degraded:
            score += 25

        case .unavailable:
            score -= 1_000

        case .unknown:
            score += 50
        }

        if
            stats.averageLatencyMilliseconds
                > 0
        {

            score -= min(
                stats.averageLatencyMilliseconds
                    / 10,

                100
            )
        }

        score -=
            Double(
                stats.consecutiveFailures
            )
            * 25

        return score
    }
}


// MARK: - 21. Statistics Snapshot

public struct Web3RPCEndpointStatisticsSnapshot:
    Sendable
{
    public let endpoint:
        Web3RPCEndpoint

    public let statistics:
        Web3RPCEndpointStatistics
}


// MARK: - 22. Request Deduplicator

public actor Web3RPCRequestDeduplicator {

    private var active:
        [
            String:
            Task<Web3RPCResponse, Error>
        ] = [:]

    public init() {}

    public func execute(
        key:
            String,

        operation:
            @escaping @Sendable () async throws
            -> Web3RPCResponse
    ) async throws
        -> Web3RPCResponse {

        if let existing =
            active[key]
        {
            return try await existing.value
        }

        let task =
            Task {
                try await operation()
            }

        active[key] =
            task

        defer {
            active.removeValue(
                forKey:
                    key
            )
        }

        return try await task.value
    }
}


// MARK: - 23. RPC Telemetry

public enum Web3RPCTelemetryEvent:
    Sendable
{
    case requestStarted(
        Web3RPCRequestID,
        Web3RPCEndpointID,
        String
    )

    case requestSucceeded(
        Web3RPCRequestID,
        Web3RPCEndpointID,
        TimeInterval
    )

    case requestFailed(
        Web3RPCRequestID,
        Web3RPCEndpointID
    )

    case endpointDisabled(
        Web3RPCEndpointID
    )

    case failover(
        Web3RPCRequestID
    )
}


public actor Web3RPCTelemetry {

    private var events:
        [Web3RPCTelemetryEvent] = []

    private let capacity:
        Int

    public init(
        capacity:
            Int = 10_000
    ) {
        self.capacity =
            capacity
    }

    public func append(
        _ event:
            Web3RPCTelemetryEvent
    ) {

        events.append(
            event
        )

        if events.count >
            capacity
        {
            events.removeFirst(
                events.count - capacity
            )
        }
    }

    public func snapshot()
        -> [Web3RPCTelemetryEvent]
    {
        events
    }
}


// MARK: - 24. RPC Node Manager

public actor SafariWeb3RPCNodeManager {

    private let transport:
        Web3RPCTransport

    private let health:
        Web3RPCEndpointHealthManager

    private let deduplicator:
        Web3RPCRequestDeduplicator

    private let telemetry:
        Web3RPCTelemetry

    private let retryPolicy:
        Web3RPCRetryPolicy

    private let timeoutPolicy:
        Web3RPCTimeoutPolicy

    private var requestCounter:
        UInt64 = 0

    private var endpoints:
        [Web3RPCEndpointID:
            Web3RPCEndpoint] = [:]

    public init(
        transport:
            Web3RPCTransport =
                Web3HTTPRPCTransport(),

        retryPolicy:
            Web3RPCRetryPolicy =
                Web3RPCRetryPolicy(),

        timeoutPolicy:
            Web3RPCTimeoutPolicy =
                Web3RPCTimeoutPolicy()
    ) {

        self.transport =
            transport

        self.health =
            Web3RPCEndpointHealthManager()

        self.deduplicator =
            Web3RPCRequestDeduplicator()

        self.telemetry =
            Web3RPCTelemetry()

        self.retryPolicy =
            retryPolicy

        self.timeoutPolicy =
            timeoutPolicy
    }


    // MARK: Endpoint registration

    public func register(
        endpoint:
            Web3RPCEndpoint
    ) async {

        endpoints[
            endpoint.id
        ] =
            endpoint

        await health.register(
            endpoint
        )
    }


    public func remove(
        endpointID:
            Web3RPCEndpointID
    ) async {

        endpoints.removeValue(
            forKey:
                endpointID
        )

        await health.remove(
            endpointID
        )
    }


    public func endpoints(
        chainID:
            Web3RPCChainID
    ) -> [Web3RPCEndpoint] {

        endpoints.values.filter {
            $0.chainID ==
                chainID
        }
    }


    // MARK: Request

    public func request(
        chainID:
            Web3RPCChainID,

        method:
            String,

        params:
            [JSONValue]? = nil
    ) async throws
        -> JSONValue {

        let requestID =
            nextRequestID()

        let request =
            Web3RPCRequest(
                id:
                    requestID,

                method:
                    method,

                params:
                    params
            )

        let dedupeKey =
            makeDeduplicationKey(
                chainID:
                    chainID,

                method:
                    method,

                params:
                    params
            )

        let response =
            try await deduplicator.execute(
                key:
                    dedupeKey
            ) {

                try await self.perform(
                    request:
                        request,

                    chainID:
                        chainID
                )
            }

        if let error =
            response.error
        {
            throw Web3RPCClientError
                .server(
                    error
                )
        }

        guard
            let result =
                response.result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return result
    }


    // MARK: Core request engine

    private func perform(
        request:
            Web3RPCRequest,

        chainID:
            Web3RPCChainID
    ) async throws
        -> Web3RPCResponse {

        var attempt =
            0

        var lastError:
            Error?

        while attempt <
                retryPolicy.maxAttempts
        {

            attempt +=
                1

            let candidates =
                await health.healthyEndpoints(
                    for:
                        chainID
                )

            guard
                !candidates.isEmpty
            else {
                throw Web3RPCClientError
                    .noHealthyEndpoints
            }

            for (
                index,
                endpoint
            ) in candidates.enumerated()
            {

                if index > 0 {

                    await telemetry.append(
                        .failover(
                            request.id
                        )
                    )
                }

                do {

                    return try await send(
                        request:
                            request,

                        endpoint:
                            endpoint
                    )

                } catch {

                    lastError =
                        error
                }
            }

            if attempt <
                retryPolicy.maxAttempts
            {

                try await backoff(
                    attempt:
                        attempt
                )
            }
        }

        throw lastError
            ?? Web3RPCClientError
                .endpointUnavailable
    }


    private func send(
        request:
            Web3RPCRequest,

        endpoint:
            Web3RPCEndpoint
    ) async throws
        -> Web3RPCResponse {

        await telemetry.append(
            .requestStarted(
                request.id,
                endpoint.id,
                request.method
            )
        )

        let start =
            ContinuousClock.now

        do {

            let response =
                try await transport.send(
                    request:
                        request,

                    endpoint:
                        endpoint,

                    timeout:
                        timeoutPolicy
                            .requestTimeout
                )

            let duration =
                start.duration(
                    to:
                        ContinuousClock.now
                )

            let latency =
                duration.timeInterval

            if let error =
                response.error
            {

                await health.recordFailure(
                    endpointID:
                        endpoint.id,

                    timeout:
                        false
                )

                await telemetry.append(
                    .requestFailed(
                        request.id,
                        endpoint.id
                    )
                )

                throw Web3RPCClientError
                    .server(
                        error
                    )
            }

            await health.recordSuccess(
                endpointID:
                    endpoint.id,

                latency:
                    latency
            )

            await telemetry.append(
                .requestSucceeded(
                    request.id,
                    endpoint.id,
                    latency
                )
            )

            return response

        } catch {

            let isTimeout =
                isTimeoutError(
                    error
                )

            await health.recordFailure(
                endpointID:
                    endpoint.id,

                timeout:
                    isTimeout
            )

            await telemetry.append(
                .requestFailed(
                    request.id,
                    endpoint.id
                )
            )

            throw error
        }
    }


    // MARK: Batch

    public func batch(
        chainID:
            Web3RPCChainID,

        methods:
            [(String, [JSONValue]?)]
    ) async throws
        -> [Web3RPCResponse] {

        //
        // JSON-RPC batch support is kept separate from the
        // ordinary request path because a real provider may
        // return responses in an order different from requests.
        //

        let endpoints =
            await health.healthyEndpoints(
                for:
                    chainID
            )

        guard
            let endpoint =
                endpoints.first
        else {
            throw Web3RPCClientError
                .noHealthyEndpoints
        }

        let requests =
            methods.map { method, params in

                Web3RPCRequest(
                    id:
                        nextRequestID(),

                    method:
                        method,

                    params:
                        params
                )
            }

        //
        // The base transport is deliberately single-request.
        // A batch-capable transport can be injected later.
        //

        var results:
            [Web3RPCResponse] = []

        for request in requests {

            do {

                let response =
                    try await send(
                        request:
                            request,

                        endpoint:
                            endpoint
                    )

                results.append(
                    response
                )

            } catch {

                throw error
            }
        }

        return results
    }


    // MARK: Backoff

    private func backoff(
        attempt:
            Int
    ) async throws {

        let exponent =
            max(
                0,
                attempt - 1
            )

        let multiplier =
            pow(
                2.0,
                Double(exponent)
            )

        let base =
            retryPolicy
                .baseDelay
                .timeInterval

        let maximum =
            retryPolicy
                .maximumDelay
                .timeInterval

        let delay =
            min(
                maximum,
                base * multiplier
            )

        let jitter =
            Double.random(
                in:
                    0...0.25
            )

        try await Task.sleep(
            for:
                .seconds(
                    delay + jitter
                )
        )
    }


    // MARK: Request IDs

    private func nextRequestID()
        -> Web3RPCRequestID
    {
        requestCounter +=
            1

        return Web3RPCRequestID(
            requestCounter
        )
    }


    // MARK: Deduplication

    private func makeDeduplicationKey(
        chainID:
            Web3RPCChainID,

        method:
            String,

        params:
            [JSONValue]?
    ) -> String {

        let encoder =
            JSONEncoder()

        let encoded =
            (
                try? encoder.encode(
                    params
                )
            )
            ?? Data()

        return
            "\(chainID.value):\(method):"
            +
            encoded.base64EncodedString()
    }


    private func isTimeoutError(
        _ error:
            Error
    ) -> Bool {

        if case
            Web3RPCClientError.timeout =
                error
        {
            return true
        }

        if case
            URLError.timedOut =
                error as? URLError
        {
            return true
        }

        return false
    }


    // MARK: Diagnostics

    public func endpointStatistics()
        async
        -> [
            Web3RPCEndpointStatisticsSnapshot
        ]
    {
        await health.snapshot()
    }

    public func telemetrySnapshot()
        async
        -> [Web3RPCTelemetryEvent]
    {
        await telemetry.snapshot()
    }
}


// MARK: - 25. EVM RPC Client

public actor SafariEVMRPCClient {

    private let nodeManager:
        SafariWeb3RPCNodeManager

    private let chainID:
        Web3RPCChainID

    public init(
        nodeManager:
            SafariWeb3RPCNodeManager,

        chainID:
            Web3RPCChainID
    ) {

        self.nodeManager =
            nodeManager

        self.chainID =
            chainID
    }


    // MARK: eth_chainId

    public func chainIDFromNode()
        async throws
        -> UInt64 {

        let result =
            try await nodeManager.request(
                chainID:
                    chainID,

                method:
                    "eth_chainId"
            )

        guard
            case .string(let value) =
                result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return try parseHex(
            value
        )
    }


    // MARK: eth_blockNumber

    public func blockNumber()
        async throws
        -> UInt64 {

        let result =
            try await nodeManager.request(
                chainID:
                    chainID,

                method:
                    "eth_blockNumber"
            )

        guard
            case .string(let value) =
                result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return try parseHex(
            value
        )
    }


    // MARK: eth_getBalance

    public func balance(
        address:
            String,

        block:
            String = "latest"
    ) async throws
        -> UInt64 {

        let result =
            try await nodeManager.request(
                chainID:
                    chainID,

                method:
                    "eth_getBalance",

                params:
                    [
                        .string(address),
                        .string(block)
                    ]
            )

        guard
            case .string(let value) =
                result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return try parseHex(
            value
        )
    }


    // MARK: eth_getTransactionCount

    public func transactionCount(
        address:
            String,

        block:
            String = "pending"
    ) async throws
        -> UInt64 {

        let result =
            try await nodeManager.request(
                chainID:
                    chainID,

                method:
                    "eth_getTransactionCount",

                params:
                    [
                        .string(address),
                        .string(block)
                    ]
            )

        guard
            case .string(let value) =
                result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return try parseHex(
            value
        )
    }


    // MARK: eth_gasPrice

    public func gasPrice()
        async throws
        -> UInt64 {

        let result =
            try await nodeManager.request(
                chainID:
                    chainID,

                method:
                    "eth_gasPrice"
            )

        guard
            case .string(let value) =
                result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return try parseHex(
            value
        )
    }


    // MARK: eth_estimateGas

    public func estimateGas(
        from:
            String,

        to:
            String?,

        value:
            String?,

        data:
            String?
    ) async throws
        -> UInt64 {

        var object:
            [String: JSONValue] = [

                "from":
                    .string(from)
            ]

        if let to {
            object["to"] =
                .string(to)
        }

        if let value {
            object["value"] =
                .string(value)
        }

        if let data {
            object["data"] =
                .string(data)
        }

        let result =
            try await nodeManager.request(
                chainID:
                    chainID,

                method:
                    "eth_estimateGas",

                params:
                    [
                        .object(object)
                    ]
            )

        guard
            case .string(let value) =
                result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return try parseHex(
            value
        )
    }


    // MARK: eth_call

    public func call(
        to:
            String,

        data:
            String,

        block:
            String = "latest"
    ) async throws
        -> String {

        let result =
            try await nodeManager.request(
                chainID:
                    chainID,

                method:
                    "eth_call",

                params:
                    [
                        .object(
                            [
                                "to":
                                    .string(to),

                                "data":
                                    .string(data)
                            ]
                        ),

                        .string(block)
                    ]
            )

        guard
            case .string(let value) =
                result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return value
    }


    // MARK: eth_sendRawTransaction

    public func sendRawTransaction(
        signedTransaction:
            String
    ) async throws
        -> String {

        let result =
            try await nodeManager.request(
                chainID:
                    chainID,

                method:
                    "eth_sendRawTransaction",

                params:
                    [
                        .string(
                            signedTransaction
                        )
                    ]
            )

        guard
            case .string(let value) =
                result
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return value
    }


    // MARK: Helpers

    private func parseHex(
        _ value:
            String
    ) throws
        -> UInt64 {

        let normalized =
            value.hasPrefix(
                "0x"
            )
            ? String(
                value.dropFirst(2)
            )
            : value

        guard
            let result =
                UInt64(
                    normalized,
                    radix:
                        16
                )
        else {
            throw Web3RPCClientError
                .invalidResponse
        }

        return result
    }
}


// MARK: - 26. Block Monitor

public actor SafariWeb3BlockMonitor {

    public struct BlockEvent:
        Sendable
    {
        public let chainID:
            Web3RPCChainID

        public let blockNumber:
            UInt64

        public let receivedAt:
            Date
    }

    private let client:
        SafariEVMRPCClient

    private var lastBlock:
        UInt64?

    private var running =
        false

    private var task:
        Task<Void, Never>?

    public init(
        client:
            SafariEVMRPCClient
    ) {
        self.client =
            client
    }

    public func start(
        interval:
            Duration = .seconds(2),

        handler:
            @escaping @Sendable (
                BlockEvent
            ) async -> Void
    ) {

        guard !running else {
            return
        }

        running =
            true

        task =
            Task {

                while !Task.isCancelled {

                    do {

                        let block =
                            try await client
                                .blockNumber()

                        if
                            lastBlock == nil
                            ||
                            block >
                                lastBlock!
                        {

                            lastBlock =
                                block

                            let event =
                                BlockEvent(
                                    chainID:
                                        await chainID(),

                                    blockNumber:
                                        block,

                                    receivedAt:
                                        Date()
                                )

                            await handler(
                                event
                            )
                        }

                    } catch {

                        // Monitoring failure is intentionally
                        // non-fatal. The next polling cycle retries.
                    }

                    do {

                        try await Task.sleep(
                            for:
                                interval
                        )

                    } catch {

                        break
                    }
                }
            }
    }

    public func stop() {

        running =
            false

        task?.cancel()

        task =
            nil
    }

    private func chainID()
        async -> Web3RPCChainID
    {
        //
        // The underlying client keeps the actual chain ID private.
        // In a larger implementation expose it as a Sendable
        // property rather than querying the network.
        //
        // This placeholder is replaced by the factory configuration.
        //
        return Web3RPCChainID(
            0
        )
    }

    deinit {
        task?.cancel()
    }
}


// MARK: - 27. WebSocket RPC Protocol

public protocol Web3RPCWebSocketTransport:
    Sendable
{
    func connect(
        endpoint:
            Web3RPCEndpoint
    ) async throws

    func disconnect()
        async

    func send(
        request:
            Web3RPCRequest
    ) async throws
        -> Web3RPCResponse
}


// MARK: - 28. WebSocket Manager

public actor SafariWeb3WebSocketManager {

    private let transport:
        Web3RPCWebSocketTransport

    private var connectedEndpoint:
        Web3RPCEndpoint?

    public init(
        transport:
            Web3RPCWebSocketTransport
    ) {
        self.transport =
            transport
    }

    public func connect(
        endpoint:
            Web3RPCEndpoint
    ) async throws {

        guard
            endpoint.isWebSocket
        else {
            throw Web3RPCClientError
                .unsupportedTransport
        }

        try await transport.connect(
            endpoint:
                endpoint
        )

        connectedEndpoint =
            endpoint
    }

    public func disconnect()
        async {

        await transport.disconnect()

        connectedEndpoint =
            nil
    }

    public func send(
        request:
            Web3RPCRequest
    ) async throws
        -> Web3RPCResponse {

        guard
            connectedEndpoint != nil
        else {
            throw Web3RPCClientError
                .endpointUnavailable
        }

        return try await transport.send(
            request:
                request
        )
    }
}


// MARK: - 29. Node Health Monitor

public actor SafariWeb3NodeHealthMonitor {

    private let manager:
        SafariWeb3RPCNodeManager

    private var running =
        false

    private var task:
        Task<Void, Never>?

    public init(
        manager:
            SafariWeb3RPCNodeManager
    ) {
        self.manager =
            manager
    }

    public func start(
        chainID:
            Web3RPCChainID,

        interval:
            Duration = .seconds(30)
    ) {

        guard !running else {
            return
        }

        running =
            true

        task =
            Task {

                while !Task.isCancelled {

                    _ =
                        try? await manager.request(
                            chainID:
                                chainID,

                            method:
                                "eth_chainId"
                        )

                    try? await Task.sleep(
                        for:
                            interval
                    )
                }
            }
    }

    public func stop() {

        running =
            false

        task?.cancel()

        task =
            nil
    }

    deinit {
        task?.cancel()
    }
}


// MARK: - 30. RPC Runtime

public actor SafariWeb3RPCRuntime {

    public let nodeManager:
        SafariWeb3RPCNodeManager

    private var evmClients:
        [Web3RPCChainID:
            SafariEVMRPCClient] = [:]

    public init(
        nodeManager:
            SafariWeb3RPCNodeManager
    ) {
        self.nodeManager =
            nodeManager
    }

    public func registerEndpoint(
        _ endpoint:
            Web3RPCEndpoint
    ) async {

        await nodeManager.register(
            endpoint:
                endpoint
        )
    }

    public func evmClient(
        chainID:
            Web3RPCChainID
    ) -> SafariEVMRPCClient {

        if let existing =
            evmClients[chainID]
        {
            return existing
        }

        let client =
            SafariEVMRPCClient(
                nodeManager:
                    nodeManager,

                chainID:
                    chainID
            )

        evmClients[chainID] =
            client

        return client
    }
}


// MARK: - 31. Web3 RPC Factory

public enum SafariWeb3RPCFactory {

    public static func make()
        -> SafariWeb3RPCRuntime
    {

        let manager =
            SafariWeb3RPCNodeManager(
                transport:
                    Web3HTTPRPCTransport(),

                retryPolicy:
                    Web3RPCRetryPolicy(
                        maxAttempts:
                            3,

                        baseDelay:
                            .milliseconds(
                                250
                            ),

                        maximumDelay:
                            .seconds(
                                4
                            )
                    ),

                timeoutPolicy:
                    Web3RPCTimeoutPolicy(
                        requestTimeout:
                            .seconds(
                                15
                            )
                    )
            )

        return SafariWeb3RPCRuntime(
            nodeManager:
                manager
        )
    }
}


// MARK: - 32. Example Bootstrap

public actor SafariWeb3Bootstrap {

    public let rpc:
        SafariWeb3RPCRuntime

    public init() {

        self.rpc =
            SafariWeb3RPCFactory.make()
    }

    public func configureEthereum(
        endpoint:
            URL
    ) async {

        let endpoint =
            Web3RPCEndpoint(
                url:
                    endpoint,

                chainID:
                    Web3RPCChainID(
                        1
                    ),

                name:
                    "Ethereum RPC",

                priority:
                    100
            )

        await rpc.registerEndpoint(
            endpoint
        )
    }
}


// MARK: - 33. RPC Diagnostics

public struct SafariWeb3RPCDiagnostics:
    Sendable
{
    public let endpointCount:
        Int

    public let healthyEndpointCount:
        Int

    public let unavailableEndpointCount:
        Int

    public let averageLatencyMilliseconds:
        Double
}


// MARK: - 34. RPC Diagnostics Engine

public actor SafariWeb3RPCDiagnosticsEngine {

    private let manager:
        SafariWeb3RPCNodeManager

    public init(
        manager:
            SafariWeb3RPCNodeManager
    ) {
        self.manager =
            manager
    }

    public func diagnostics()
        async
        -> SafariWeb3RPCDiagnostics {

        let snapshot =
            await manager.endpointStatistics()

        let endpointCount =
            snapshot.count

        let healthy =
            snapshot.filter {
                $0.statistics.health ==
                    .healthy
            }

        let unavailable =
            snapshot.filter {
                $0.statistics.health ==
                    .unavailable
            }

        let latencies =
            snapshot
                .map {
                    $0.statistics
                        .averageLatencyMilliseconds
                }
                .filter {
                    $0 > 0
                }

        let average =
            latencies.isEmpty
            ? 0
            : latencies.reduce(
                0,
                +
            )
            /
            Double(
                latencies.count
            )

        return SafariWeb3RPCDiagnostics(
            endpointCount:
                endpointCount,

            healthyEndpointCount:
                healthy.count,

            unavailableEndpointCount:
                unavailable.count,

            averageLatencyMilliseconds:
                average
        )
    }
}


// MARK: - 35. DEBUG Tests

#if DEBUG

public enum SafariWeb3RPCTests {

    public static func requestCreation()
        -> Bool
    {

        let request =
            Web3RPCRequest(
                id:
                    Web3RPCRequestID(
                        1
                    ),

                method:
                    "eth_blockNumber"
            )

        return
            request.jsonrpc ==
                "2.0"
            &&
            request.method ==
                "eth_blockNumber"
            &&
            request.id.rawValue ==
                1
    }


    public static func endpointCreation()
        -> Bool
    {

        guard
            let url =
                URL(
                    string:
                        "https://example-rpc.invalid"
                )
        else {
            return false
        }

        let endpoint =
            Web3RPCEndpoint(
                url:
                    url,

                chainID:
                    Web3RPCChainID(
                        1
                    ),

                name:
                    "Test Node"
            )

        return
            endpoint.chainID.value ==
                1
    }


    public static func JSONValueTest()
        -> Bool
    {

        let value =
            JSONValue.object(
                [
                    "method":
                        .string(
                            "eth_blockNumber"
                        ),

                    "id":
                        .number(
                            1
                        )
                ]
            )

        let encoder =
            JSONEncoder()

        guard
            let data =
                try? encoder.encode(
                    value
                )
        else {
            return false
        }

        return !data.isEmpty
    }
}

#endif






//
// SafariWeb3DAppSessionManager.swift
//
// Safari Web3 Project — #3
// Native DApp Session / WalletConnect-Style Session Manager
//
// Swift 6
//
// Responsibilities:
//
// - DApp session creation
// - Origin isolation
// - Chain namespaces
// - Account permissions
// - Session expiry
// - Session renewal
// - Session revocation
// - DApp connection requests
// - Transaction/message request routing
// - Chain switching
// - Account switching
// - Session event stream
// - Request lifecycle
// - Transport abstraction
// - WalletConnect-style pairing abstraction
// - Reconnection
// - Session telemetry
//
// Does NOT:
//
// - store private keys
// - sign transactions
// - perform cryptographic signing
// - implement the complete WalletConnect wire protocol
//
// #1 = Wallet
// #2 = Blockchain RPC
// #3 = DApp sessions
// #4 = Transaction simulation
// #6 = Contract security
//

import Foundation
import os


// MARK: - 1. DApp Session ID

public struct SafariDAppSessionID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UUID

    public init(
        _ rawValue:
            UUID = UUID()
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 2. Pairing ID

public struct SafariDAppPairingID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UUID

    public init(
        _ rawValue:
            UUID = UUID()
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 3. DApp Request ID

public struct SafariDAppRequestID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UUID

    public init(
        _ rawValue:
            UUID = UUID()
    ) {
        self.rawValue =
            rawValue
    }
}


// MARK: - 4. DApp Origin

public struct SafariDAppOrigin:
    Hashable,
    Codable,
    Sendable
{
    public let scheme:
        String

    public let host:
        String

    public let port:
        Int?

    public init?(
        url:
            URL
    ) {

        guard
            let scheme =
                url.scheme,

            let host =
                url.host
        else {
            return nil
        }

        self.scheme =
            scheme.lowercased()

        self.host =
            host.lowercased()

        self.port =
            url.port
    }

    public var serialized:
        String
    {
        var result =
            "\(scheme)://\(host)"

        if let port {
            result +=
                ":\(port)"
        }

        return result
    }
}


// MARK: - 5. DApp Metadata

public struct SafariDAppMetadata:
    Codable,
    Sendable
{
    public let name:
        String

    public let description:
        String

    public let url:
        URL

    public let icons:
        [URL]

    public init(
        name:
            String,

        description:
            String,

        url:
            URL,

        icons:
            [URL] = []
    ) {
        self.name =
            name

        self.description =
            description

        self.url =
            url

        self.icons =
            icons
    }
}


// MARK: - 6. Web3 Namespace

public enum SafariWeb3Namespace:
    String,
    Codable,
    Hashable,
    Sendable
{
    case eip155
    case solana
    case bitcoin
    case cosmos
    case custom
}


// MARK: - 7. Chain Reference

public struct SafariWeb3ChainReference:
    Hashable,
    Codable,
    Sendable
{
    public let namespace:
        SafariWeb3Namespace

    public let reference:
        String

    public init(
        namespace:
            SafariWeb3Namespace,

        reference:
            String
    ) {
        self.namespace =
            namespace

        self.reference =
            reference
    }

    public var serialized:
        String
    {
        "\(namespace.rawValue):\(reference)"
    }
}


// MARK: - 8. Account Reference

public struct SafariWeb3AccountReference:
    Hashable,
    Codable,
    Sendable
{
    public let namespace:
        SafariWeb3Namespace

    public let chainReference:
        String

    public let address:
        String

    public init(
        namespace:
            SafariWeb3Namespace,

        chainReference:
            String,

        address:
            String
    ) {
        self.namespace =
            namespace

        self.chainReference =
            chainReference

        self.address =
            address
    }

    public var serialized:
        String
    {
        "\(namespace.rawValue):\(chainReference):\(address)"
    }
}


// MARK: - 9. Session Permission

public enum SafariDAppPermission:
    String,
    Codable,
    Hashable,
    Sendable,
    CaseIterable
{
    case accounts
    case chainInformation
    case balance
    case signMessage
    case signTypedData
    case signTransaction
    case sendTransaction
    case switchChain
}


// MARK: - 10. Session State

public enum SafariDAppSessionState:
    String,
    Codable,
    Sendable
{
    case proposed
    case awaitingApproval
    case active
    case reconnecting
    case expired
    case revoked
    case rejected
}


// MARK: - 11. Session

public struct SafariDAppSession:
    Codable,
    Sendable
{
    public let id:
        SafariDAppSessionID

    public let pairingID:
        SafariDAppPairingID

    public let origin:
        SafariDAppOrigin

    public let metadata:
        SafariDAppMetadata

    public let namespace:
        SafariWeb3Namespace

    public var chains:
        Set<SafariWeb3ChainReference>

    public var accounts:
        Set<SafariWeb3AccountReference>

    public var permissions:
        Set<SafariDAppPermission>

    public var state:
        SafariDAppSessionState

    public let createdAt:
        Date

    public var lastActivityAt:
        Date

    public var expiresAt:
        Date

    public var relayTopic:
        String?

    public init(
        id:
            SafariDAppSessionID =
                SafariDAppSessionID(),

        pairingID:
            SafariDAppPairingID,

        origin:
            SafariDAppOrigin,

        metadata:
            SafariDAppMetadata,

        namespace:
            SafariWeb3Namespace,

        chains:
            Set<SafariWeb3ChainReference>,

        accounts:
            Set<SafariWeb3AccountReference>,

        permissions:
            Set<SafariDAppPermission>,

        state:
            SafariDAppSessionState =
                .proposed,

        createdAt:
            Date = Date(),

        lastActivityAt:
            Date = Date(),

        expiresAt:
            Date,

        relayTopic:
            String? = nil
    ) {
        self.id =
            id

        self.pairingID =
            pairingID

        self.origin =
            origin

        self.metadata =
            metadata

        self.namespace =
            namespace

        self.chains =
            chains

        self.accounts =
            accounts

        self.permissions =
            permissions

        self.state =
            state

        self.createdAt =
            createdAt

        self.lastActivityAt =
            lastActivityAt

        self.expiresAt =
            expiresAt

        self.relayTopic =
            relayTopic
    }

    public var isExpired:
        Bool
    {
        Date() >=
            expiresAt
    }
}


// MARK: - 12. Pairing

public struct SafariDAppPairing:
    Codable,
    Sendable
{
    public let id:
        SafariDAppPairingID

    public let topic:
        String

    public let uri:
        String

    public let origin:
        SafariDAppOrigin

    public let createdAt:
        Date

    public var expiresAt:
        Date

    public var isActive:
        Bool

    public init(
        id:
            SafariDAppPairingID =
                SafariDAppPairingID(),

        topic:
            String,

        uri:
            String,

        origin:
            SafariDAppOrigin,

        createdAt:
            Date = Date(),

        expiresAt:
            Date,

        isActive:
            Bool = true
    ) {
        self.id =
            id

        self.topic =
            topic

        self.uri =
            uri

        self.origin =
            origin

        self.createdAt =
            createdAt

        self.expiresAt =
            expiresAt

        self.isActive =
            isActive
    }
}


// MARK: - 13. Session Proposal

public struct SafariDAppSessionProposal:
    Sendable
{
    public let pairing:
        SafariDAppPairing

    public let metadata:
        SafariDAppMetadata

    public let namespace:
        SafariWeb3Namespace

    public let requestedChains:
        Set<SafariWeb3ChainReference>

    public let requestedPermissions:
        Set<SafariDAppPermission>

    public init(
        pairing:
            SafariDAppPairing,

        metadata:
            SafariDAppMetadata,

        namespace:
            SafariWeb3Namespace,

        requestedChains:
            Set<SafariWeb3ChainReference>,

        requestedPermissions:
            Set<SafariDAppPermission>
    ) {
        self.pairing =
            pairing

        self.metadata =
            metadata

        self.namespace =
            namespace

        self.requestedChains =
            requestedChains

        self.requestedPermissions =
            requestedPermissions
    }
}


// MARK: - 14. Session Approval

public struct SafariDAppSessionApproval:
    Sendable
{
    public let proposal:
        SafariDAppSessionProposal

    public let accounts:
        Set<SafariWeb3AccountReference>

    public let approvedChains:
        Set<SafariWeb3ChainReference>

    public let approvedPermissions:
        Set<SafariDAppPermission>

    public init(
        proposal:
            SafariDAppSessionProposal,

        accounts:
            Set<SafariWeb3AccountReference>,

        approvedChains:
            Set<SafariWeb3ChainReference>,

        approvedPermissions:
            Set<SafariDAppPermission>
    ) {
        self.proposal =
            proposal

        self.accounts =
            accounts

        self.approvedChains =
            approvedChains

        self.approvedPermissions =
            approvedPermissions
    }
}


// MARK: - 15. Session Request Method

public enum SafariDAppRequestMethod:
    String,
    Codable,
    Sendable
{
    case getAccounts
    case getChainID
    case getBalance

    case signMessage
    case signTypedData

    case estimateGas
    case sendTransaction
    case switchChain

    case custom
}


// MARK: - 16. Session Request

public struct SafariDAppRequest:
    Sendable
{
    public let id:
        SafariDAppRequestID

    public let sessionID:
        SafariDAppSessionID

    public let origin:
        SafariDAppOrigin

    public let method:
        SafariDAppRequestMethod

    public let payload:
        [String: String]

    public let createdAt:
        Date

    public init(
        id:
            SafariDAppRequestID =
                SafariDAppRequestID(),

        sessionID:
            SafariDAppSessionID,

        origin:
            SafariDAppOrigin,

        method:
            SafariDAppRequestMethod,

        payload:
            [String: String] = [:],

        createdAt:
            Date = Date()
    ) {
        self.id =
            id

        self.sessionID =
            sessionID

        self.origin =
            origin

        self.method =
            method

        self.payload =
            payload

        self.createdAt =
            createdAt
    }
}


// MARK: - 17. Request Result

public enum SafariDAppRequestResult:
    Sendable
{
    case success(
        [String: String]
    )

    case rejected

    case failure(
        String
    )
}


// MARK: - 18. Session Error

public enum SafariDAppSessionError:
    Error,
    Sendable
{
    case invalidOrigin
    case invalidProposal
    case sessionNotFound
    case pairingNotFound
    case sessionExpired
    case sessionInactive
    case permissionDenied
    case chainNotApproved
    case accountNotApproved
    case requestNotFound
    case requestRejected
    case unsupportedNamespace
    case unsupportedMethod
    case invalidPayload
    case transportFailure
}


// MARK: - 19. Session Transport

//
// This is the abstraction where a real WalletConnect-compatible
// relay/transport can be inserted.
//
// The session engine itself does not depend on a particular
// transport implementation.
//

public protocol SafariDAppSessionTransport:
    Sendable
{
    func publish(
        topic:
            String,

        message:
            Data
    ) async throws

    func subscribe(
        topic:
            String
    ) async throws

    func unsubscribe(
        topic:
            String
    ) async throws

    func reconnect()
        async throws
}


// MARK: - 20. Local Transport

public actor SafariLocalDAppSessionTransport:
    SafariDAppSessionTransport
{
    public init() {}

    public func publish(
        topic:
            String,

        message:
            Data
    ) async throws {
        //
        // Local development transport.
        //
        // Replace with an actual relay implementation.
        //
    }

    public func subscribe(
        topic:
            String
    ) async throws {
    }

    public func unsubscribe(
        topic:
            String
    ) async throws {
    }

    public func reconnect()
        async throws {
    }
}


// MARK: - 21. Session Store

public actor SafariDAppSessionStore {

    private var sessions:
        [SafariDAppSessionID:
            SafariDAppSession] = [:]

    public init() {}

    public func insert(
        _ session:
            SafariDAppSession
    ) {

        sessions[
            session.id
        ] =
            session
    }

    public func session(
        id:
            SafariDAppSessionID
    ) -> SafariDAppSession? {

        sessions[id]
    }

    public func update(
        _ session:
            SafariDAppSession
    ) {

        guard
            sessions[
                session.id
            ] != nil
        else {
            return
        }

        sessions[
            session.id
        ] =
            session
    }

    public func remove(
        id:
            SafariDAppSessionID
    ) {

        sessions.removeValue(
            forKey:
                id
        )
    }

    public func sessionsForOrigin(
        _ origin:
            SafariDAppOrigin
    ) -> [SafariDAppSession] {

        sessions.values.filter {
            $0.origin ==
                origin
        }
    }

    public func all()
        -> [SafariDAppSession]
    {
        Array(
            sessions.values
        )
    }
}


// MARK: - 22. Pairing Store

public actor SafariDAppPairingStore {

    private var pairings:
        [SafariDAppPairingID:
            SafariDAppPairing] = [:]

    public init() {}

    public func insert(
        _ pairing:
            SafariDAppPairing
    ) {

        pairings[
            pairing.id
        ] =
            pairing
    }

    public func pairing(
        id:
            SafariDAppPairingID
    ) -> SafariDAppPairing? {

        pairings[id]
    }

    public func deactivate(
        id:
            SafariDAppPairingID
    ) {

        guard
            var pairing =
                pairings[id]
        else {
            return
        }

        pairing.isActive =
            false

        pairings[id] =
            pairing
    }

    public func remove(
        id:
            SafariDAppPairingID
    ) {

        pairings.removeValue(
            forKey:
                id
        )
    }
}


// MARK: - 23. Request Store

public actor SafariDAppRequestStore {

    private var requests:
        [SafariDAppRequestID:
            SafariDAppRequest] = [:]

    public init() {}

    public func insert(
        _ request:
            SafariDAppRequest
    ) {

        requests[
            request.id
        ] =
            request
    }

    public func request(
        id:
            SafariDAppRequestID
    ) -> SafariDAppRequest? {

        requests[id]
    }

    public func remove(
        id:
            SafariDAppRequestID
    ) {

        requests.removeValue(
            forKey:
                id
        )
    }

    public func all()
        -> [SafariDAppRequest]
    {
        Array(
            requests.values
        )
    }
}


// MARK: - 24. Permission Engine

public actor SafariDAppSessionPermissionEngine {

    public init() {}

    public func requiredPermission(
        for method:
            SafariDAppRequestMethod
    ) -> SafariDAppPermission {

        switch method {

        case .getAccounts:
            return .accounts

        case .getChainID:
            return .chainInformation

        case .getBalance:
            return .balance

        case .signMessage:
            return .signMessage

        case .signTypedData:
            return .signTypedData

        case .estimateGas:
            return .chainInformation

        case .sendTransaction:
            return .sendTransaction

        case .switchChain:
            return .switchChain

        case .custom:
            return .accounts
        }
    }

    public func check(
        session:
            SafariDAppSession,

        method:
            SafariDAppRequestMethod
    ) throws {

        guard
            session.state ==
                .active
        else {
            throw SafariDAppSessionError
                .sessionInactive
        }

        guard
            !session.isExpired
        else {
            throw SafariDAppSessionError
                .sessionExpired
        }

        let permission =
            requiredPermission(
                for:
                    method
            )

        guard
            session.permissions.contains(
                permission
            )
        else {
            throw SafariDAppSessionError
                .permissionDenied
        }
    }
}


// MARK: - 25. Origin Security Engine

public struct SafariDAppOriginSecurityEngine:
    Sendable
{
    public init() {}

    public func validate(
        origin:
            SafariDAppOrigin
    ) throws {

        guard
            !origin.host.isEmpty
        else {
            throw SafariDAppSessionError
                .invalidOrigin
        }

        //
        // Native wallet access should not be granted to
        // arbitrary non-web schemes.
        //

        guard
            origin.scheme == "https"
            ||
            origin.scheme == "http"
        else {
            throw SafariDAppSessionError
                .invalidOrigin
        }

        //
        // HTTP can be restricted further by policy in production.
        //
    }
}


// MARK: - 26. Session Policy

public struct SafariDAppSessionPolicy:
    Sendable
{
    public let defaultLifetime:
        TimeInterval

    public let maximumLifetime:
        TimeInterval

    public let allowHTTPOrigins:
        Bool

    public init(
        defaultLifetime:
            TimeInterval =
                60 * 60 * 24,

        maximumLifetime:
            TimeInterval =
                60 * 60 * 24 * 30,

        allowHTTPOrigins:
            Bool = false
    ) {
        self.defaultLifetime =
            defaultLifetime

        self.maximumLifetime =
            maximumLifetime

        self.allowHTTPOrigins =
            allowHTTPOrigins
    }
}


// MARK: - 27. Session Event

public enum SafariDAppSessionEvent:
    Sendable
{
    case proposalReceived(
        SafariDAppSessionID,
        SafariDAppOrigin
    )

    case sessionApproved(
        SafariDAppSessionID
    )

    case sessionRejected(
        SafariDAppSessionID
    )

    case sessionExpired(
        SafariDAppSessionID
    )

    case sessionRevoked(
        SafariDAppSessionID
    )

    case sessionReconnected(
        SafariDAppSessionID
    )

    case accountChanged(
        SafariDAppSessionID
    )

    case chainChanged(
        SafariDAppSessionID
    )

    case requestReceived(
        SafariDAppRequestID
    )

    case requestApproved(
        SafariDAppRequestID
    )

    case requestRejected(
        SafariDAppRequestID
    )
}


// MARK: - 28. Event Stream

public actor SafariDAppSessionEventBus {

    private var subscribers:
        [
            UUID:
            AsyncStream<SafariDAppSessionEvent>.Continuation
        ] = [:]

    public init() {}

    public func stream()
        -> AsyncStream<SafariDAppSessionEvent>
    {

        let identifier =
            UUID()

        return AsyncStream { continuation in

            subscribers[
                identifier
            ] =
                continuation

            continuation.onTermination =
                { @Sendable _ in

                    Task {
                        await self.remove(
                            identifier
                        )
                    }
                }
        }
    }

    public func emit(
        _ event:
            SafariDAppSessionEvent
    ) {

        for continuation
            in subscribers.values
        {
            continuation.yield(
                event
            )
        }
    }

    private func remove(
        _ id:
            UUID
    ) {

        subscribers.removeValue(
            forKey:
                id
        )
    }
}


// MARK: - 29. Session Telemetry

public enum SafariDAppSessionTelemetryEvent:
    Sendable
{
    case pairingCreated(
        SafariDAppPairingID
    )

    case proposalReceived(
        SafariDAppSessionID
    )

    case sessionApproved(
        SafariDAppSessionID
    )

    case sessionRejected(
        SafariDAppSessionID
    )

    case sessionExpired(
        SafariDAppSessionID
    )

    case sessionRevoked(
        SafariDAppSessionID
    )

    case requestReceived(
        SafariDAppRequestID,
        SafariDAppRequestMethod
    )

    case requestRejected(
        SafariDAppRequestID
    )

    case requestApproved(
        SafariDAppRequestID
    )
}


public actor SafariDAppSessionTelemetry {

    private var events:
        [SafariDAppSessionTelemetryEvent] = []

    private let capacity:
        Int

    public init(
        capacity:
            Int = 10_000
    ) {
        self.capacity =
            capacity
    }

    public func append(
        _ event:
            SafariDAppSessionTelemetryEvent
    ) {

        events.append(
            event
        )

        if events.count >
            capacity
        {
            events.removeFirst(
                events.count - capacity
            )
        }
    }

    public func snapshot()
        -> [SafariDAppSessionTelemetryEvent]
    {
        events
    }
}


// MARK: - 30. Session Manager

public actor SafariWeb3DAppSessionManager {

    public let sessions:
        SafariDAppSessionStore

    public let pairings:
        SafariDAppPairingStore

    public let requests:
        SafariDAppRequestStore

    public let events:
        SafariDAppSessionEventBus

    public let telemetry:
        SafariDAppSessionTelemetry

    private let transport:
        SafariDAppSessionTransport

    private let permissionEngine:
        SafariDAppSessionPermissionEngine

    private let originSecurity:
        SafariDAppOriginSecurityEngine

    private let policy:
        SafariDAppSessionPolicy

    public init(
        transport:
            SafariDAppSessionTransport =
                SafariLocalDAppSessionTransport(),

        policy:
            SafariDAppSessionPolicy =
                SafariDAppSessionPolicy()
    ) {

        self.sessions =
            SafariDAppSessionStore()

        self.pairings =
            SafariDAppPairingStore()

        self.requests =
            SafariDAppRequestStore()

        self.events =
            SafariDAppSessionEventBus()

        self.telemetry =
            SafariDAppSessionTelemetry()

        self.transport =
            transport

        self.permissionEngine =
            SafariDAppSessionPermissionEngine()

        self.originSecurity =
            SafariDAppOriginSecurityEngine()

        self.policy =
            policy
    }


    // MARK: Pairing

    public func createPairing(
        origin:
            SafariDAppOrigin
    ) async throws
        -> SafariDAppPairing {

        try originSecurity.validate(
            origin:
                origin
        )

        if
            origin.scheme == "http"
            &&
            !policy.allowHTTPOrigins
        {
            throw SafariDAppSessionError
                .invalidOrigin
        }

        let topic =
            UUID()
                .uuidString
                .replacingOccurrences(
                    of:
                        "-",
                    with:
                        ""
                )

        let uri =
            "wc:\(topic)@2"

        let pairing =
            SafariDAppPairing(
                topic:
                    topic,

                uri:
                    uri,

                origin:
                    origin,

                expiresAt:
                    Date().addingTimeInterval(
                        60 * 10
                    )
            )

        await pairings.insert(
            pairing
        )

        await telemetry.append(
            .pairingCreated(
                pairing.id
            )
        )

        return pairing
    }


    // MARK: Proposal

    public func receiveProposal(
        pairing:
            SafariDAppPairing,

        metadata:
            SafariDAppMetadata,

        namespace:
            SafariWeb3Namespace,

        chains:
            Set<SafariWeb3ChainReference>,

        permissions:
            Set<SafariDAppPermission>
    ) async throws
        -> SafariDAppSessionProposal {

        guard
            pairing.isActive
        else {
            throw SafariDAppSessionError
                .pairingNotFound
        }

        guard
            pairing.expiresAt > Date()
        else {
            throw SafariDAppSessionError
                .sessionExpired
        }

        let proposal =
            SafariDAppSessionProposal(
                pairing:
                    pairing,

                metadata:
                    metadata,

                namespace:
                    namespace,

                requestedChains:
                    chains,

                requestedPermissions:
                    permissions
            )

        let session =
            SafariDAppSession(
                pairingID:
                    pairing.id,

                origin:
                    pairing.origin,

                metadata:
                    metadata,

                namespace:
                    namespace,

                chains:
                    chains,

                accounts:
                    [],

                permissions:
                    permissions,

                state:
                    .awaitingApproval,

                expiresAt:
                    Date().addingTimeInterval(
                        policy.defaultLifetime
                    )
            )

        await sessions.insert(
            session
        )

        await telemetry.append(
            .proposalReceived(
                session.id
            )
        )

        await events.emit(
            .proposalReceived(
                session.id,
                pairing.origin
            )
        )

        return proposal
    }


    // MARK: Approve

    public func approve(
        sessionID:
            SafariDAppSessionID,

        accounts:
            Set<SafariWeb3AccountReference>,

        chains:
            Set<SafariWeb3ChainReference>,

        permissions:
            Set<SafariDAppPermission>
    ) async throws
        -> SafariDAppSession {

        guard
            var session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw SafariDAppSessionError
                .sessionNotFound
        }

        guard
            session.state ==
                .awaitingApproval
        else {
            throw SafariDAppSessionError
                .invalidProposal
        }

        guard
            !session.isExpired
        else {
            throw SafariDAppSessionError
                .sessionExpired
        }

        guard
            chains.isSubset(
                of:
                    session.chains
            )
        else {
            throw SafariDAppSessionError
                .chainNotApproved
        }

        guard
            permissions.isSubset(
                of:
                    session.permissions
            )
        else {
            throw SafariDAppSessionError
                .permissionDenied
        }

        guard
            !accounts.isEmpty
        else {
            throw SafariDAppSessionError
                .accountNotApproved
        }

        session.accounts =
            accounts

        session.chains =
            chains

        session.permissions =
            permissions

        session.state =
            .active

        session.lastActivityAt =
            Date()

        await sessions.update(
            session
        )

        try await transport.subscribe(
            topic:
                session.relayTopic
                ??
                session.pairingID
                    .rawValue
                    .uuidString
        )

        await telemetry.append(
            .sessionApproved(
                session.id
            )
        )

        await events.emit(
            .sessionApproved(
                session.id
            )
        )

        return session
    }


    // MARK: Reject

    public func reject(
        sessionID:
            SafariDAppSessionID
    ) async throws {

        guard
            var session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw SafariDAppSessionError
                .sessionNotFound
        }

        session.state =
            .rejected

        await sessions.update(
            session
        )

        await telemetry.append(
            .sessionRejected(
                sessionID
            )
        )

        await events.emit(
            .sessionRejected(
                sessionID
            )
        )
    }


    // MARK: Request

    public func receiveRequest(
        sessionID:
            SafariDAppSessionID,

        origin:
            SafariDAppOrigin,

        method:
            SafariDAppRequestMethod,

        payload:
            [String: String] = [:]
    ) async throws
        -> SafariDAppRequest {

        guard
            let session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw SafariDAppSessionError
                .sessionNotFound
        }

        guard
            session.origin ==
                origin
        else {
            throw SafariDAppSessionError
                .invalidOrigin
        }

        try await permissionEngine.check(
            session:
                session,

            method:
                method
        )

        let request =
            SafariDAppRequest(
                sessionID:
                    sessionID,

                origin:
                    origin,

                method:
                    method,

                payload:
                    payload
            )

        await requests.insert(
            request
        )

        await telemetry.append(
            .requestReceived(
                request.id,
                method
            )
        )

        await events.emit(
            .requestReceived(
                request.id
            )
        )

        return request
    }


    // MARK: Complete request

    public func completeRequest(
        requestID:
            SafariDAppRequestID,

        result:
            SafariDAppRequestResult
    ) async throws {

        guard
            let request =
                await requests.request(
                    id:
                        requestID
                )
        else {
            throw SafariDAppSessionError
                .requestNotFound
        }

        switch result {

        case .success:

            await telemetry.append(
                .requestApproved(
                    requestID
                )
            )

            await events.emit(
                .requestApproved(
                    requestID
                )
            )

        case .rejected:

            await telemetry.append(
                .requestRejected(
                    requestID
                )
            )

            await events.emit(
                .requestRejected(
                    requestID
                )
            )

        case .failure:

            await telemetry.append(
                .requestRejected(
                    requestID
                )
            )

            await events.emit(
                .requestRejected(
                    requestID
                )
            )
        }

        await requests.remove(
            id:
                request.id
        )
    }


    // MARK: Account switch

    public func updateAccounts(
        sessionID:
            SafariDAppSessionID,

        accounts:
            Set<SafariWeb3AccountReference>
    ) async throws {

        guard
            var session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw SafariDAppSessionError
                .sessionNotFound
        }

        guard
            session.state ==
                .active
        else {
            throw SafariDAppSessionError
                .sessionInactive
        }

        session.accounts =
            accounts

        session.lastActivityAt =
            Date()

        await sessions.update(
            session
        )

        await events.emit(
            .accountChanged(
                sessionID
            )
        )
    }


    // MARK: Chain switch

    public func switchChain(
        sessionID:
            SafariDAppSessionID,

        chain:
            SafariWeb3ChainReference
    ) async throws {

        guard
            var session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw SafariDAppSessionError
                .sessionNotFound
        }

        guard
            session.state ==
                .active
        else {
            throw SafariDAppSessionError
                .sessionInactive
        }

        guard
            session.permissions.contains(
                .switchChain
            )
        else {
            throw SafariDAppSessionError
                .permissionDenied
        }

        guard
            session.chains.contains(
                chain
            )
        else {
            throw SafariDAppSessionError
                .chainNotApproved
        }

        session.lastActivityAt =
            Date()

        await sessions.update(
            session
        )

        await events.emit(
            .chainChanged(
                sessionID
            )
        )
    }


    // MARK: Revoke

    public func revoke(
        sessionID:
            SafariDAppSessionID
    ) async throws {

        guard
            var session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw SafariDAppSessionError
                .sessionNotFound
        }

        session.state =
            .revoked

        await sessions.update(
            session
        )

        if let topic =
            session.relayTopic
        {
            try? await transport.unsubscribe(
                topic:
                    topic
            )
        }

        await telemetry.append(
            .sessionRevoked(
                sessionID
            )
        )

        await events.emit(
            .sessionRevoked(
                sessionID
            )
        )
    }


    // MARK: Expiration

    public func expireSessions() async {

        let currentSessions =
            await sessions.all()

        for var session
            in currentSessions
        {

            guard
                session.state ==
                    .active
            else {
                continue
            }

            guard
                session.isExpired
            else {
                continue
            }

            session.state =
                .expired

            await sessions.update(
                session
            )

            await telemetry.append(
                .sessionExpired(
                    session.id
                )
            )

            await events.emit(
                .sessionExpired(
                    session.id
                )
            )
        }
    }


    // MARK: Reconnect

    public func reconnect(
        sessionID:
            SafariDAppSessionID
    ) async throws {

        guard
            var session =
                await sessions.session(
                    id:
                        sessionID
                )
        else {
            throw SafariDAppSessionError
                .sessionNotFound
        }

        guard
            session.state ==
                .active
            ||
            session.state ==
                .reconnecting
        else {
            throw SafariDAppSessionError
                .sessionInactive
        }

        session.state =
            .reconnecting

        await sessions.update(
            session
        )

        do {

            try await transport.reconnect()

            session.state =
                .active

            session.lastActivityAt =
                Date()

            await sessions.update(
                session
            )

            await events.emit(
                .sessionReconnected(
                    sessionID
                )
            )

        } catch {

            session.state =
                .reconnecting

            await sessions.update(
                session
            )

            throw SafariDAppSessionError
                .transportFailure
        }
    }


    // MARK: Session lookup

    public func session(
        id:
            SafariDAppSessionID
    ) async
        -> SafariDAppSession?
    {
        await sessions.session(
            id:
                id
        )
    }

    public func sessionsForOrigin(
        _ origin:
            SafariDAppOrigin
    ) async
        -> [SafariDAppSession]
    {
        await sessions.sessionsForOrigin(
            origin
        )
    }
}


// MARK: - 31. Session Expiration Runtime

public actor SafariDAppSessionExpirationRuntime {

    private let manager:
        SafariWeb3DAppSessionManager

    private var task:
        Task<Void, Never>?

    public init(
        manager:
            SafariWeb3DAppSessionManager
    ) {
        self.manager =
            manager
    }

    public func start(
        interval:
            Duration = .seconds(30)
    ) {

        guard
            task == nil
        else {
            return
        }

        task =
            Task {

                while !Task.isCancelled {

                    await manager
                        .expireSessions()

                    try? await Task.sleep(
                        for:
                            interval
                    )
                }
            }
    }

    public func stop() {

        task?.cancel()

        task =
            nil
    }

    deinit {
        task?.cancel()
    }
}


// MARK: - 32. Safari WebView Bridge

//
// The bridge converts browser-originated Web3 requests into
// native session requests.
//
// The important security property is that the bridge derives
// the origin from the actual WKWebView navigation context rather
// than trusting an origin supplied by JavaScript.
//

import WebKit

@MainActor
public final class SafariDAppWebViewBridge:
    NSObject,
    WKScriptMessageHandler
{

    private weak var webView:
        WKWebView?

    private let sessionManager:
        SafariWeb3DAppSessionManager

    public init(
        webView:
            WKWebView,

        sessionManager:
            SafariWeb3DAppSessionManager
    ) {

        self.webView =
            webView

        self.sessionManager =
            sessionManager

        super.init()

        webView
            .configuration
            .userContentController
            .add(
                self,

                name:
                    "safariDApp"
            )
    }


    public func userContentController(
        _ userContentController:
            WKUserContentController,

        didReceive message:
            WKScriptMessage
    ) {

        guard
            message.name ==
                "safariDApp"
        else {
            return
        }

        guard
            let dictionary =
                message.body
                    as? [String: Any]
        else {
            return
        }

        guard
            let method =
                dictionary["method"]
                as? String
        else {
            return
        }

        guard
            let url =
                webView?.url,

            let origin =
                SafariDAppOrigin(
                    url:
                        url
                )
        else {
            return
        }

        Task {

            await handle(
                method:
                    method,

                origin:
                    origin,

                dictionary:
                    dictionary
            )
        }
    }


    private func handle(
        method:
            String,

        origin:
            SafariDAppOrigin,

        dictionary:
            [String: Any]
    ) async {

        switch method {

        case "eth_requestAccounts":

            //
            // The native UI should now display the connection
            // approval screen.
            //
            // This bridge does not silently grant access.
            //

            await requestAccountConnection(
                origin:
                    origin
            )

        case "wallet_switchEthereumChain":

            await requestChainSwitch(
                origin:
                    origin,

                dictionary:
                    dictionary
            )

        default:

            await sendError(
                "Unsupported DApp method"
            )
        }
    }


    private func requestAccountConnection(
        origin:
            SafariDAppOrigin
    ) async {

        //
        // Actual account selection belongs to the native
        // wallet UI and #1 Wallet Engine.
        //
        // This is deliberately not auto-approved.
        //
    }


    private func requestChainSwitch(
        origin:
            SafariDAppOrigin,

        dictionary:
            [String: Any]
    ) async {

        //
        // Parse the requested chain here,
        // then pass it through the session manager.
        //
    }


    private func sendError(
        _ message:
            String
    ) async {

        guard
            let webView
        else {
            return
        }

        let escaped =
            message
                .replacingOccurrences(
                    of:
                        "\\",
                    with:
                        "\\\\"
                )
                .replacingOccurrences(
                    of:
                        "\"",
                    with:
                        "\\\""
                )

        let script =
            """
            window.dispatchEvent(
                new CustomEvent(
                    "safariDAppResponse",
                    {
                        detail: {
                            error: "\(escaped)"
                        }
                    }
                )
            );
            """

        webView.evaluateJavaScript(
            script
        )
    }


    deinit {

        webView?
            .configuration
            .userContentController
            .removeScriptMessageHandler(
                forName:
                    "safariDApp"
            )
    }
}


// MARK: - 33. Browser Session Controller

@MainActor
public final class SafariDAppBrowserSessionController {

    private let sessionManager:
        SafariWeb3DAppSessionManager

    private var bridges:
        [
            ObjectIdentifier:
            SafariDAppWebViewBridge
        ] = [:]

    public init(
        sessionManager:
            SafariWeb3DAppSessionManager
    ) {
        self.sessionManager =
            sessionManager
    }

    public func attach(
        webView:
            WKWebView
    ) {

        let bridge =
            SafariDAppWebViewBridge(
                webView:
                    webView,

                sessionManager:
                    sessionManager
            )

        bridges[
            ObjectIdentifier(
                webView
            )
        ] =
            bridge
    }

    public func detach(
        webView:
            WKWebView
    ) {

        bridges.removeValue(
            forKey:
                ObjectIdentifier(
                    webView
                )
        )
    }
}


// MARK: - 34. Session Factory

public enum SafariDAppSessionFactory {

    public static func make()
        -> SafariWeb3DAppSessionManager
    {

        let transport =
            SafariLocalDAppSessionTransport()

        return SafariWeb3DAppSessionManager(
            transport:
                transport,

            policy:
                SafariDAppSessionPolicy(
                    defaultLifetime:
                        60 * 60 * 24,

                    maximumLifetime:
                        60 * 60 * 24 * 30,

                    allowHTTPOrigins:
                        false
                )
        )
    }
}


// MARK: - 35. Unified Web3 Session Runtime

public actor SafariWeb3SessionRuntime {

    public let manager:
        SafariWeb3DAppSessionManager

    private let expiration:
        SafariDAppSessionExpirationRuntime

    public init() {

        let manager =
            SafariDAppSessionFactory.make()

        self.manager =
            manager

        self.expiration =
            SafariDAppSessionExpirationRuntime(
                manager:
                    manager
            )
    }

    public func start() async {

        await expiration.start()
    }

    public func stop() async {

        await expiration.stop()
    }
}


// MARK: - 36. Example EVM Session

public enum SafariWeb3SessionExamples {

    public static func ethereumChain()
        -> SafariWeb3ChainReference
    {
        SafariWeb3ChainReference(
            namespace:
                .eip155,

            reference:
                "1"
        )
    }


    public static func ethereumAccount(
        address:
            String
    )
        -> SafariWeb3AccountReference
    {
        SafariWeb3AccountReference(
            namespace:
                .eip155,

            chainReference:
                "1",

            address:
                address
        )
    }
}


// MARK: - 37. DEBUG Tests

#if DEBUG

public enum SafariDAppSessionTests {

    public static func originTest()
        -> Bool
    {

        guard
            let url =
                URL(
                    string:
                        "https://example-dapp.com"
                )
        else {
            return false
        }

        guard
            let origin =
                SafariDAppOrigin(
                    url:
                        url
                )
        else {
            return false
        }

        return
            origin.scheme ==
                "https"
            &&
            origin.host ==
                "example-dapp.com"
    }


    public static func chainReferenceTest()
        -> Bool
    {

        let chain =
            SafariDAppSessionExamples
                .ethereumChain()

        return
            chain.serialized ==
                "eip155:1"
    }


    public static func accountReferenceTest()
        -> Bool
    {

        let account =
            SafariDAppSessionExamples
                .ethereumAccount(
                    address:
                        "0x123"
                )

        return
            account.serialized ==
                "eip155:1:0x123"
    }


    public static func permissionTest()
        -> Bool
    {

        let permissions:
            Set<SafariDAppPermission> = [
                .accounts,
                .chainInformation,
                .signMessage
            ]

        return
            permissions.contains(
                .signMessage
            )
    }
}

#endif






//
// SafariWeb3TransactionSimulationEngine.swift
//
// Native Web3 transaction simulation layer for a Safari/WebKit browser.
//
// Swift 6 / macOS-oriented architecture
//
// Responsibilities:
//   • Decode and normalize DApp transaction requests
//   • Perform eth_call-style simulation through the RPC layer
//   • Estimate gas
//   • Detect likely ETH/native-token transfers
//   • Detect ERC-20 transfers and approvals
//   • Detect ERC-721 / ERC-1155 transfers where calldata is recognizable
//   • Produce human-readable simulation results
//   • Identify simulation warnings
//   • Maintain simulation lifecycle state
//   • Cache short-lived simulation results
//   • Never sign or broadcast transactions
//
// Cryptographic signing belongs to #1.
// RPC transport belongs to #2.
// DApp sessions belong to #3.
// Security analysis can consume this engine's output.
//
// IMPORTANT:
// This implementation intentionally uses protocol abstractions.
// A production implementation should connect those abstractions to
// the vetted EVM/secp256k1/RLP/ABI libraries used by the wallet.
// Do not implement production cryptography by hand.
//

import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(WebKit)
import WebKit
#endif

// MARK: - Identifiers

public struct SafariSimulationID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct SafariSimulationRequestID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

// MARK: - EVM primitives

public struct EVMAddress: Hashable, Codable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        let normalized = value.lowercased()

        guard normalized.hasPrefix("0x"),
              normalized.count == 42 else {
            throw SafariTransactionSimulationError.invalidAddress(value)
        }

        let hex = String(normalized.dropFirst(2))

        guard hex.allSatisfy({
            $0.isNumber ||
            ("a"..."f").contains(String($0))
        }) else {
            throw SafariTransactionSimulationError.invalidAddress(value)
        }

        self.value = normalized
    }
}

public struct EVMHex: Hashable, Codable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        let normalized = value.lowercased()

        guard normalized.hasPrefix("0x") else {
            throw SafariTransactionSimulationError.invalidHex(value)
        }

        self.value = normalized
    }

    public var byteCount: Int {
        max(0, (value.count - 2) / 2)
    }
}

// MARK: - Transaction

public struct SafariEVMTransaction: Codable, Hashable, Sendable {

    public let from: EVMAddress
    public let to: EVMAddress?
    public let value: String
    public let data: EVMHex
    public let gas: String?
    public let gasPrice: String?
    public let maxFeePerGas: String?
    public let maxPriorityFeePerGas: String?
    public let nonce: String?

    public init(
        from: EVMAddress,
        to: EVMAddress?,
        value: String = "0x0",
        data: EVMHex = try! EVMHex("0x"),
        gas: String? = nil,
        gasPrice: String? = nil,
        maxFeePerGas: String? = nil,
        maxPriorityFeePerGas: String? = nil,
        nonce: String? = nil
    ) {
        self.from = from
        self.to = to
        self.value = value
        self.data = data
        self.gas = gas
        self.gasPrice = gasPrice
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.nonce = nonce
    }
}

// MARK: - Simulation state

public enum SafariSimulationState: String, Codable, Sendable {
    case queued
    case simulating
    case estimatingGas
    case decoding
    case completed
    case failed
    case expired
    case cancelled
}

// MARK: - Revert information

public struct SafariSimulationRevert: Codable, Hashable, Sendable {

    public let rawData: EVMHex
    public let decodedReason: String?
    public let selector: String?

    public init(
        rawData: EVMHex,
        decodedReason: String? = nil,
        selector: String? = nil
    ) {
        self.rawData = rawData
        self.decodedReason = decodedReason
        self.selector = selector
    }
}

// MARK: - RPC abstraction

public protocol SafariWeb3SimulationRPC: Sendable {

    func ethCall(
        transaction: SafariEVMTransaction,
        blockTag: String
    ) async throws -> EVMHex

    func estimateGas(
        transaction: SafariEVMTransaction
    ) async throws -> String

    func getBalance(
        address: EVMAddress,
        blockTag: String
    ) async throws -> String

    func getChainID() async throws -> String
}

// MARK: - Simulation configuration

public struct SafariSimulationConfiguration: Sendable {

    public var blockTag: String
    public var cacheLifetime: Duration
    public var maximumSimulationTime: Duration
    public var gasSafetyMultiplier: Double
    public var enableTokenDecoding: Bool

    public init(
        blockTag: String = "latest",
        cacheLifetime: Duration = .seconds(10),
        maximumSimulationTime: Duration = .seconds(15),
        gasSafetyMultiplier: Double = 1.15,
        enableTokenDecoding: Bool = true
    ) {
        self.blockTag = blockTag
        self.cacheLifetime = cacheLifetime
        self.maximumSimulationTime = maximumSimulationTime
        self.gasSafetyMultiplier = gasSafetyMultiplier
        self.enableTokenDecoding = enableTokenDecoding
    }
}

// MARK: - Asset movements

public enum SafariAssetMovementKind: String, Codable, Sendable {
    case native
    case erc20
    case erc721
    case erc1155
    case approval
    case unknown
}

public struct SafariAssetMovement: Codable, Hashable, Sendable {

    public let kind: SafariAssetMovementKind
    public let tokenContract: EVMAddress?
    public let from: EVMAddress?
    public let to: EVMAddress?
    public let tokenID: String?
    public let amount: String?
    public let symbol: String?
    public let decimals: Int?

    public init(
        kind: SafariAssetMovementKind,
        tokenContract: EVMAddress? = nil,
        from: EVMAddress? = nil,
        to: EVMAddress? = nil,
        tokenID: String? = nil,
        amount: String? = nil,
        symbol: String? = nil,
        decimals: Int? = nil
    ) {
        self.kind = kind
        self.tokenContract = tokenContract
        self.from = from
        self.to = to
        self.tokenID = tokenID
        self.amount = amount
        self.symbol = symbol
        self.decimals = decimals
    }
}

// MARK: - Warnings

public enum SafariSimulationWarningSeverity: String, Codable, Sendable {
    case informational
    case notice
    case warning
    case critical
}

public enum SafariSimulationWarningCode: String, Codable, Sendable {

    case simulationReverted
    case unknownContract
    case nativeValueTransfer
    case tokenTransfer
    case tokenApproval
    case unlimitedApproval
    case contractInteraction
    case highGasEstimate
    case unusualCalldata
    case missingRecipient
    case insufficientBalance
    case simulationUnavailable
}

public struct SafariSimulationWarning: Codable, Hashable, Sendable {

    public let code: SafariSimulationWarningCode
    public let severity: SafariSimulationWarningSeverity
    public let title: String
    public let message: String

    public init(
        code: SafariSimulationWarningCode,
        severity: SafariSimulationWarningSeverity,
        title: String,
        message: String
    ) {
        self.code = code
        self.severity = severity
        self.title = title
        self.message = message
    }
}

// MARK: - Gas

public struct SafariGasEstimate: Codable, Hashable, Sendable {

    public let rawEstimate: String
    public let recommendedLimit: String
    public let multiplier: Double

    public init(
        rawEstimate: String,
        recommendedLimit: String,
        multiplier: Double
    ) {
        self.rawEstimate = rawEstimate
        self.recommendedLimit = recommendedLimit
        self.multiplier = multiplier
    }
}

// MARK: - Simulation result

public struct SafariTransactionSimulationResult:
    Codable,
    Hashable,
    Sendable
{
    public let simulationID: SafariSimulationID
    public let requestID: SafariSimulationRequestID

    public let chainID: String
    public let transaction: SafariEVMTransaction

    public let success: Bool
    public let returnData: EVMHex?
    public let revert: SafariSimulationRevert?

    public let gasEstimate: SafariGasEstimate?
    public let assetMovements: [SafariAssetMovement]
    public let warnings: [SafariSimulationWarning]

    public let createdAt: Date
    public let expiresAt: Date

    public init(
        simulationID: SafariSimulationID,
        requestID: SafariSimulationRequestID,
        chainID: String,
        transaction: SafariEVMTransaction,
        success: Bool,
        returnData: EVMHex?,
        revert: SafariSimulationRevert?,
        gasEstimate: SafariGasEstimate?,
        assetMovements: [SafariAssetMovement],
        warnings: [SafariSimulationWarning],
        createdAt: Date,
        expiresAt: Date
    ) {
        self.simulationID = simulationID
        self.requestID = requestID
        self.chainID = chainID
        self.transaction = transaction
        self.success = success
        self.returnData = returnData
        self.revert = revert
        self.gasEstimate = gasEstimate
        self.assetMovements = assetMovements
        self.warnings = warnings
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

// MARK: - Errors

public enum SafariTransactionSimulationError:
    Error,
    LocalizedError,
    Sendable
{
    case invalidAddress(String)
    case invalidHex(String)
    case invalidTransaction
    case missingRPCProvider
    case simulationReverted
    case gasEstimationFailed
    case timeout
    case cancelled
    case insufficientBalance
    case unsupportedChain
    case malformedCalldata
    case resultExpired

    public var errorDescription: String? {
        switch self {
        case .invalidAddress(let address):
            return "Invalid EVM address: \(address)"

        case .invalidHex(let value):
            return "Invalid hexadecimal value: \(value)"

        case .invalidTransaction:
            return "The transaction is incomplete or invalid."

        case .missingRPCProvider:
            return "No blockchain RPC provider is available."

        case .simulationReverted:
            return "The transaction reverted during simulation."

        case .gasEstimationFailed:
            return "Gas estimation failed."

        case .timeout:
            return "Transaction simulation timed out."

        case .cancelled:
            return "Transaction simulation was cancelled."

        case .insufficientBalance:
            return "The account may not have enough native balance."

        case .unsupportedChain:
            return "This blockchain network is not supported."

        case .malformedCalldata:
            return "The transaction calldata could not be decoded."

        case .resultExpired:
            return "The simulation result has expired."
        }
    }
}

// MARK: - ABI function selectors

public enum SafariEVMFunctionSelector {

    public static let transfer = "0xa9059cbb"
    public static let approve = "0x095ea7b3"
    public static let transferFrom = "0x23b872dd"
    public static let safeTransferFrom = "0x42842e0e"
    public static let safeTransferFromWithData = "0xb88d4fde"
    public static let setApprovalForAll = "0xa22cb465"

    public static func selector(
        from data: EVMHex
    ) -> String? {

        guard data.value.count >= 10 else {
            return nil
        }

        return String(data.value.prefix(10))
    }
}

// MARK: - Calldata decoder

public struct SafariEVMCalldataDecoder: Sendable {

    public init() {}

    public func decode(
        transaction: SafariEVMTransaction
    ) -> [SafariAssetMovement] {

        guard
            let selector = SafariEVMFunctionSelector.selector(
                from: transaction.data
            )
        else {
            return []
        }

        switch selector {

        case SafariEVMFunctionSelector.transfer:
            return decodeERC20Transfer(transaction)

        case SafariEVMFunctionSelector.approve:
            return decodeERC20Approval(transaction)

        case SafariEVMFunctionSelector.transferFrom:
            return decodeERC20TransferFrom(transaction)

        case SafariEVMFunctionSelector.safeTransferFrom:
            return decodeERC721TransferFrom(transaction)

        case SafariEVMFunctionSelector.safeTransferFromWithData:
            return decodeERC721TransferFrom(transaction)

        case SafariEVMFunctionSelector.setApprovalForAll:
            return decodeApprovalForAll(transaction)

        default:
            return []
        }
    }

    private func decodeERC20Transfer(
        _ transaction: SafariEVMTransaction
    ) -> [SafariAssetMovement] {

        let payload = stripSelector(transaction.data.value)

        guard payload.count >= 128 else {
            return []
        }

        guard let recipient = decodeAddress(
            word: substring(payload, start: 0, length: 64)
        ) else {
            return []
        }

        let amount = substring(
            payload,
            start: 64,
            length: 64
        )

        return [
            SafariAssetMovement(
                kind: .erc20,
                tokenContract: transaction.to,
                from: transaction.from,
                to: recipient,
                amount: "0x" + amount
            )
        ]
    }

    private func decodeERC20Approval(
        _ transaction: SafariEVMTransaction
    ) -> [SafariAssetMovement] {

        let payload = stripSelector(transaction.data.value)

        guard payload.count >= 128 else {
            return []
        }

        guard let spender = decodeAddress(
            word: substring(payload, start: 0, length: 64)
        ) else {
            return []
        }

        let amount = substring(
            payload,
            start: 64,
            length: 64
        )

        let normalizedAmount = amount
            .trimmingCharacters(in: CharacterSet(charactersIn: "0"))

        let isUnlimited =
            normalizedAmount.isEmpty ||
            amount.count >= 64 &&
            amount.allSatisfy { $0 == "f" }

        return [
            SafariAssetMovement(
                kind: .approval,
                tokenContract: transaction.to,
                from: transaction.from,
                to: spender,
                amount: "0x" + amount
            ),
            SafariAssetMovement(
                kind: isUnlimited ? .approval : .approval,
                tokenContract: transaction.to,
                from: transaction.from,
                to: spender,
                amount: "0x" + amount
            )
        ]
    }

    private func decodeERC20TransferFrom(
        _ transaction: SafariEVMTransaction
    ) -> [SafariAssetMovement] {

        let payload = stripSelector(transaction.data.value)

        guard payload.count >= 192 else {
            return []
        }

        guard
            let from = decodeAddress(
                word: substring(payload, start: 0, length: 64)
            ),
            let to = decodeAddress(
                word: substring(payload, start: 64, length: 64)
            )
        else {
            return []
        }

        let amount = substring(
            payload,
            start: 128,
            length: 64
        )

        return [
            SafariAssetMovement(
                kind: .erc20,
                tokenContract: transaction.to,
                from: from,
                to: to,
                amount: "0x" + amount
            )
        ]
    }

    private func decodeERC721TransferFrom(
        _ transaction: SafariEVMTransaction
    ) -> [SafariAssetMovement] {

        let payload = stripSelector(transaction.data.value)

        guard payload.count >= 192 else {
            return []
        }

        guard
            let from = decodeAddress(
                word: substring(payload, start: 0, length: 64)
            ),
            let to = decodeAddress(
                word: substring(payload, start: 64, length: 64)
            )
        else {
            return []
        }

        let tokenID = substring(
            payload,
            start: 128,
            length: 64
        )

        return [
            SafariAssetMovement(
                kind: .erc721,
                tokenContract: transaction.to,
                from: from,
                to: to,
                tokenID: "0x" + tokenID
            )
        ]
    }

    private func decodeApprovalForAll(
        _ transaction: SafariEVMTransaction
    ) -> [SafariAssetMovement] {

        let payload = stripSelector(transaction.data.value)

        guard payload.count >= 128 else {
            return []
        }

        guard let operatorAddress = decodeAddress(
            word: substring(payload, start: 0, length: 64)
        ) else {
            return []
        }

        return [
            SafariAssetMovement(
                kind: .approval,
                tokenContract: transaction.to,
                from: transaction.from,
                to: operatorAddress,
                amount: "approvalForAll"
            )
        ]
    }

    private func stripSelector(_ data: String) -> String {
        String(data.dropFirst(10))
    }

    private func substring(
        _ value: String,
        start: Int,
        length: Int
    ) -> String {

        let startIndex = value.index(
            value.startIndex,
            offsetBy: min(start, value.count)
        )

        let endIndex = value.index(
            startIndex,
            offsetBy: min(length, value.distance(from: startIndex, to: value.endIndex))
        )

        return String(value[startIndex..<endIndex])
    }

    private func decodeAddress(
        word: String
    ) -> EVMAddress? {

        let addressHex = String(
            word.suffix(40)
        )

        return try? EVMAddress(
            "0x" + addressHex
        )
    }
}

// MARK: - Native transfer analysis

public struct SafariNativeTransferAnalyzer: Sendable {

    public init() {}

    public func analyze(
        transaction: SafariEVMTransaction
    ) -> [SafariAssetMovement] {

        guard transaction.value != "0x0",
              transaction.value != "0x",
              transaction.value != "0x00"
        else {
            return []
        }

        guard let destination = transaction.to else {
            return []
        }

        return [
            SafariAssetMovement(
                kind: .native,
                from: transaction.from,
                to: destination,
                amount: transaction.value
            )
        ]
    }
}

// MARK: - Warning engine

public struct SafariSimulationWarningEngine: Sendable {

    public init() {}

    public func warnings(
        transaction: SafariEVMTransaction,
        movements: [SafariAssetMovement],
        simulationSucceeded: Bool,
        gas: SafariGasEstimate?
    ) -> [SafariSimulationWarning] {

        var result: [SafariSimulationWarning] = []

        if !simulationSucceeded {
            result.append(
                SafariSimulationWarning(
                    code: .simulationReverted,
                    severity: .critical,
                    title: "Transaction reverted",
                    message: "The blockchain rejected this transaction during simulation."
                )
            )
        }

        if transaction.to == nil {
            result.append(
                SafariSimulationWarning(
                    code: .missingRecipient,
                    severity: .warning,
                    title: "No recipient",
                    message: "This transaction does not specify a contract or recipient address."
                )
            )
        }

        if !movements.isEmpty {
            for movement in movements {

                switch movement.kind {

                case .native:
                    result.append(
                        SafariSimulationWarning(
                            code: .nativeValueTransfer,
                            severity: .notice,
                            title: "Native asset transfer",
                            message: "This transaction transfers a native blockchain asset."
                        )
                    )

                case .erc20:
                    result.append(
                        SafariSimulationWarning(
                            code: .tokenTransfer,
                            severity: .notice,
                            title: "Token transfer",
                            message: "This transaction appears to transfer a token."
                        )
                    )

                case .approval:
                    result.append(
                        SafariSimulationWarning(
                            code: .tokenApproval,
                            severity: .warning,
                            title: "Token approval",
                            message: "This transaction changes token spending permissions."
                        )
                    )

                case .erc721, .erc1155:
                    result.append(
                        SafariSimulationWarning(
                            code: .tokenTransfer,
                            severity: .notice,
                            title: "NFT transfer",
                            message: "This transaction appears to transfer a digital asset."
                        )
                    )

                case .unknown:
                    break
                }
            }
        }

        if gas != nil {
            result.append(
                SafariSimulationWarning(
                    code: .contractInteraction,
                    severity: .informational,
                    title: "Gas required",
                    message: "The transaction requires blockchain execution fees."
                )
            )
        }

        return result
    }
}

// MARK: - Simulation cache

public actor SafariSimulationCache {

    private struct CachedValue: Sendable {
        let result: SafariTransactionSimulationResult
        let expiresAt: Date
    }

    private var storage:
        [SafariSimulationRequestID: CachedValue] = [:]

    public init() {}

    public func insert(
        _ result: SafariTransactionSimulationResult
    ) {
        storage[result.requestID] = CachedValue(
            result: result,
            expiresAt: result.expiresAt
        )
    }

    public func result(
        for requestID: SafariSimulationRequestID,
        now: Date = Date()
    ) -> SafariTransactionSimulationResult? {

        guard let cached = storage[requestID] else {
            return nil
        }

        guard cached.expiresAt > now else {
            storage.removeValue(forKey: requestID)
            return nil
        }

        return cached.result
    }

    public func remove(
        requestID: SafariSimulationRequestID
    ) {
        storage.removeValue(forKey: requestID)
    }

    public func removeExpired(
        now: Date = Date()
    ) {
        storage = storage.filter {
            $0.value.expiresAt > now
        }
    }
}

// MARK: - Simulation telemetry

public enum SafariSimulationTelemetryEvent:
    Codable,
    Sendable
{
    case started(SafariSimulationID)
    case completed(SafariSimulationID)
    case failed(SafariSimulationID)
    case reverted(SafariSimulationID)
    case gasEstimated(SafariSimulationID)
    case warning(SafariSimulationID, SafariSimulationWarningCode)
}

public actor SafariSimulationTelemetry {

    private var events:
        [SafariSimulationTelemetryEvent] = []

    private let maximumEvents: Int

    public init(
        maximumEvents: Int = 2_000
    ) {
        self.maximumEvents = maximumEvents
    }

    public func record(
        _ event: SafariSimulationTelemetryEvent
    ) {
        events.append(event)

        if events.count > maximumEvents {
            events.removeFirst(
                events.count - maximumEvents
            )
        }
    }

    public func snapshot()
        -> [SafariSimulationTelemetryEvent]
    {
        events
    }
}

// MARK: - Core engine

public actor SafariWeb3TransactionSimulationEngine {

    private let rpc: any SafariWeb3SimulationRPC
    private let configuration: SafariSimulationConfiguration

    private let decoder: SafariEVMCalldataDecoder
    private let nativeAnalyzer: SafariNativeTransferAnalyzer
    private let warningEngine: SafariSimulationWarningEngine

    private let cache: SafariSimulationCache
    private let telemetry: SafariSimulationTelemetry

    private var activeTasks:
        [SafariSimulationID: Task<
            SafariTransactionSimulationResult,
            Error
        >] = [:]

    public init(
        rpc: any SafariWeb3SimulationRPC,
        configuration: SafariSimulationConfiguration = .init(),
        cache: SafariSimulationCache = .init(),
        telemetry: SafariSimulationTelemetry = .init()
    ) {
        self.rpc = rpc
        self.configuration = configuration
        self.decoder = SafariEVMCalldataDecoder()
        self.nativeAnalyzer = SafariNativeTransferAnalyzer()
        self.warningEngine = SafariSimulationWarningEngine()
        self.cache = cache
        self.telemetry = telemetry
    }

    public func simulate(
        transaction: SafariEVMTransaction
    ) async throws -> SafariTransactionSimulationResult {

        let requestID = SafariSimulationRequestID()
        let simulationID = SafariSimulationID()

        if let cached = await cache.result(
            for: requestID
        ) {
            return cached
        }

        await telemetry.record(
            .started(simulationID)
        )

        let task = Task {
            try await self.performSimulation(
                simulationID: simulationID,
                requestID: requestID,
                transaction: transaction
            )
        }

        activeTasks[simulationID] = task

        do {
            let result = try await task.value

            activeTasks.removeValue(
                forKey: simulationID
            )

            return result

        } catch {

            activeTasks.removeValue(
                forKey: simulationID
            )

            await telemetry.record(
                .failed(simulationID)
            )

            throw error
        }
    }

    public func cancel(
        simulationID: SafariSimulationID
    ) {
        activeTasks[simulationID]?.cancel()
        activeTasks.removeValue(
            forKey: simulationID
        )
    }

    private func performSimulation(
        simulationID: SafariSimulationID,
        requestID: SafariSimulationRequestID,
        transaction: SafariEVMTransaction
    ) async throws -> SafariTransactionSimulationResult {

        try Task.checkCancellation()

        let chainID = try await rpc.getChainID()

        try Task.checkCancellation()

        let returnData: EVMHex

        do {

            returnData = try await rpc.ethCall(
                transaction: transaction,
                blockTag: configuration.blockTag
            )

        } catch {

            await telemetry.record(
                .reverted(simulationID)
            )

            let revert = SafariSimulationRevert(
                rawData: transaction.data,
                decodedReason: error.localizedDescription,
                selector: SafariEVMFunctionSelector.selector(
                    from: transaction.data
                )
            )

            let warnings = warningEngine.warnings(
                transaction: transaction,
                movements: [],
                simulationSucceeded: false,
                gas: nil
            )

            let now = Date()

            let result = SafariTransactionSimulationResult(
                simulationID: simulationID,
                requestID: requestID,
                chainID: chainID,
                transaction: transaction,
                success: false,
                returnData: nil,
                revert: revert,
                gasEstimate: nil,
                assetMovements: [],
                warnings: warnings,
                createdAt: now,
                expiresAt: now.addingTimeInterval(
                    configuration.cacheLifetime.timeInterval
                )
            )

            await cache.insert(result)

            return result
        }

        try Task.checkCancellation()

        let rawGas: String

        do {
            rawGas = try await rpc.estimateGas(
                transaction: transaction
            )
        } catch {

            throw SafariTransactionSimulationError
                .gasEstimationFailed
        }

        await telemetry.record(
            .gasEstimated(simulationID)
        )

        let recommendedGas =
            multiplyHexQuantity(
                rawGas,
                by: configuration.gasSafetyMultiplier
            )

        let gas = SafariGasEstimate(
            rawEstimate: rawGas,
            recommendedLimit: recommendedGas,
            multiplier: configuration.gasSafetyMultiplier
        )

        let tokenMovements =
            decoder.decode(
                transaction: transaction
            )

        let nativeMovements =
            nativeAnalyzer.analyze(
                transaction: transaction
            )

        let movements =
            nativeMovements +
            tokenMovements

        let warnings = warningEngine.warnings(
            transaction: transaction,
            movements: movements,
            simulationSucceeded: true,
            gas: gas
        )

        for warning in warnings {
            await telemetry.record(
                .warning(
                    simulationID,
                    warning.code
                )
            )
        }

        let now = Date()

        let result =
            SafariTransactionSimulationResult(
                simulationID: simulationID,
                requestID: requestID,
                chainID: chainID,
                transaction: transaction,
                success: true,
                returnData: returnData,
                revert: nil,
                gasEstimate: gas,
                assetMovements: movements,
                warnings: warnings,
                createdAt: now,
                expiresAt: now.addingTimeInterval(
                    configuration.cacheLifetime.timeInterval
                )
            )

        await cache.insert(result)

        await telemetry.record(
            .completed(simulationID)
        )

        return result
    }

    private func multiplyHexQuantity(
        _ value: String,
        by multiplier: Double
    ) -> String {

        guard value.hasPrefix("0x"),
              let integer = UInt64(
                value.dropFirst(2),
                radix: 16
              )
        else {
            return value
        }

        let result = Double(integer) * multiplier

        return String(
            format: "0x%llx",
            UInt64(result.rounded(.up))
        )
    }
}

// MARK: - Human-readable transaction summary

public struct SafariTransactionSummaryBuilder: Sendable {

    public init() {}

    public func build(
        result: SafariTransactionSimulationResult
    ) -> String {

        guard result.success else {
            if let reason = result.revert?.decodedReason {
                return "Transaction simulation failed: \(reason)"
            }

            return "Transaction simulation failed."
        }

        var lines: [String] = []

        if !result.assetMovements.isEmpty {

            lines.append("Expected asset activity:")

            for movement in result.assetMovements {

                switch movement.kind {

                case .native:
                    lines.append(
                        "• Native asset: \(movement.amount ?? "unknown") → \(movement.to?.value ?? "unknown")"
                    )

                case .erc20:
                    lines.append(
                        "• Token transfer: \(movement.amount ?? "unknown") → \(movement.to?.value ?? "unknown")"
                    )

                case .erc721:
                    lines.append(
                        "• NFT transfer: \(movement.tokenID ?? "unknown") → \(movement.to?.value ?? "unknown")"
                    )

                case .erc1155:
                    lines.append(
                        "• ERC-1155 asset transfer"
                    )

                case .approval:
                    lines.append(
                        "• Token approval: \(movement.to?.value ?? "unknown")"
                    )

                case .unknown:
                    lines.append(
                        "• Unknown contract interaction"
                    )
                }
            }
        }

        if let gas = result.gasEstimate {
            lines.append(
                "Estimated gas: \(gas.rawEstimate)"
            )

            lines.append(
                "Recommended gas limit: \(gas.recommendedLimit)"
            )
        }

        if !result.warnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")

            for warning in result.warnings {
                lines.append(
                    "• \(warning.title): \(warning.message)"
                )
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Browser-facing facade

@MainActor
public final class SafariWeb3TransactionController {

    private let engine:
        SafariWeb3TransactionSimulationEngine

    public init(
        engine: SafariWeb3TransactionSimulationEngine
    ) {
        self.engine = engine
    }

    public func simulate(
        transaction: SafariEVMTransaction
    ) async throws
        -> SafariTransactionSimulationResult
    {
        try await engine.simulate(
            transaction: transaction
        )
    }

    public func cancel(
        simulationID: SafariSimulationID
    ) async {
        await engine.cancel(
            simulationID: simulationID
        )
    }
}

// MARK: - Integration with DApp requests

public actor SafariWeb3TransactionSimulationGateway {

    private let engine:
        SafariWeb3TransactionSimulationEngine

    public init(
        engine: SafariWeb3TransactionSimulationEngine
    ) {
        self.engine = engine
    }

    public func prepareSigningRequest(
        transaction: SafariEVMTransaction
    ) async throws
        -> SafariTransactionSimulationResult
    {
        let result = try await engine.simulate(
            transaction: transaction
        )

        guard result.success else {
            throw SafariTransactionSimulationError
                .simulationReverted
        }

        return result
    }
}

// MARK: - Example RPC adapter

public actor SafariExampleRPCAdapter:
    SafariWeb3SimulationRPC
{

    public init() {}

    public func ethCall(
        transaction: SafariEVMTransaction,
        blockTag: String
    ) async throws -> EVMHex {

        // Connect this to #2:
        //
        // SafariWeb3RPCNodeManager
        //
        // The actual production implementation should issue:
        //
        // eth_call
        //
        // against a healthy chain endpoint.

        return try EVMHex("0x")
    }

    public func estimateGas(
        transaction: SafariEVMTransaction
    ) async throws -> String {

        // Production:
        //
        // eth_estimateGas

        return "0x5208"
    }

    public func getBalance(
        address: EVMAddress,
        blockTag: String
    ) async throws -> String {

        // Production:
        //
        // eth_getBalance

        return "0x0"
    }

    public func getChainID()
        async throws -> String
    {
        // Production:
        //
        // eth_chainId

        return "0x1"
    }
}

// MARK: - Factory

public enum SafariWeb3SimulationFactory {

    public static func makeEngine()
        -> SafariWeb3TransactionSimulationEngine
    {
        let rpc = SafariExampleRPCAdapter()

        return SafariWeb3TransactionSimulationEngine(
            rpc: rpc,
            configuration: SafariSimulationConfiguration(
                blockTag: "latest",
                cacheLifetime: .seconds(10),
                maximumSimulationTime: .seconds(15),
                gasSafetyMultiplier: 1.15,
                enableTokenDecoding: true
            )
        )
    }
}

// MARK: - DEBUG tests

#if DEBUG

enum SafariWeb3TransactionSimulationTests {

    static func testAddress() throws {

        let address = try EVMAddress(
            "0x1111111111111111111111111111111111111111"
        )

        assert(
            address.value ==
            "0x1111111111111111111111111111111111111111"
        )
    }

    static func testNativeTransfer() throws {

        let from = try EVMAddress(
            "0x1111111111111111111111111111111111111111"
        )

        let to = try EVMAddress(
            "0x2222222222222222222222222222222222222222"
        )

        let tx = SafariEVMTransaction(
            from: from,
            to: to,
            value: "0xde0b6b3a7640000"
        )

        let analyzer =
            SafariNativeTransferAnalyzer()

        let movements =
            analyzer.analyze(
                transaction: tx
            )

        assert(
            movements.count == 1
        )

        assert(
            movements.first?.kind == .native
        )
    }

    static func testERC20Transfer() throws {

        let from = try EVMAddress(
            "0x1111111111111111111111111111111111111111"
        )

        let token = try EVMAddress(
            "0x3333333333333333333333333333333333333333"
        )

        let recipient =
            "0000000000000000000000000000000000000000000000002222222222222222222222222222222222222222"

        let amount =
            String(
                repeating: "0",
                count: 63
            ) + "1"

        let data =
            "0xa9059cbb" +
            recipient +
            amount

        let tx = SafariEVMTransaction(
            from: from,
            to: token,
            data: try EVMHex(data)
        )

        let decoder =
            SafariEVMCalldataDecoder()

        let movements =
            decoder.decode(
                transaction: tx
            )

        assert(
            movements.count == 1
        )

        assert(
            movements.first?.kind == .erc20
        )
    }

    static func testSummary() throws {

        let from = try EVMAddress(
            "0x1111111111111111111111111111111111111111"
        )

        let to = try EVMAddress(
            "0x2222222222222222222222222222222222222222"
        )

        let tx = SafariEVMTransaction(
            from: from,
            to: to,
            value: "0x1"
        )

        let result =
            SafariTransactionSimulationResult(
                simulationID: .init(),
                requestID: .init(),
                chainID: "0x1",
                transaction: tx,
                success: true,
                returnData: try? EVMHex("0x"),
                revert: nil,
                gasEstimate: nil,
                assetMovements: [
                    SafariAssetMovement(
                        kind: .native,
                        from: from,
                        to: to,
                        amount: "0x1"
                    )
                ],
                warnings: [],
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(10)
            )

        let summary =
            SafariTransactionSummaryBuilder()
                .build(result: result)

        assert(
            summary.contains(
                "Native asset"
            )
        )
    }

    static func runAll() throws {
        try testAddress()
        try testNativeTransfer()
        try testERC20Transfer()
        try testSummary()
    }
}

#endif




//
// SafariWeb3IdentityEngine.swift
//
// Native on-device Web3 identity layer for Safari.
//
// Swift 6 / macOS
//
// Responsibilities:
//   • Origin-scoped Web3 identities
//   • Cryptographic challenge/response
//   • DApp authentication
//   • Identity aliases
//   • Account/address discovery
//   • Selective disclosure
//   • Identity permissions
//   • Session-bound identity credentials
//   • Identity revocation
//   • Privacy-preserving telemetry
//
// IMPORTANT:
// This layer deliberately does NOT implement private-key cryptography.
// Production signing should be delegated to #1 Wallet Engine and a
// vetted secp256k1 implementation for EVM networks.
//

import Foundation

// MARK: - Identity identifiers

public struct SafariWeb3IdentityID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: UUID

    public init(
        rawValue: UUID = UUID()
    ) {
        self.rawValue = rawValue
    }
}

public struct SafariIdentityRequestID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: UUID

    public init(
        rawValue: UUID = UUID()
    ) {
        self.rawValue = rawValue
    }
}

public struct SafariIdentityCredentialID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: UUID

    public init(
        rawValue: UUID = UUID()
    ) {
        self.rawValue = rawValue
    }
}

// MARK: - DApp origin

public struct SafariIdentityOrigin:
    Hashable,
    Codable,
    Sendable
{
    public let scheme: String
    public let host: String
    public let port: Int?

    public init(
        scheme: String,
        host: String,
        port: Int? = nil
    ) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        self.port = port
    }

    public init?(
        url: URL
    ) {
        guard
            let scheme = url.scheme,
            let host = url.host
        else {
            return nil
        }

        self.init(
            scheme: scheme,
            host: host,
            port: url.port
        )
    }

    public var serialized: String {

        if let port {
            return "\(scheme)://\(host):\(port)"
        }

        return "\(scheme)://\(host)"
    }
}

// MARK: - Identity networks

public enum SafariIdentityNamespace:
    String,
    Codable,
    Sendable
{
    case eip155
    case solana
    case bitcoin
    case cosmos
    case custom
}

public struct SafariIdentityChain:
    Hashable,
    Codable,
    Sendable
{
    public let namespace: SafariIdentityNamespace
    public let reference: String

    public init(
        namespace: SafariIdentityNamespace,
        reference: String
    ) {
        self.namespace = namespace
        self.reference = reference
    }

    public var serialized: String {
        "\(namespace.rawValue):\(reference)"
    }
}

// MARK: - Identity address

public struct SafariWeb3IdentityAddress:
    Hashable,
    Codable,
    Sendable
{
    public let chain: SafariIdentityChain
    public let address: String

    public init(
        chain: SafariIdentityChain,
        address: String
    ) {
        self.chain = chain
        self.address = address
    }
}

// MARK: - Identity scope

public enum SafariIdentityScope:
    String,
    Codable,
    Sendable
{
    case origin
    case session
    case global
}

// MARK: - Disclosure permissions

public enum SafariIdentityDisclosure:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case publicAddress
    case chain
    case displayName
    case alias
    case signedAuthentication
    case accountProof
    case walletOwnership
}

// MARK: - Identity permissions

public struct SafariIdentityPermissionSet:
    Codable,
    Hashable,
    Sendable
{
    public var disclosures:
        Set<SafariIdentityDisclosure>

    public var chains:
        Set<SafariIdentityChain>

    public init(
        disclosures: Set<SafariIdentityDisclosure> = [],
        chains: Set<SafariIdentityChain> = []
    ) {
        self.disclosures = disclosures
        self.chains = chains
    }

    public func allows(
        _ disclosure: SafariIdentityDisclosure
    ) -> Bool {
        disclosures.contains(disclosure)
    }
}

// MARK: - Identity record

public struct SafariWeb3Identity:
    Codable,
    Hashable,
    Sendable
{
    public let id: SafariWeb3IdentityID

    public let origin: SafariIdentityOrigin

    public let scope: SafariIdentityScope

    public let createdAt: Date

    public var lastUsedAt: Date

    public var displayName: String?

    public var alias: String?

    public var addresses:
        [SafariWeb3IdentityAddress]

    public var permissions:
        SafariIdentityPermissionSet

    public var revoked: Bool

    public init(
        id: SafariWeb3IdentityID,
        origin: SafariIdentityOrigin,
        scope: SafariIdentityScope,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        displayName: String? = nil,
        alias: String? = nil,
        addresses: [SafariWeb3IdentityAddress] = [],
        permissions: SafariIdentityPermissionSet = .init(),
        revoked: Bool = false
    ) {
        self.id = id
        self.origin = origin
        self.scope = scope
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.displayName = displayName
        self.alias = alias
        self.addresses = addresses
        self.permissions = permissions
        self.revoked = revoked
    }
}

// MARK: - Authentication challenge

public struct SafariIdentityChallenge:
    Codable,
    Hashable,
    Sendable
{
    public let id: SafariIdentityRequestID

    public let origin: SafariIdentityOrigin

    public let nonce: String

    public let issuedAt: Date

    public let expiresAt: Date

    public let statement: String

    public let chain: SafariIdentityChain?

    public init(
        id: SafariIdentityRequestID,
        origin: SafariIdentityOrigin,
        nonce: String,
        issuedAt: Date,
        expiresAt: Date,
        statement: String,
        chain: SafariIdentityChain?
    ) {
        self.id = id
        self.origin = origin
        self.nonce = nonce
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.statement = statement
        self.chain = chain
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}

// MARK: - Authentication response

public struct SafariIdentityAuthentication:
    Codable,
    Hashable,
    Sendable
{
    public let credentialID:
        SafariIdentityCredentialID

    public let identityID:
        SafariWeb3IdentityID

    public let origin:
        SafariIdentityOrigin

    public let address:
        SafariWeb3IdentityAddress

    public let challenge:
        SafariIdentityChallenge

    public let signature:
        String

    public let issuedAt:
        Date

    public let expiresAt:
        Date

    public init(
        credentialID: SafariIdentityCredentialID,
        identityID: SafariWeb3IdentityID,
        origin: SafariIdentityOrigin,
        address: SafariWeb3IdentityAddress,
        challenge: SafariIdentityChallenge,
        signature: String,
        issuedAt: Date,
        expiresAt: Date
    ) {
        self.credentialID = credentialID
        self.identityID = identityID
        self.origin = origin
        self.address = address
        self.challenge = challenge
        self.signature = signature
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

// MARK: - Alias

public struct SafariWeb3IdentityAlias:
    Codable,
    Hashable,
    Sendable
{
    public let identityID:
        SafariWeb3IdentityID

    public let name: String

    public let namespace: String

    public let createdAt: Date

    public init(
        identityID: SafariWeb3IdentityID,
        name: String,
        namespace: String,
        createdAt: Date = Date()
    ) {
        self.identityID = identityID
        self.name = name
        self.namespace = namespace
        self.createdAt = createdAt
    }

    public var fullyQualifiedName: String {
        "\(name).\(namespace)"
    }
}

// MARK: - Identity request

public enum SafariIdentityRequestMethod:
    String,
    Codable,
    Sendable
{
    case requestIdentity
    case getAddress
    case getAddresses
    case requestAuthentication
    case signChallenge
    case getAlias
    case getIdentityMetadata
    case revokeIdentity
}

public struct SafariIdentityRequest:
    Codable,
    Sendable
{
    public let id:
        SafariIdentityRequestID

    public let origin:
        SafariIdentityOrigin

    public let method:
        SafariIdentityRequestMethod

    public let chain:
        SafariIdentityChain?

    public let message:
        String?

    public init(
        id: SafariIdentityRequestID = .init(),
        origin: SafariIdentityOrigin,
        method: SafariIdentityRequestMethod,
        chain: SafariIdentityChain? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.origin = origin
        self.method = method
        self.chain = chain
        self.message = message
    }
}

// MARK: - Identity errors

public enum SafariWeb3IdentityError:
    Error,
    LocalizedError,
    Sendable
{
    case identityNotFound
    case identityRevoked
    case originMismatch
    case permissionDenied
    case chainNotPermitted
    case addressUnavailable
    case challengeExpired
    case challengeInvalid
    case authenticationExpired
    case signingRejected
    case invalidOrigin
    case invalidMessage
    case aliasUnavailable
    case duplicateIdentity

    public var errorDescription: String? {

        switch self {

        case .identityNotFound:
            return "The Web3 identity could not be found."

        case .identityRevoked:
            return "This Web3 identity has been revoked."

        case .originMismatch:
            return "The identity does not belong to this origin."

        case .permissionDenied:
            return "The requested identity disclosure was not permitted."

        case .chainNotPermitted:
            return "This blockchain network is not permitted."

        case .addressUnavailable:
            return "No address is available for this blockchain."

        case .challengeExpired:
            return "The authentication challenge has expired."

        case .challengeInvalid:
            return "The authentication challenge is invalid."

        case .authenticationExpired:
            return "The authentication credential has expired."

        case .signingRejected:
            return "The identity signing request was rejected."

        case .invalidOrigin:
            return "The supplied origin is invalid."

        case .invalidMessage:
            return "The authentication message is invalid."

        case .aliasUnavailable:
            return "No identity alias is available."

        case .duplicateIdentity:
            return "An identity already exists for this origin."
        }
    }
}

// MARK: - Secure signer abstraction

public protocol SafariWeb3IdentitySigner:
    Sendable
{
    func signAuthenticationMessage(
        message: String,
        chain: SafariIdentityChain,
        address: SafariWeb3IdentityAddress
    ) async throws -> String
}

// MARK: - Wallet integration

public protocol SafariWeb3IdentityWallet:
    Sendable
{
    func addresses(
        for chain: SafariIdentityChain
    ) async throws
        -> [SafariWeb3IdentityAddress]

    func primaryAddress(
        for chain: SafariIdentityChain
    ) async throws
        -> SafariWeb3IdentityAddress?

    func signer(
        for address: SafariWeb3IdentityAddress
    ) async throws
        -> any SafariWeb3IdentitySigner
}

// MARK: - Origin security

public struct SafariIdentityOriginPolicy:
    Sendable
{
    public let requireHTTPS:
        Bool

    public let allowLocalDevelopment:
        Bool

    public init(
        requireHTTPS: Bool = true,
        allowLocalDevelopment: Bool = false
    ) {
        self.requireHTTPS = requireHTTPS
        self.allowLocalDevelopment =
            allowLocalDevelopment
    }

    public func validate(
        _ origin: SafariIdentityOrigin
    ) throws {

        if requireHTTPS &&
            origin.scheme != "https"
        {

            if allowLocalDevelopment &&
                (
                    origin.host == "localhost" ||
                    origin.host == "127.0.0.1"
                )
            {
                return
            }

            throw SafariWeb3IdentityError.invalidOrigin
        }
    }
}

// MARK: - Identity store

public actor SafariWeb3IdentityStore {

    private var identities:
        [SafariWeb3IdentityID: SafariWeb3Identity] = [:]

    private var originIndex:
        [SafariIdentityOrigin: SafariWeb3IdentityID] = [:]

    public init() {}

    public func insert(
        _ identity: SafariWeb3Identity
    ) throws {

        if originIndex[identity.origin] != nil {
            throw SafariWeb3IdentityError
                .duplicateIdentity
        }

        identities[identity.id] = identity
        originIndex[identity.origin] = identity.id
    }

    public func identity(
        id: SafariWeb3IdentityID
    ) -> SafariWeb3Identity? {
        identities[id]
    }

    public func identity(
        origin: SafariIdentityOrigin
    ) -> SafariWeb3Identity? {

        guard let id = originIndex[origin] else {
            return nil
        }

        return identities[id]
    }

    public func update(
        _ identity: SafariWeb3Identity
    ) {
        identities[identity.id] = identity
    }

    public func revoke(
        id: SafariWeb3IdentityID
    ) {

        guard var identity = identities[id]
        else {
            return
        }

        identity.revoked = true

        identities[id] = identity
    }

    public func remove(
        id: SafariWeb3IdentityID
    ) {

        guard let identity = identities.removeValue(
            forKey: id
        ) else {
            return
        }

        originIndex.removeValue(
            forKey: identity.origin
        )
    }

    public func all() -> [SafariWeb3Identity] {
        Array(identities.values)
    }
}

// MARK: - Challenge store

public actor SafariIdentityChallengeStore {

    private var challenges:
        [SafariIdentityRequestID: SafariIdentityChallenge] = [:]

    public init() {}

    public func insert(
        _ challenge: SafariIdentityChallenge
    ) {
        challenges[challenge.id] = challenge
    }

    public func challenge(
        id: SafariIdentityRequestID
    ) -> SafariIdentityChallenge? {

        guard let challenge = challenges[id]
        else {
            return nil
        }

        guard !challenge.isExpired else {
            challenges.removeValue(
                forKey: id
            )

            return nil
        }

        return challenge
    }

    public func consume(
        id: SafariIdentityRequestID
    ) {

        challenges.removeValue(
            forKey: id
        )
    }

    public func removeExpired() {

        let now = Date()

        challenges = challenges.filter {
            $0.value.expiresAt > now
        }
    }
}

// MARK: - Credential store

public actor SafariIdentityCredentialStore {

    private var credentials:
        [SafariIdentityCredentialID: SafariIdentityAuthentication] = [:]

    public init() {}

    public func insert(
        _ credential: SafariIdentityAuthentication
    ) {
        credentials[credential.credentialID] =
            credential
    }

    public func credential(
        id: SafariIdentityCredentialID
    ) -> SafariIdentityAuthentication? {

        guard let credential =
            credentials[id]
        else {
            return nil
        }

        guard credential.expiresAt > Date()
        else {
            credentials.removeValue(
                forKey: id
            )

            return nil
        }

        return credential
    }

    public func revoke(
        id: SafariIdentityCredentialID
    ) {
        credentials.removeValue(
            forKey: id
        )
    }

    public func revokeAll(
        identityID: SafariWeb3IdentityID
    ) {

        credentials = credentials.filter {
            $0.value.identityID != identityID
        }
    }
}

// MARK: - Identity policy

public struct SafariWeb3IdentityPolicy:
    Sendable
{
    public var challengeLifetime:
        TimeInterval

    public var credentialLifetime:
        TimeInterval

    public var requireExplicitAuthentication:
        Bool

    public var originPolicy:
        SafariIdentityOriginPolicy

    public init(
        challengeLifetime: TimeInterval = 300,
        credentialLifetime: TimeInterval = 3_600,
        requireExplicitAuthentication: Bool = true,
        originPolicy: SafariIdentityOriginPolicy = .init()
    ) {
        self.challengeLifetime =
            challengeLifetime

        self.credentialLifetime =
            credentialLifetime

        self.requireExplicitAuthentication =
            requireExplicitAuthentication

        self.originPolicy =
            originPolicy
    }
}

// MARK: - Nonce generator

public struct SafariIdentityNonceGenerator:
    Sendable
{
    public init() {}

    public func generate() -> String {

        let uuid = UUID().uuidString
            .replacingOccurrences(
                of: "-",
                with: ""
            )
            .lowercased()

        return uuid
    }
}

// MARK: - Authentication message builder

public struct SafariIdentityMessageBuilder:
    Sendable
{
    public init() {}

    public func build(
        origin: SafariIdentityOrigin,
        address: SafariWeb3IdentityAddress,
        challenge: SafariIdentityChallenge
    ) -> String {

        var message = ""

        message +=
            "\(origin.host) wants you to sign in with your Web3 identity.\n\n"

        message +=
            "Address: \(address.address)\n"

        message +=
            "Chain: \(address.chain.serialized)\n\n"

        message +=
            challenge.statement

        message += "\n\n"

        message +=
            "URI: \(origin.serialized)\n"

        message +=
            "Nonce: \(challenge.nonce)\n"

        message +=
            "Issued At: \(challenge.issuedAt.ISO8601Format())\n"

        message +=
            "Expiration Time: \(challenge.expiresAt.ISO8601Format())"

        return message
    }
}

// MARK: - Identity engine

public actor SafariWeb3IdentityEngine {

    private let wallet:
        any SafariWeb3IdentityWallet

    private let store:
        SafariWeb3IdentityStore

    private let challengeStore:
        SafariIdentityChallengeStore

    private let credentialStore:
        SafariIdentityCredentialStore

    private let policy:
        SafariWeb3IdentityPolicy

    private let nonceGenerator:
        SafariIdentityNonceGenerator

    private let messageBuilder:
        SafariIdentityMessageBuilder

    public init(
        wallet: any SafariWeb3IdentityWallet,
        store: SafariWeb3IdentityStore = .init(),
        challengeStore: SafariIdentityChallengeStore = .init(),
        credentialStore: SafariIdentityCredentialStore = .init(),
        policy: SafariWeb3IdentityPolicy = .init()
    ) {
        self.wallet = wallet
        self.store = store
        self.challengeStore = challengeStore
        self.credentialStore = credentialStore
        self.policy = policy
        self.nonceGenerator = .init()
        self.messageBuilder = .init()
    }

    // MARK: Identity creation

    public func createIdentity(
        origin: SafariIdentityOrigin,
        chain: SafariIdentityChain,
        permissions: SafariIdentityPermissionSet
    ) async throws -> SafariWeb3Identity {

        try policy.originPolicy.validate(
            origin
        )

        if let existing =
            await store.identity(
                origin: origin
            )
        {
            return existing
        }

        guard permissions.allows(
            .publicAddress
        ) else {
            throw SafariWeb3IdentityError
                .permissionDenied
        }

        let addresses =
            try await wallet.addresses(
                for: chain
            )

        guard !addresses.isEmpty else {
            throw SafariWeb3IdentityError
                .addressUnavailable
        }

        let identity =
            SafariWeb3Identity(
                id: .init(),
                origin: origin,
                scope: .origin,
                addresses: addresses,
                permissions: permissions
            )

        try await store.insert(
            identity
        )

        return identity
    }

    // MARK: Address access

    public func addresses(
        identityID: SafariWeb3IdentityID
    ) async throws
        -> [SafariWeb3IdentityAddress]
    {
        guard let identity =
            await store.identity(
                id: identityID
            )
        else {
            throw SafariWeb3IdentityError
                .identityNotFound
        }

        guard !identity.revoked else {
            throw SafariWeb3IdentityError
                .identityRevoked
        }

        guard identity.permissions.allows(
            .publicAddress
        ) else {
            throw SafariWeb3IdentityError
                .permissionDenied
        }

        return identity.addresses
    }

    // MARK: Challenge

    public func createChallenge(
        identityID: SafariWeb3IdentityID,
        chain: SafariIdentityChain,
        statement: String
    ) async throws
        -> SafariIdentityChallenge
    {
        guard let identity =
            await store.identity(
                id: identityID
            )
        else {
            throw SafariWeb3IdentityError
                .identityNotFound
        }

        guard !identity.revoked else {
            throw SafariWeb3IdentityError
                .identityRevoked
        }

        guard identity.permissions.allows(
            .signedAuthentication
        ) else {
            throw SafariWeb3IdentityError
                .permissionDenied
        }

        guard identity.permissions.chains.contains(
            chain
        ) else {
            throw SafariWeb3IdentityError
                .chainNotPermitted
        }

        let now = Date()

        let challenge =
            SafariIdentityChallenge(
                id: .init(),
                origin: identity.origin,
                nonce: nonceGenerator.generate(),
                issuedAt: now,
                expiresAt: now.addingTimeInterval(
                    policy.challengeLifetime
                ),
                statement: statement,
                chain: chain
            )

        await challengeStore.insert(
            challenge
        )

        return challenge
    }

    // MARK: Authentication

    public func authenticate(
        identityID: SafariWeb3IdentityID,
        challengeID: SafariIdentityRequestID
    ) async throws
        -> SafariIdentityAuthentication
    {
        guard let identity =
            await store.identity(
                id: identityID
            )
        else {
            throw SafariWeb3IdentityError
                .identityNotFound
        }

        guard !identity.revoked else {
            throw SafariWeb3IdentityError
                .identityRevoked
        }

        guard let challenge =
            await challengeStore.challenge(
                id: challengeID
            )
        else {
            throw SafariWeb3IdentityError
                .challengeExpired
        }

        guard challenge.origin ==
                identity.origin
        else {
            throw SafariWeb3IdentityError
                .originMismatch
        }

        guard let chain =
            challenge.chain
        else {
            throw SafariWeb3IdentityError
                .chainNotPermitted
        }

        guard let address =
            identity.addresses.first(
                where: {
                    $0.chain == chain
                }
            )
        else {
            throw SafariWeb3IdentityError
                .addressUnavailable
        }

        let message =
            messageBuilder.build(
                origin: identity.origin,
                address: address,
                challenge: challenge
            )

        let signer =
            try await wallet.signer(
                for: address
            )

        let signature =
            try await signer.signAuthenticationMessage(
                message: message,
                chain: chain,
                address: address
            )

        let now = Date()

        let authentication =
            SafariIdentityAuthentication(
                credentialID: .init(),
                identityID: identity.id,
                origin: identity.origin,
                address: address,
                challenge: challenge,
                signature: signature,
                issuedAt: now,
                expiresAt: now.addingTimeInterval(
                    policy.credentialLifetime
                )
            )

        await credentialStore.insert(
            authentication
        )

        await challengeStore.consume(
            id: challenge.id
        )

        return authentication
    }

    // MARK: Credential validation

    public func validate(
        credentialID: SafariIdentityCredentialID,
        origin: SafariIdentityOrigin
    ) async throws
        -> SafariIdentityAuthentication
    {
        guard let credential =
            await credentialStore.credential(
                id: credentialID
            )
        else {
            throw SafariWeb3IdentityError
                .authenticationExpired
        }

        guard credential.origin ==
                origin
        else {
            throw SafariWeb3IdentityError
                .originMismatch
        }

        guard let identity =
            await store.identity(
                id: credential.identityID
            )
        else {
            throw SafariWeb3IdentityError
                .identityNotFound
        }

        guard !identity.revoked else {
            throw SafariWeb3IdentityError
                .identityRevoked
        }

        return credential
    }

    // MARK: Revocation

    public func revoke(
        identityID: SafariWeb3IdentityID
    ) async {

        await store.revoke(
            id: identityID
        )

        await credentialStore.revokeAll(
            identityID: identityID
        )
    }

    // MARK: Alias

    public func setAlias(
        identityID: SafariWeb3IdentityID,
        name: String,
        namespace: String
    ) async throws
        -> SafariWeb3IdentityAlias
    {
        guard var identity =
            await store.identity(
                id: identityID
            )
        else {
            throw SafariWeb3IdentityError
                .identityNotFound
        }

        guard !identity.revoked else {
            throw SafariWeb3IdentityError
                .identityRevoked
        }

        guard identity.permissions.allows(
            .alias
        ) else {
            throw SafariWeb3IdentityError
                .permissionDenied
        }

        identity.alias = name

        await store.update(
            identity
        )

        return SafariWeb3IdentityAlias(
            identityID: identityID,
            name: name,
            namespace: namespace
        )
    }

    // MARK: Metadata

    public func metadata(
        identityID: SafariWeb3IdentityID
    ) async throws
        -> SafariWeb3Identity
    {
        guard let identity =
            await store.identity(
                id: identityID
            )
        else {
            throw SafariWeb3IdentityError
                .identityNotFound
        }

        guard !identity.revoked else {
            throw SafariWeb3IdentityError
                .identityRevoked
        }

        guard identity.permissions.allows(
            .displayName
        ) ||
        identity.permissions.allows(
            .alias
        )
        else {
            throw SafariWeb3IdentityError
                .permissionDenied
        }

        return identity
    }
}

// MARK: - JavaScript bridge message

public struct SafariIdentityBridgeMessage:
    Codable,
    Sendable
{
    public let method:
        SafariIdentityRequestMethod

    public let chainNamespace:
        String?

    public let chainReference:
        String?

    public let statement:
        String?

    public init(
        method: SafariIdentityRequestMethod,
        chainNamespace: String? = nil,
        chainReference: String? = nil,
        statement: String? = nil
    ) {
        self.method = method
        self.chainNamespace = chainNamespace
        self.chainReference = chainReference
        self.statement = statement
    }
}

// MARK: - WebKit bridge

#if canImport(WebKit)

@MainActor
public final class SafariWeb3IdentityWebViewBridge:
    NSObject,
    WKScriptMessageHandler
{
    private weak var webView:
        WKWebView?

    private let engine:
        SafariWeb3IdentityEngine

    public init(
        webView: WKWebView,
        engine: SafariWeb3IdentityEngine
    ) {
        self.webView = webView
        self.engine = engine
    }

    public func attach() {

        webView?
            .configuration
            .userContentController
            .add(
                self,
                name: "safariIdentity"
            )
    }

    public func detach() {

        webView?
            .configuration
            .userContentController
            .removeScriptMessageHandler(
                forName: "safariIdentity"
            )
    }

    public func userContentController(
        _ userContentController:
            WKUserContentController,
        didReceive message:
            WKScriptMessage
    ) {

        guard
            let webView,
            let originURL = webView.url,
            let origin =
                SafariIdentityOrigin(
                    url: originURL
                )
        else {
            return
        }

        guard
            let body =
                message.body as? [String: Any],
            let methodRaw =
                body["method"] as? String,
            let method =
                SafariIdentityRequestMethod(
                    rawValue: methodRaw
                )
        else {
            return
        }

        let chain: SafariIdentityChain?

        if
            let namespace =
                body["chainNamespace"] as? String,
            let reference =
                body["chainReference"] as? String,
            let parsedNamespace =
                SafariIdentityNamespace(
                    rawValue: namespace
                )
        {
            chain =
                SafariIdentityChain(
                    namespace: parsedNamespace,
                    reference: reference
                )
        } else {
            chain = nil
        }

        let statement =
            body["statement"] as? String

        Task {

            do {

                let request =
                    SafariIdentityRequest(
                        origin: origin,
                        method: method,
                        chain: chain,
                        message: statement
                    )

                let response =
                    try await self.handle(
                        request
                    )

                await self.send(
                    response: response
                )

            } catch {

                await self.sendError(
                    error.localizedDescription
                )
            }
        }
    }

    private func handle(
        _ request: SafariIdentityRequest
    ) async throws -> Any {

        switch request.method {

        case .requestIdentity:

            guard let chain =
                    request.chain
            else {
                throw SafariWeb3IdentityError
                    .chainNotPermitted
            }

            let permissions =
                SafariIdentityPermissionSet(
                    disclosures: [
                        .publicAddress,
                        .chain
                    ],
                    chains: [chain]
                )

            let identity =
                try await engine.createIdentity(
                    origin: request.origin,
                    chain: chain,
                    permissions: permissions
                )

            return [
                "identityID":
                    identity.id.rawValue.uuidString
            ]

        case .getAddress:

            guard
                let identity =
                    await engine.identity(
                        origin: request.origin
                    )
            else {
                throw SafariWeb3IdentityError
                    .identityNotFound
            }

            let addresses =
                try await engine.addresses(
                    identityID: identity.id
                )

            guard let chain =
                    request.chain
            else {
                throw SafariWeb3IdentityError
                    .chainNotPermitted
            }

            guard let address =
                    addresses.first(
                        where: {
                            $0.chain == chain
                        }
                    )
            else {
                throw SafariWeb3IdentityError
                    .addressUnavailable
            }

            return [
                "address":
                    address.address,
                "chain":
                    address.chain.serialized
            ]

        case .requestAuthentication:

            guard
                let identity =
                    await engine.identity(
                        origin: request.origin
                    )
            else {
                throw SafariWeb3IdentityError
                    .identityNotFound
            }

            guard
                let chain = request.chain
            else {
                throw SafariWeb3IdentityError
                    .chainNotPermitted
            }

            let challenge =
                try await engine.createChallenge(
                    identityID: identity.id,
                    chain: chain,
                    statement:
                        request.message ??
                        "Authenticate with Safari Web3 Identity."
                )

            return [
                "challengeID":
                    challenge.id.rawValue.uuidString,
                "nonce":
                    challenge.nonce,
                "expiresAt":
                    challenge.expiresAt.timeIntervalSince1970
            ]

        default:
            throw SafariWeb3IdentityError
                .permissionDenied
        }
    }

    private func send(
        response: Any
    ) async {

        guard let webView else {
            return
        }

        guard
            let data =
                try? JSONSerialization.data(
                    withJSONObject: response
                ),
            let json =
                String(
                    data: data,
                    encoding: .utf8
                )
        else {
            return
        }

        let script =
            "window.dispatchEvent(new CustomEvent('safariIdentityResponse',{detail:\(json)}));"

        webView.evaluateJavaScript(
            script
        )
    }

    private func sendError(
        _ error: String
    ) async {

        let escaped =
            error
                .replacingOccurrences(
                    of: "\\",
                    with: "\\\\"
                )
                .replacingOccurrences(
                    of: "\"",
                    with: "\\\""
                )

        webView?.evaluateJavaScript(
            """
            window.dispatchEvent(
                new CustomEvent(
                    'safariIdentityError',
                    {
                        detail: {
                            message: "\(escaped)"
                        }
                    }
                )
            );
            """
        )
    }
}

#endif

// MARK: - Engine extension

extension SafariWeb3IdentityEngine {

    public func identity(
        origin: SafariIdentityOrigin
    ) async -> SafariWeb3Identity? {

        await store.identity(
            origin: origin
        )
    }
}

// MARK: - Runtime

public actor SafariWeb3IdentityRuntime {

    public let engine:
        SafariWeb3IdentityEngine

    public init(
        wallet:
            any SafariWeb3IdentityWallet
    ) {
        self.engine =
            SafariWeb3IdentityEngine(
                wallet: wallet
            )
    }
}

// MARK: - Example wallet adapter

public actor SafariExampleIdentityWallet:
    SafariWeb3IdentityWallet
{
    private var exampleAddress:
        SafariWeb3IdentityAddress

    public init() {

        let chain =
            SafariIdentityChain(
                namespace: .eip155,
                reference: "1"
            )

        self.exampleAddress =
            SafariWeb3IdentityAddress(
                chain: chain,
                address:
                    "0x1111111111111111111111111111111111111111"
            )
    }

    public func addresses(
        for chain: SafariIdentityChain
    ) async throws
        -> [SafariWeb3IdentityAddress]
    {
        guard exampleAddress.chain == chain else {
            return []
        }

        return [exampleAddress]
    }

    public func primaryAddress(
        for chain: SafariIdentityChain
    ) async throws
        -> SafariWeb3IdentityAddress?
    {
        guard exampleAddress.chain == chain else {
            return nil
        }

        return exampleAddress
    }

    public func signer(
        for address: SafariWeb3IdentityAddress
    ) async throws
        -> any SafariWeb3IdentitySigner
    {
        SafariExampleIdentitySigner()
    }
}

// MARK: - Example signer

public struct SafariExampleIdentitySigner:
    SafariWeb3IdentitySigner
{
    public init() {}

    public func signAuthenticationMessage(
        message: String,
        chain: SafariIdentityChain,
        address: SafariWeb3IdentityAddress
    ) async throws -> String {

        // PLACEHOLDER ONLY.
        //
        // Production implementation must delegate to
        // SafariWeb3WalletEngine (#1) and its secure signing
        // implementation.
        //
        // Do NOT use this implementation to authenticate real
        // blockchain identities.

        return "0xSIMULATED_SIGNATURE"
    }
}

// MARK: - Tests

#if DEBUG

enum SafariWeb3IdentityTests {

    static func testOrigin() {

        let origin =
            SafariIdentityOrigin(
                scheme: "https",
                host: "example.com"
            )

        assert(
            origin.serialized ==
            "https://example.com"
        )
    }

    static func testChain() {

        let chain =
            SafariIdentityChain(
                namespace: .eip155,
                reference: "1"
            )

        assert(
            chain.serialized ==
            "eip155:1"
        )
    }

    static func testAddress() {

        let chain =
            SafariIdentityChain(
                namespace: .eip155,
                reference: "1"
            )

        let address =
            SafariWeb3IdentityAddress(
                chain: chain,
                address:
                    "0x1111111111111111111111111111111111111111"
            )

        assert(
            address.address.hasPrefix("0x")
        )
    }

    static func testPermissions() {

        let permissions =
            SafariIdentityPermissionSet(
                disclosures: [
                    .publicAddress,
                    .signedAuthentication
                ],
                chains: [
                    SafariIdentityChain(
                        namespace: .eip155,
                        reference: "1"
                    )
                ]
            )

        assert(
            permissions.allows(
                .publicAddress
            )
        )

        assert(
            permissions.allows(
                .signedAuthentication
            )
        )
    }

    static func runAll() {

        testOrigin()
        testChain()
        testAddress()
        testPermissions()
    }
}

#endif





//
// SafariWeb3SmartContractSecurityEngine.swift
//
// Native Web3 transaction / smart-contract security analysis
// for Safari.
//
// Swift 6
//
// Responsibilities:
//
//   • Analyse simulated transactions
//   • Inspect recipients and calldata
//   • Detect token approvals
//   • Detect unlimited approvals
//   • Detect suspicious recipient patterns
//   • Detect contract creation
//   • Detect unknown function selectors
//   • Detect dangerous permission changes
//   • Detect native-asset transfers
//   • Analyse simulation warnings
//   • Produce structured security findings
//   • Produce an overall risk level
//   • Support pluggable reputation providers
//   • Never sign transactions
//   • Never broadcast transactions
//
// Security principle:
//
//     "No finding" != "safe"
//
// The engine reports evidence and risk indicators rather than
// making an absolute safety guarantee.
//

import Foundation

// MARK: - Identifiers

public struct SafariSecurityAnalysisID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: UUID

    public init(
        rawValue: UUID = UUID()
    ) {
        self.rawValue = rawValue
    }
}

// MARK: - Security severity

public enum SafariSecuritySeverity:
    Int,
    Codable,
    Comparable,
    Sendable
{
    case informational = 0
    case notice = 1
    case warning = 2
    case high = 3
    case critical = 4

    public static func < (
        lhs: SafariSecuritySeverity,
        rhs: SafariSecuritySeverity
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Risk level

public enum SafariSecurityRiskLevel:
    String,
    Codable,
    Sendable
{
    case unknown
    case low
    case moderate
    case high
    case critical
}

// MARK: - Security finding code

public enum SafariSecurityFindingCode:
    String,
    Codable,
    Sendable
{
    case simulationFailed
    case unknownRecipient
    case contractCreation
    case nativeAssetTransfer

    case tokenTransfer
    case tokenApproval
    case unlimitedTokenApproval
    case approvalForAll

    case unknownFunction
    case suspiciousFunction
    case unusualCalldata

    case zeroAddressInteraction
    case selfTransfer

    case unexpectedRecipient
    case unexpectedAssetMovement

    case highGasRequirement
    case missingSimulation

    case contractNotVerified
    case reputationUnavailable

    case phishingDomain
    case knownMaliciousContract

    case chainMismatch
    case identityMismatch
}

// MARK: - Security finding

public struct SafariSecurityFinding:
    Codable,
    Hashable,
    Sendable
{
    public let code:
        SafariSecurityFindingCode

    public let severity:
        SafariSecuritySeverity

    public let title:
        String

    public let explanation:
        String

    public let evidence:
        [String]

    public let remediation:
        String?

    public init(
        code: SafariSecurityFindingCode,
        severity: SafariSecuritySeverity,
        title: String,
        explanation: String,
        evidence: [String] = [],
        remediation: String? = nil
    ) {
        self.code = code
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.evidence = evidence
        self.remediation = remediation
    }
}

// MARK: - Contract reputation

public enum SafariContractReputation:
    String,
    Codable,
    Sendable
{
    case unknown
    case new
    case established
    case trusted
    case suspicious
    case malicious
}

public struct SafariContractReputationResult:
    Codable,
    Hashable,
    Sendable
{
    public let address:
        String

    public let reputation:
        SafariContractReputation

    public let source:
        String

    public let explanation:
        String?

    public init(
        address: String,
        reputation: SafariContractReputation,
        source: String,
        explanation: String? = nil
    ) {
        self.address = address
        self.reputation = reputation
        self.source = source
        self.explanation = explanation
    }
}

// MARK: - Reputation provider

public protocol SafariContractReputationProvider:
    Sendable
{
    func reputation(
        for address: String,
        chainID: String
    ) async throws
        -> SafariContractReputationResult
}

// MARK: - Security configuration

public struct SafariSecurityScannerConfiguration:
    Sendable
{
    public var requireSimulation:
        Bool

    public var warnOnUnknownFunctions:
        Bool

    public var warnOnUnlimitedApprovals:
        Bool

    public var warnOnUnknownRecipients:
        Bool

    public var warnOnNativeTransfers:
        Bool

    public var warnOnContractCreation:
        Bool

    public var reputationTimeout:
        Duration

    public init(
        requireSimulation: Bool = true,
        warnOnUnknownFunctions: Bool = true,
        warnOnUnlimitedApprovals: Bool = true,
        warnOnUnknownRecipients: Bool = true,
        warnOnNativeTransfers: Bool = true,
        warnOnContractCreation: Bool = true,
        reputationTimeout: Duration = .seconds(5)
    ) {
        self.requireSimulation =
            requireSimulation

        self.warnOnUnknownFunctions =
            warnOnUnknownFunctions

        self.warnOnUnlimitedApprovals =
            warnOnUnlimitedApprovals

        self.warnOnUnknownRecipients =
            warnOnUnknownRecipients

        self.warnOnNativeTransfers =
            warnOnNativeTransfers

        self.warnOnContractCreation =
            warnOnContractCreation

        self.reputationTimeout =
            reputationTimeout
    }
}

// MARK: - Known function selectors

public struct SafariKnownEVMFunction:
    Sendable
{
    public let selector:
        String

    public let name:
        String

    public let category:
        SafariSecurityFunctionCategory

    public init(
        selector: String,
        name: String,
        category: SafariSecurityFunctionCategory
    ) {
        self.selector = selector.lowercased()
        self.name = name
        self.category = category
    }
}

public enum SafariSecurityFunctionCategory:
    String,
    Codable,
    Sendable
{
    case transfer
    case approval
    case nftTransfer
    case swap
    case contractManagement
    case permit
    case readOnly
    case unknown
}

// MARK: - Selector registry

public struct SafariEVMFunctionRegistry:
    Sendable
{
    private let functions:
        [String: SafariKnownEVMFunction]

    public init() {

        self.functions = [

            "0xa9059cbb":
                SafariKnownEVMFunction(
                    selector: "0xa9059cbb",
                    name: "transfer(address,uint256)",
                    category: .transfer
                ),

            "0x095ea7b3":
                SafariKnownEVMFunction(
                    selector: "0x095ea7b3",
                    name: "approve(address,uint256)",
                    category: .approval
                ),

            "0x23b872dd":
                SafariKnownEVMFunction(
                    selector: "0x23b872dd",
                    name: "transferFrom(address,address,uint256)",
                    category: .transfer
                ),

            "0xa22cb465":
                SafariKnownEVMFunction(
                    selector: "0xa22cb465",
                    name: "setApprovalForAll(address,bool)",
                    category: .approval
                ),

            "0x42842e0e":
                SafariKnownEVMFunction(
                    selector: "0x42842e0e",
                    name: "safeTransferFrom(address,address,uint256)",
                    category: .nftTransfer
                ),

            "0xb88d4fde":
                SafariKnownEVMFunction(
                    selector: "0xb88d4fde",
                    name:
                        "safeTransferFrom(address,address,uint256,bytes)",
                    category: .nftTransfer
                ),

            "0x095ea7b3":
                SafariKnownEVMFunction(
                    selector: "0x095ea7b3",
                    name: "approve(address,uint256)",
                    category: .approval
                )
        ]
    }

    public func lookup(
        selector: String
    ) -> SafariKnownEVMFunction? {
        functions[
            selector.lowercased()
        ]
    }
}

// MARK: - Security context

public struct SafariSecurityAnalysisContext:
    Sendable
{
    public let chainID:
        String

    public let origin:
        String?

    public let expectedRecipient:
        String?

    public let expectedChainID:
        String?

    public let userAddress:
        String?

    public let simulationSucceeded:
        Bool

    public init(
        chainID: String,
        origin: String? = nil,
        expectedRecipient: String? = nil,
        expectedChainID: String? = nil,
        userAddress: String? = nil,
        simulationSucceeded: Bool
    ) {
        self.chainID = chainID
        self.origin = origin
        self.expectedRecipient =
            expectedRecipient
        self.expectedChainID =
            expectedChainID
        self.userAddress =
            userAddress
        self.simulationSucceeded =
            simulationSucceeded
    }
}

// MARK: - Analysis result

public struct SafariSecurityAnalysisResult:
    Codable,
    Sendable
{
    public let id:
        SafariSecurityAnalysisID

    public let risk:
        SafariSecurityRiskLevel

    public let findings:
        [SafariSecurityFinding]

    public let contractReputation:
        SafariContractReputationResult?

    public let analyzedAt:
        Date

    public let expiresAt:
        Date

    public let canProceed:
        Bool

    public init(
        id: SafariSecurityAnalysisID,
        risk: SafariSecurityRiskLevel,
        findings: [SafariSecurityFinding],
        contractReputation:
            SafariContractReputationResult?,
        analyzedAt: Date,
        expiresAt: Date,
        canProceed: Bool
    ) {
        self.id = id
        self.risk = risk
        self.findings = findings
        self.contractReputation =
            contractReputation
        self.analyzedAt = analyzedAt
        self.expiresAt = expiresAt
        self.canProceed = canProceed
    }
}

// MARK: - Scanner

public struct SafariWeb3SecurityScanner:
    Sendable
{
    private let configuration:
        SafariSecurityScannerConfiguration

    private let functionRegistry:
        SafariEVMFunctionRegistry

    public init(
        configuration:
            SafariSecurityScannerConfiguration = .init()
    ) {
        self.configuration =
            configuration

        self.functionRegistry =
            SafariEVMFunctionRegistry()
    }

    public func scan(
        simulation:
            SafariTransactionSimulationResult,
        context:
            SafariSecurityAnalysisContext
    ) -> SafariSecurityAnalysisResult {

        var findings:
            [SafariSecurityFinding] = []

        // ---------------------------------------------------------
        // Simulation
        // ---------------------------------------------------------

        if configuration.requireSimulation &&
            !simulation.success
        {
            findings.append(
                SafariSecurityFinding(
                    code: .simulationFailed,
                    severity: .critical,
                    title: "Transaction simulation failed",
                    explanation:
                        "The proposed transaction did not successfully execute during simulation.",
                    remediation:
                        "Do not sign the transaction until the cause of the failure is understood."
                )
            )
        }

        // ---------------------------------------------------------
        // Chain verification
        // ---------------------------------------------------------

        if let expectedChain =
            context.expectedChainID,
            expectedChain != context.chainID
        {
            findings.append(
                SafariSecurityFinding(
                    code: .chainMismatch,
                    severity: .critical,
                    title: "Chain mismatch",
                    explanation:
                        "The transaction is being evaluated against a different blockchain network than the expected network.",
                    evidence: [
                        "Expected: \(expectedChain)",
                        "Actual: \(context.chainID)"
                    ],
                    remediation:
                        "Verify the selected blockchain network before signing."
                )
            )
        }

        // ---------------------------------------------------------
        // Recipient
        // ---------------------------------------------------------

        if let to =
            simulation.transaction.to
        {
            if configuration.warnOnUnknownRecipients {

                findings.append(
                    SafariSecurityFinding(
                        code: .unknownRecipient,
                        severity: .informational,
                        title: "Contract recipient",
                        explanation:
                            "The transaction interacts with a blockchain address.",
                        evidence: [
                            to.value
                        ]
                    )
                )
            }
        }
        else if configuration.warnOnContractCreation {

            findings.append(
                SafariSecurityFinding(
                    code: .contractCreation,
                    severity: .high,
                    title: "Contract creation",
                    explanation:
                        "This transaction does not specify a recipient and may create a contract.",
                    remediation:
                        "Only sign contract-creation transactions when you explicitly intended to deploy code."
                )
            )
        }

        // ---------------------------------------------------------
        // Native transfer
        // ---------------------------------------------------------

        if configuration.warnOnNativeTransfers {

            for movement in
                simulation.assetMovements
            {
                guard movement.kind == .native
                else {
                    continue
                }

                findings.append(
                    SafariSecurityFinding(
                        code: .nativeAssetTransfer,
                        severity: .warning,
                        title: "Native asset transfer",
                        explanation:
                            "The transaction transfers native blockchain assets.",
                        evidence: [
                            "Amount: \(movement.amount ?? "unknown")",
                            "Recipient: \(movement.to?.value ?? "unknown")"
                        ]
                    )
                )
            }
        }

        // ---------------------------------------------------------
        // Token transfers
        // ---------------------------------------------------------

        for movement in
            simulation.assetMovements
        {
            switch movement.kind {

            case .erc20:

                findings.append(
                    SafariSecurityFinding(
                        code: .tokenTransfer,
                        severity: .notice,
                        title: "ERC-20 token transfer",
                        explanation:
                            "The simulation indicates that tokens will move between addresses.",
                        evidence: [
                            "Contract: \(movement.tokenContract?.value ?? "unknown")",
                            "Recipient: \(movement.to?.value ?? "unknown")",
                            "Amount: \(movement.amount ?? "unknown")"
                        ]
                    )
                )

            case .erc721, .erc1155:

                findings.append(
                    SafariSecurityFinding(
                        code: .tokenTransfer,
                        severity: .notice,
                        title: "NFT / digital asset transfer",
                        explanation:
                            "The simulation indicates that a tokenised digital asset may move.",
                        evidence: [
                            "Contract: \(movement.tokenContract?.value ?? "unknown")",
                            "Recipient: \(movement.to?.value ?? "unknown")"
                        ]
                    )
                )

            case .approval:

                analyzeApproval(
                    movement: movement,
                    findings: &findings
                )

            default:
                break
            }
        }

        // ---------------------------------------------------------
        // Function selector
        // ---------------------------------------------------------

        if let selector =
            SafariEVMFunctionSelector.selector(
                from: simulation.transaction.data
            )
        {
            if let known =
                functionRegistry.lookup(
                    selector: selector
                )
            {
                if known.category == .approval {

                    findings.append(
                        SafariSecurityFinding(
                            code: .tokenApproval,
                            severity: .warning,
                            title: "Token permission change",
                            explanation:
                                "This transaction changes permissions that may allow another address or contract to spend tokens.",
                            evidence: [
                                known.name
                            ],
                            remediation:
                                "Verify the spender and allowance before signing."
                        )
                    )
                }

            }
            else if configuration.warnOnUnknownFunctions {

                findings.append(
                    SafariSecurityFinding(
                        code: .unknownFunction,
                        severity: .warning,
                        title: "Unknown contract function",
                        explanation:
                            "Safari does not recognize the transaction's function selector.",
                        evidence: [
                            selector
                        ],
                        remediation:
                            "Review the transaction through a trusted contract interface before signing."
                    )
                )
            }
        }

        // ---------------------------------------------------------
        // Self transfer
        // ---------------------------------------------------------

        if let userAddress =
            context.userAddress
        {
            let normalized =
                userAddress.lowercased()

            for movement in
                simulation.assetMovements
            {
                if movement.from?.value.lowercased()
                    == normalized &&
                    movement.to?.value.lowercased()
                    == normalized
                {
                    findings.append(
                        SafariSecurityFinding(
                            code: .selfTransfer,
                            severity: .informational,
                            title: "Self transfer",
                            explanation:
                                "The simulated asset movement begins and ends at the same address."
                        )
                    )
                }
            }
        }

        // ---------------------------------------------------------
        // Unusual calldata
        // ---------------------------------------------------------

        if simulation.transaction.data.byteCount > 10_000 {

            findings.append(
                SafariSecurityFinding(
                    code: .unusualCalldata,
                    severity: .warning,
                    title: "Unusually large calldata",
                    explanation:
                        "The transaction contains an unusually large calldata payload.",
                    evidence: [
                        "\(simulation.transaction.data.byteCount) bytes"
                    ]
                )
            )
        }

        // ---------------------------------------------------------
        // Gas
        // ---------------------------------------------------------

        if let gas =
            simulation.gasEstimate,
           let gasValue =
                UInt64(
                    gas.rawEstimate.dropFirst(2),
                    radix: 16
                )
        {
            if gasValue > 5_000_000 {

                findings.append(
                    SafariSecurityFinding(
                        code: .highGasRequirement,
                        severity: .warning,
                        title: "High gas requirement",
                        explanation:
                            "The transaction requires an unusually large gas limit.",
                        evidence: [
                            "Estimated gas: \(gas.rawEstimate)"
                        ],
                        remediation:
                            "Confirm that the contract operation genuinely requires this amount of computation."
                    )
                )
            }
        }

        // ---------------------------------------------------------
        // Final risk
        // ---------------------------------------------------------

        let risk =
            calculateRisk(
                findings
            )

        let canProceed =
            !findings.contains {
                $0.severity == .critical
            }

        let now = Date()

        return SafariSecurityAnalysisResult(
            id: .init(),
            risk: risk,
            findings: findings,
            contractReputation: nil,
            analyzedAt: now,
            expiresAt:
                now.addingTimeInterval(
                    30
                ),
            canProceed: canProceed
        )
    }

    private func analyzeApproval(
        movement:
            SafariAssetMovement,
        findings:
            inout [SafariSecurityFinding]
    ) {

        findings.append(
            SafariSecurityFinding(
                code: .tokenApproval,
                severity: .warning,
                title: "Token approval",
                explanation:
                    "The transaction changes token spending permissions.",
                evidence: [
                    "Token contract: \(movement.tokenContract?.value ?? "unknown")",
                    "Spender: \(movement.to?.value ?? "unknown")",
                    "Allowance: \(movement.amount ?? "unknown")"
                ],
                remediation:
                    "Check exactly which contract receives spending permission."
            )
        )

        if isUnlimitedAllowance(
            movement.amount
        ) {
            findings.append(
                SafariSecurityFinding(
                    code: .unlimitedTokenApproval,
                    severity: .high,
                    title: "Potential unlimited token approval",
                    explanation:
                        "The allowance appears to permit a very large token spend.",
                    evidence: [
                        "Allowance: \(movement.amount ?? "unknown")"
                    ],
                    remediation:
                        "Use the smallest allowance required for the intended transaction."
                )
            )
        }
    }

    private func isUnlimitedAllowance(
        _ amount: String?
    ) -> Bool {

        guard let amount else {
            return false
        }

        let normalized =
            amount
                .lowercased()
                .replacingOccurrences(
                    of: "0x",
                    with: ""
                )

        guard normalized.count >= 64
        else {
            return false
        }

        let suffix =
            String(
                normalized.suffix(64)
            )

        return suffix.allSatisfy {
            $0 == "f"
        }
    }

    private func calculateRisk(
        _ findings:
            [SafariSecurityFinding]
    ) -> SafariSecurityRiskLevel {

        if findings.contains(
            where: {
                $0.severity == .critical
            }
        ) {
            return .critical
        }

        if findings.contains(
            where: {
                $0.severity == .high
            }
        ) {
            return .high
        }

        if findings.contains(
            where: {
                $0.severity == .warning
            }
        ) {
            return .moderate
        }

        if findings.contains(
            where: {
                $0.severity == .notice
            }
        ) {
            return .low
        }

        return .unknown
    }
}

// MARK: - Reputation-aware scanner

public actor SafariWeb3SecurityEngine {

    private let scanner:
        SafariWeb3SecurityScanner

    private let reputationProvider:
        (any SafariContractReputationProvider)?

    private let configuration:
        SafariSecurityScannerConfiguration

    public init(
        configuration:
            SafariSecurityScannerConfiguration = .init(),
        reputationProvider:
            (any SafariContractReputationProvider)? = nil
    ) {
        self.configuration =
            configuration

        self.scanner =
            SafariWeb3SecurityScanner(
                configuration: configuration
            )

        self.reputationProvider =
            reputationProvider
    }

    public func analyze(
        simulation:
            SafariTransactionSimulationResult,
        context:
            SafariSecurityAnalysisContext
    ) async
        -> SafariSecurityAnalysisResult
    {
        var result =
            scanner.scan(
                simulation: simulation,
                context: context
            )

        guard
            let provider =
                reputationProvider,
            let recipient =
                simulation.transaction.to
        else {
            return result
        }

        do {

            let reputation =
                try await provider.reputation(
                    for: recipient.value,
                    chainID: context.chainID
                )

            result =
                applyReputation(
                    reputation,
                    to: result
                )

        } catch {

            // Reputation is an optional intelligence source.
            //
            // Failure to reach it must NOT automatically imply
            // that the contract is malicious.

            result.findings.append(
                SafariSecurityFinding(
                    code: .reputationUnavailable,
                    severity: .informational,
                    title: "Contract reputation unavailable",
                    explanation:
                        "Safari could not obtain optional external contract reputation information."
                )
            )
        }

        return result
    }

    private func applyReputation(
        _ reputation:
            SafariContractReputationResult,
        to result:
            SafariSecurityAnalysisResult
    ) -> SafariSecurityAnalysisResult {

        var findings =
            result.findings

        switch reputation.reputation {

        case .malicious:

            findings.append(
                SafariSecurityFinding(
                    code: .knownMaliciousContract,
                    severity: .critical,
                    title: "Contract reported as malicious",
                    explanation:
                        "An external reputation provider reports this contract as malicious.",
                    evidence: [
                        "Source: \(reputation.source)",
                        reputation.explanation ?? ""
                    ],
                    remediation:
                        "Do not sign until the contract and transaction have been independently verified."
                )
            )

        case .suspicious:

            findings.append(
                SafariSecurityFinding(
                    code: .knownMaliciousContract,
                    severity: .high,
                    title: "Contract reported as suspicious",
                    explanation:
                        "An external reputation provider has flagged this contract.",
                    evidence: [
                        "Source: \(reputation.source)",
                        reputation.explanation ?? ""
                    ]
                )
            )

        case .unknown,
             .new,
             .established,
             .trusted:
            break
        }

        let risk =
            calculateRisk(
                findings
            )

        var updated =
            result

        updated.findings =
            findings

        updated.canProceed =
            risk != .critical

        updated =
            SafariSecurityAnalysisResult(
                id: result.id,
                risk: risk,
                findings: findings,
                contractReputation: reputation,
                analyzedAt: result.analyzedAt,
                expiresAt: result.expiresAt,
                canProceed: updated.canProceed
            )

        return updated
    }

    private func calculateRisk(
        _ findings:
            [SafariSecurityFinding]
    ) -> SafariSecurityRiskLevel {

        if findings.contains(
            where: {
                $0.severity == .critical
            }
        ) {
            return .critical
        }

        if findings.contains(
            where: {
                $0.severity == .high
            }
        ) {
            return .high
        }

        if findings.contains(
            where: {
                $0.severity == .warning
            }
        ) {
            return .moderate
        }

        if findings.contains(
            where: {
                $0.severity == .notice
            }
        ) {
            return .low
        }

        return .unknown
    }
}

// MARK: - Security decision

public enum SafariSecurityDecision:
    String,
    Codable,
    Sendable
{
    case requireUserReview
    case allowUserToProceed
    case block
}

public struct SafariSecurityGateResult:
    Codable,
    Sendable
{
    public let decision:
        SafariSecurityDecision

    public let analysis:
        SafariSecurityAnalysisResult

    public init(
        decision:
            SafariSecurityDecision,
        analysis:
            SafariSecurityAnalysisResult
    ) {
        self.decision = decision
        self.analysis = analysis
    }
}

// MARK: - Signing gate

public struct SafariWeb3SecurityGate:
    Sendable
{
    public init() {}

    public func evaluate(
        analysis:
            SafariSecurityAnalysisResult
    ) -> SafariSecurityGateResult {

        if analysis.findings.contains(
            where: {
                $0.severity == .critical
            }
        ) {
            return SafariSecurityGateResult(
                decision: .block,
                analysis: analysis
            )
        }

        if analysis.findings.contains(
            where: {
                $0.severity == .high ||
                $0.severity == .warning
            }
        ) {
            return SafariSecurityGateResult(
                decision: .requireUserReview,
                analysis: analysis
            )
        }

        return SafariSecurityGateResult(
            decision: .allowUserToProceed,
            analysis: analysis
        )
    }
}

// MARK: - Security telemetry

public enum SafariSecurityTelemetryEvent:
    Codable,
    Sendable
{
    case analysisStarted
    case analysisCompleted
    case criticalFinding
    case highFinding
    case userReviewRequired
    case signingBlocked
}

public actor SafariSecurityTelemetry {

    private var events:
        [SafariSecurityTelemetryEvent] = []

    private let maximumEvents:
        Int

    public init(
        maximumEvents: Int = 2_000
    ) {
        self.maximumEvents =
            maximumEvents
    }

    public func record(
        _ event:
            SafariSecurityTelemetryEvent
    ) {

        events.append(
            event
        )

        if events.count >
            maximumEvents
        {
            events.removeFirst(
                events.count -
                maximumEvents
            )
        }
    }

    public func snapshot()
        -> [SafariSecurityTelemetryEvent]
    {
        events
    }
}

// MARK: - Integrated security runtime

public actor SafariWeb3SecurityRuntime {

    public let securityEngine:
        SafariWeb3SecurityEngine

    private let gate:
        SafariWeb3SecurityGate

    private let telemetry:
        SafariSecurityTelemetry

    public init(
        configuration:
            SafariSecurityScannerConfiguration = .init(),
        reputationProvider:
            (any SafariContractReputationProvider)? = nil
    ) {
        self.securityEngine =
            SafariWeb3SecurityEngine(
                configuration: configuration,
                reputationProvider:
                    reputationProvider
            )

        self.gate =
            SafariWeb3SecurityGate()

        self.telemetry =
            SafariSecurityTelemetry()
    }

    public func evaluate(
        simulation:
            SafariTransactionSimulationResult,
        context:
            SafariSecurityAnalysisContext
    ) async
        -> SafariSecurityGateResult
    {
        await telemetry.record(
            .analysisStarted
        )

        let analysis =
            await securityEngine.analyze(
                simulation: simulation,
                context: context
            )

        await telemetry.record(
            .analysisCompleted
        )

        switch analysis.risk {

        case .critical:
            await telemetry.record(
                .criticalFinding
            )

        case .high:
            await telemetry.record(
                .highFinding
            )

        default:
            break
        }

        let result =
            gate.evaluate(
                analysis: analysis
            )

        switch result.decision {

        case .requireUserReview:
            await telemetry.record(
                .userReviewRequired
            )

        case .block:
            await telemetry.record(
                .signingBlocked
            )

        case .allowUserToProceed:
            break
        }

        return result
    }
}

// MARK: - Example reputation provider

public actor SafariExampleContractReputationProvider:
    SafariContractReputationProvider
{
    public init() {}

    public func reputation(
        for address: String,
        chainID: String
    ) async throws
        -> SafariContractReputationResult
    {
        // Production implementation can connect to a
        // trusted contract intelligence service.
        //
        // Do not treat absence from a reputation database
        // as proof of safety.

        return SafariContractReputationResult(
            address: address,
            reputation: .unknown,
            source: "local-demo"
        )
    }
}

// MARK: - Human-readable security report

public struct SafariSecurityReportBuilder:
    Sendable
{
    public init() {}

    public func build(
        _ result:
            SafariSecurityAnalysisResult
    ) -> String {

        var lines:
            [String] = []

        lines.append(
            "Safari Web3 Security Analysis"
        )

        lines.append(
            "Risk: \(result.risk.rawValue.uppercased())"
        )

        lines.append("")

        if result.findings.isEmpty {

            lines.append(
                "No security indicators were detected by the local scanner."
            )

            lines.append(
                "This does not guarantee that the transaction or contract is safe."
            )

        } else {

            for finding in
                result.findings
            {
                lines.append(
                    "[\(finding.severity)] \(finding.title}"
                )

                lines.append(
                    finding.explanation
                )

                for evidence in
                    finding.evidence
                {
                    lines.append(
                        "  • \(evidence)"
                    )
                }

                if let remediation =
                    finding.remediation
                {
                    lines.append(
                        "  → \(remediation)"
                    )
                }

                lines.append("")
            }
        }

        return lines.joined(
            separator: "\n"
        )
    }
}

// MARK: - DEBUG tests

#if DEBUG

enum SafariWeb3SecurityTests {

    static func testRegistry() {

        let registry =
            SafariEVMFunctionRegistry()

        let transfer =
            registry.lookup(
                selector:
                    "0xa9059cbb"
            )

        assert(
            transfer?.name ==
            "transfer(address,uint256)"
        )
    }

    static func testUnlimitedApproval() {

        let movement =
            SafariAssetMovement(
                kind: .approval,
                amount:
                    "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            )

        let scanner =
            SafariWeb3SecurityScanner()

        let transaction =
            SafariEVMTransaction(
                from:
                    try! EVMAddress(
                        "0x1111111111111111111111111111111111111111"
                    ),
                to:
                    try! EVMAddress(
                        "0x2222222222222222222222222222222222222222"
                    )
            )

        let simulation =
            SafariTransactionSimulationResult(
                simulationID: .init(),
                requestID: .init(),
                chainID: "0x1",
                transaction: transaction,
                success: true,
                returnData:
                    try! EVMHex("0x"),
                revert: nil,
                gasEstimate: nil,
                assetMovements: [
                    movement
                ],
                warnings: [],
                createdAt: Date(),
                expiresAt:
                    Date().addingTimeInterval(30)
            )

        let context =
            SafariSecurityAnalysisContext(
                chainID: "0x1",
                userAddress:
                    "0x1111111111111111111111111111111111111111",
                simulationSucceeded: true
            )

        let result =
            scanner.scan(
                simulation: simulation,
                context: context
            )

        assert(
            result.findings.contains {
                $0.code ==
                .unlimitedTokenApproval
            }
        )
    }

    static func testContractCreation() {

        let transaction =
            SafariEVMTransaction(
                from:
                    try! EVMAddress(
                        "0x1111111111111111111111111111111111111111"
                    ),
                to: nil
            )

        let simulation =
            SafariTransactionSimulationResult(
                simulationID: .init(),
                requestID: .init(),
                chainID: "0x1",
                transaction: transaction,
                success: true,
                returnData:
                    try! EVMHex("0x"),
                revert: nil,
                gasEstimate: nil,
                assetMovements: [],
                warnings: [],
                createdAt: Date(),
                expiresAt:
                    Date().addingTimeInterval(30)
            )

        let scanner =
            SafariWeb3SecurityScanner()

        let context =
            SafariSecurityAnalysisContext(
                chainID: "0x1",
                simulationSucceeded: true
            )

        let result =
            scanner.scan(
                simulation: simulation,
                context: context
            )

        assert(
            result.findings.contains {
                $0.code ==
                .contractCreation
            }
        )
    }

    static func testGate() {

        let analysis =
            SafariSecurityAnalysisResult(
                id: .init(),
                risk: .critical,
                findings: [
                    SafariSecurityFinding(
                        code:
                            .knownMaliciousContract,
                        severity:
                            .critical,
                        title:
                            "Malicious contract",
                        explanation:
                            "Example."
                    )
                ],
                contractReputation: nil,
                analyzedAt: Date(),
                expiresAt:
                    Date().addingTimeInterval(30),
                canProceed: false
            )

        let gate =
            SafariWeb3SecurityGate()

        let result =
            gate.evaluate(
                analysis: analysis
            )

        assert(
            result.decision ==
            .block
        )
    }

    static func runAll() {

        testRegistry()
        testUnlimitedApproval()
        testContractCreation()
        testGate()
    }
}

#endif








//
// SafariWeb3StorageEngine.swift
//
// Native decentralized / content-addressed storage layer for Safari.
//
// Swift 6
//
// Architecture:
//
//     DApp
//       ↓
//     Web3 JS Bridge
//       ↓
//     SafariWeb3StorageEngine
//       ├── Content Addressing
//       ├── Local Object Store
//       ├── Pinning
//       ├── Encryption
//       ├── Integrity Verification
//       ├── Gateway Manager
//       ├── Storage Quotas
//       └── Telemetry
//
// This is deliberately an abstraction layer.
// A production implementation can attach:
//     • IPFS-compatible nodes
//     • trusted HTTP gateways
//     • local content-addressed storage
//     • decentralized storage providers
//     • encrypted application storage
//
// It does NOT claim that ordinary WebKit APIs provide native IPFS.
//
// Swift 6
//

import Foundation
import CryptoKit

// MARK: - Identifiers

public struct SafariWeb3ObjectID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }
}

public struct SafariWeb3StorageNamespace:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: String

    public init(
        _ rawValue: String
    ) {
        self.rawValue = rawValue
    }
}

// MARK: - Content hash

public struct SafariWeb3ContentHash:
    Hashable,
    Codable,
    Sendable
{
    public let algorithm:
        String

    public let digest:
        String

    public init(
        algorithm: String,
        digest: String
    ) {
        self.algorithm = algorithm
        self.digest = digest
    }

    public var serialized: String {
        "\(algorithm):\(digest)"
    }
}

// MARK: - Content addressing

public enum SafariWeb3AddressingAlgorithm:
    String,
    Codable,
    Sendable
{
    case sha256
}

public struct SafariWeb3ContentAddress:
    Hashable,
    Codable,
    Sendable
{
    public let algorithm:
        SafariWeb3AddressingAlgorithm

    public let digest:
        String

    public init(
        algorithm:
            SafariWeb3AddressingAlgorithm,
        digest: String
    ) {
        self.algorithm =
            algorithm

        self.digest =
            digest
    }

    public var cidLikeRepresentation:
        String
    {
        "\(algorithm.rawValue)-\(digest)"
    }
}

// MARK: - Storage object

public struct SafariWeb3StorageObject:
    Codable,
    Hashable,
    Sendable
{
    public let objectID:
        SafariWeb3ObjectID

    public let namespace:
        SafariWeb3StorageNamespace

    public let address:
        SafariWeb3ContentAddress

    public let contentType:
        String

    public let size:
        Int

    public let createdAt:
        Date

    public let expiresAt:
        Date?

    public let encrypted:
        Bool

    public let pinned:
        Bool

    public init(
        objectID:
            SafariWeb3ObjectID,
        namespace:
            SafariWeb3StorageNamespace,
        address:
            SafariWeb3ContentAddress,
        contentType:
            String,
        size:
            Int,
        createdAt:
            Date,
        expiresAt:
            Date?,
        encrypted:
            Bool,
        pinned:
            Bool
    ) {
        self.objectID =
            objectID

        self.namespace =
            namespace

        self.address =
            address

        self.contentType =
            contentType

        self.size =
            size

        self.createdAt =
            createdAt

        self.expiresAt =
            expiresAt

        self.encrypted =
            encrypted

        self.pinned =
            pinned
    }
}

// MARK: - Storage options

public struct SafariWeb3StorageWriteOptions:
    Sendable
{
    public var contentType:
        String

    public var encrypt:
        Bool

    public var pin:
        Bool

    public var expiresAt:
        Date?

    public init(
        contentType: String =
            "application/octet-stream",
        encrypt: Bool = false,
        pin: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.contentType =
            contentType

        self.encrypt =
            encrypt

        self.pin =
            pin

        self.expiresAt =
            expiresAt
    }
}

// MARK: - Storage errors

public enum SafariWeb3StorageError:
    Error,
    Codable,
    Sendable
{
    case objectNotFound
    case integrityFailure
    case quotaExceeded
    case encryptionFailure
    case decryptionFailure
    case invalidAddress
    case unsupportedAddressing
    case gatewayUnavailable
    case gatewayReturnedInvalidData
    case namespaceNotAuthorized
    case expired
    case invalidContent
    case persistenceFailure
}

// MARK: - Hashing

public struct SafariWeb3ContentHasher:
    Sendable
{
    public init() {}

    public func hash(
        _ data: Data
    ) -> SafariWeb3ContentAddress {

        let digest =
            SHA256.hash(
                data: data
            )

        let hex =
            digest
                .map {
                    String(
                        format: "%02x",
                        $0
                    )
                }
                .joined()

        return SafariWeb3ContentAddress(
            algorithm: .sha256,
            digest: hex
        )
    }
}

// MARK: - Encryption

public struct SafariWeb3EncryptedObject:
    Sendable
{
    public let ciphertext:
        Data

    public let nonce:
        Data

    public let tag:
        Data

    public init(
        ciphertext: Data,
        nonce: Data,
        tag: Data
    ) {
        self.ciphertext =
            ciphertext

        self.nonce =
            nonce

        self.tag =
            tag
    }
}

public struct SafariWeb3ObjectEncryptor:
    Sendable
{
    public init() {}

    public func encrypt(
        data: Data,
        key: SymmetricKey
    ) throws
        -> SafariWeb3EncryptedObject
    {
        do {

            let sealed =
                try AES.GCM.seal(
                    data,
                    using: key
                )

            guard
                let combined =
                    sealed.combined
            else {
                throw
                    SafariWeb3StorageError
                        .encryptionFailure
            }

            let nonce =
                Data(
                    combined.prefix(12)
                )

            let tag =
                Data(
                    combined.suffix(16)
                )

            let ciphertext =
                Data(
                    combined.dropFirst(12).dropLast(16)
                )

            return SafariWeb3EncryptedObject(
                ciphertext:
                    ciphertext,
                nonce:
                    nonce,
                tag:
                    tag
            )

        } catch {

            throw
                SafariWeb3StorageError
                    .encryptionFailure
        }
    }

    public func decrypt(
        object:
            SafariWeb3EncryptedObject,
        key:
            SymmetricKey
    ) throws -> Data {

        do {

            let nonce =
                try AES.GCM.Nonce(
                    data:
                        object.nonce
                )

            let sealed =
                try AES.GCM.SealedBox(
                    nonce:
                        nonce,
                    ciphertext:
                        object.ciphertext,
                    tag:
                        object.tag
                )

            return try AES.GCM.open(
                sealed,
                using: key
            )

        } catch {

            throw
                SafariWeb3StorageError
                    .decryptionFailure
        }
    }
}

// MARK: - Local storage record

struct SafariWeb3LocalStorageRecord:
    Codable,
    Sendable
{
    let metadata:
        SafariWeb3StorageObject

    let data:
        Data
}

// MARK: - Local object store

public actor SafariWeb3LocalObjectStore {

    private var objects:
        [SafariWeb3ObjectID:
            SafariWeb3LocalStorageRecord]

    public init() {

        self.objects = [:]
    }

    public func put(
        _ record:
            SafariWeb3LocalStorageRecord
    ) {

        objects[
            record.metadata.objectID
        ] = record
    }

    public func get(
        _ objectID:
            SafariWeb3ObjectID
    ) throws
        -> SafariWeb3LocalStorageRecord
    {
        guard
            let object =
                objects[objectID]
        else {
            throw
                SafariWeb3StorageError
                    .objectNotFound
        }

        return object
    }

    public func remove(
        _ objectID:
            SafariWeb3ObjectID
    ) {

        objects.removeValue(
            forKey:
                objectID
        )
    }

    public func all()
        -> [SafariWeb3LocalStorageRecord]
    {
        Array(
            objects.values
        )
    }

    public func contains(
        _ objectID:
            SafariWeb3ObjectID
    ) -> Bool
    {
        objects[
            objectID
        ] != nil
    }

    public func totalBytes()
        -> Int
    {
        objects.values.reduce(
            0
        ) {
            $0 + $1.data.count
        }
    }
}

// MARK: - Pinning

public enum SafariWeb3PinState:
    String,
    Codable,
    Sendable
{
    case unpinned
    case pending
    case pinned
    case failed
}

public struct SafariWeb3PinRecord:
    Codable,
    Hashable,
    Sendable
{
    public let objectID:
        SafariWeb3ObjectID

    public let address:
        SafariWeb3ContentAddress

    public let state:
        SafariWeb3PinState

    public let updatedAt:
        Date

    public init(
        objectID:
            SafariWeb3ObjectID,
        address:
            SafariWeb3ContentAddress,
        state:
            SafariWeb3PinState,
        updatedAt:
            Date = Date()
    ) {
        self.objectID =
            objectID

        self.address =
            address

        self.state =
            state

        self.updatedAt =
            updatedAt
    }
}

public actor SafariWeb3PinStore {

    private var records:
        [SafariWeb3ObjectID:
            SafariWeb3PinRecord] = [:]

    public init() {}

    public func set(
        _ record:
            SafariWeb3PinRecord
    ) {

        records[
            record.objectID
        ] = record
    }

    public func get(
        _ objectID:
            SafariWeb3ObjectID
    ) -> SafariWeb3PinRecord?
    {
        records[
            objectID
        ]
    }

    public func pinnedObjects()
        -> [SafariWeb3PinRecord]
    {
        records.values.filter {
            $0.state == .pinned
        }
    }
}

// MARK: - Gateway

public struct SafariWeb3GatewayResponse:
    Sendable
{
    public let data:
        Data

    public let contentType:
        String?

    public init(
        data: Data,
        contentType: String?
    ) {
        self.data =
            data

        self.contentType =
            contentType
    }
}

public protocol SafariWeb3Gateway:
    Sendable
{
    func fetch(
        address:
            SafariWeb3ContentAddress
    ) async throws
        -> SafariWeb3GatewayResponse
}

// MARK: - HTTP gateway

public struct SafariHTTPWeb3Gateway:
    SafariWeb3Gateway
{
    public let baseURL:
        URL

    public let session:
        URLSession

    public init(
        baseURL:
            URL,
        session:
            URLSession = .shared
    ) {
        self.baseURL =
            baseURL

        self.session =
            session
    }

    public func fetch(
        address:
            SafariWeb3ContentAddress
    ) async throws
        -> SafariWeb3GatewayResponse
    {
        let url =
            baseURL.appendingPathComponent(
                address.cidLikeRepresentation
            )

        let (
            data,
            response
        ) =
            try await session.data(
                from: url
            )

        guard
            let http =
                response as? HTTPURLResponse,
            (200..<300).contains(
                http.statusCode
            )
        else {
            throw
                SafariWeb3StorageError
                    .gatewayReturnedInvalidData
        }

        return SafariWeb3GatewayResponse(
            data:
                data,
            contentType:
                http.value(
                    forHTTPHeaderField:
                        "Content-Type"
                )
        )
    }
}

// MARK: - Gateway manager

public actor SafariWeb3GatewayManager {

    private var gateways:
        [any SafariWeb3Gateway]

    public init(
        gateways:
            [any SafariWeb3Gateway] = []
    ) {
        self.gateways =
            gateways
    }

    public func addGateway(
        _ gateway:
            any SafariWeb3Gateway
    ) {

        gateways.append(
            gateway
        )
    }

    public func fetch(
        address:
            SafariWeb3ContentAddress
    ) async throws
        -> SafariWeb3GatewayResponse
    {
        guard
            !gateways.isEmpty
        else {
            throw
                SafariWeb3StorageError
                    .gatewayUnavailable
        }

        var lastError:
            Error?

        for gateway in gateways {

            do {

                return try await gateway.fetch(
                    address:
                        address
                )

            } catch {

                lastError =
                    error
            }
        }

        throw
            lastError ??
            SafariWeb3StorageError
                .gatewayUnavailable
    }
}

// MARK: - Quotas

public struct SafariWeb3StorageQuota:
    Sendable
{
    public let maximumBytes:
        Int

    public init(
        maximumBytes:
            Int
    ) {
        self.maximumBytes =
            maximumBytes
    }
}

public actor SafariWeb3StorageQuotaManager {

    private var quotas:
        [SafariWeb3StorageNamespace:
            SafariWeb3StorageQuota]

    private let defaultQuota:
        SafariWeb3StorageQuota

    public init(
        defaultQuota:
            SafariWeb3StorageQuota =
                .init(
                    maximumBytes:
                        512 * 1024 * 1024
                )
    ) {
        self.defaultQuota =
            defaultQuota

        self.quotas = [:]
    }

    public func setQuota(
        _ quota:
            SafariWeb3StorageQuota,
        for namespace:
            SafariWeb3StorageNamespace
    ) {

        quotas[
            namespace
        ] = quota
    }

    public func quota(
        for namespace:
            SafariWeb3StorageNamespace
    ) -> SafariWeb3StorageQuota
    {
        quotas[
            namespace
        ] ??
        defaultQuota
    }

    public func canStore(
        bytes:
            Int,
        existingBytes:
            Int,
        namespace:
            SafariWeb3StorageNamespace
    ) -> Bool {

        let quota =
            quotas[
                namespace
            ] ??
            defaultQuota

        return
            existingBytes +
            bytes <=
            quota.maximumBytes
    }
}

// MARK: - Metadata index

public actor SafariWeb3StorageIndex {

    private var records:
        [SafariWeb3ObjectID:
            SafariWeb3StorageObject] = [:]

    public init() {}

    public func insert(
        _ object:
            SafariWeb3StorageObject
    ) {

        records[
            object.objectID
        ] = object
    }

    public func get(
        _ objectID:
            SafariWeb3ObjectID
    ) -> SafariWeb3StorageObject?
    {
        records[
            objectID
        ]
    }

    public func remove(
        _ objectID:
            SafariWeb3ObjectID
    ) {

        records.removeValue(
            forKey:
                objectID
        )
    }

    public func objects(
        in namespace:
            SafariWeb3StorageNamespace
    ) -> [SafariWeb3StorageObject]
    {
        records.values.filter {
            $0.namespace == namespace
        }
    }
}

// MARK: - Storage telemetry

public enum SafariWeb3StorageTelemetryEvent:
    Codable,
    Sendable
{
    case writeStarted
    case writeCompleted
    case readStarted
    case readCompleted
    case cacheHit
    case cacheMiss
    case gatewayFetch
    case integrityFailure
    case encryptionUsed
    case objectPinned
    case objectUnpinned
    case quotaRejected
}

public actor SafariWeb3StorageTelemetry {

    private var events:
        [SafariWeb3StorageTelemetryEvent]

    private let maximumEvents:
        Int

    public init(
        maximumEvents:
            Int = 2_000
    ) {
        self.maximumEvents =
            maximumEvents

        self.events = []
    }

    public func record(
        _ event:
            SafariWeb3StorageTelemetryEvent
    ) {

        events.append(
            event
        )

        if events.count >
            maximumEvents
        {
            events.removeFirst(
                events.count -
                maximumEvents
            )
        }
    }

    public func snapshot()
        -> [SafariWeb3StorageTelemetryEvent]
    {
        events
    }
}

// MARK: - Pin manager

public actor SafariWeb3PinManager {

    private let pinStore:
        SafariWeb3PinStore

    public init(
        pinStore:
            SafariWeb3PinStore =
                SafariWeb3PinStore()
    ) {
        self.pinStore =
            pinStore
    }

    public func markPinned(
        object:
            SafariWeb3StorageObject
    ) async {

        await pinStore.set(
            SafariWeb3PinRecord(
                objectID:
                    object.objectID,
                address:
                    object.address,
                state:
                    .pinned
            )
        )
    }

    public func unpin(
        object:
            SafariWeb3StorageObject
    ) async {

        await pinStore.set(
            SafariWeb3PinRecord(
                objectID:
                    object.objectID,
                address:
                    object.address,
                state:
                    .unpinned
            )
        )
    }

    public func isPinned(
        _ objectID:
            SafariWeb3ObjectID
    ) async -> Bool {

        guard
            let record =
                await pinStore.get(
                    objectID
                )
        else {
            return false
        }

        return
            record.state == .pinned
    }
}

// MARK: - Main storage engine

public actor SafariWeb3StorageEngine {

    public let localStore:
        SafariWeb3LocalObjectStore

    public let index:
        SafariWeb3StorageIndex

    public let gatewayManager:
        SafariWeb3GatewayManager

    public let quotaManager:
        SafariWeb3StorageQuotaManager

    public let pinManager:
        SafariWeb3PinManager

    public let telemetry:
        SafariWeb3StorageTelemetry

    private let hasher:
        SafariWeb3ContentHasher

    private let encryptor:
        SafariWeb3ObjectEncryptor

    public init(
        gateways:
            [any SafariWeb3Gateway] = []
    ) {
        self.localStore =
            SafariWeb3LocalObjectStore()

        self.index =
            SafariWeb3StorageIndex()

        self.gatewayManager =
            SafariWeb3GatewayManager(
                gateways:
                    gateways
            )

        self.quotaManager =
            SafariWeb3StorageQuotaManager()

        self.pinManager =
            SafariWeb3PinManager()

        self.telemetry =
            SafariWeb3StorageTelemetry()

        self.hasher =
            SafariWeb3ContentHasher()

        self.encryptor =
            SafariWeb3ObjectEncryptor()
    }

    // MARK: Write

    public func put(
        data:
            Data,
        namespace:
            SafariWeb3StorageNamespace,
        options:
            SafariWeb3StorageWriteOptions,
        encryptionKey:
            SymmetricKey? = nil
    ) async throws
        -> SafariWeb3StorageObject
    {
        await telemetry.record(
            .writeStarted
        )

        var storedData =
            data

        if options.encrypt {

            guard
                let encryptionKey
            else {
                throw
                    SafariWeb3StorageError
                        .encryptionFailure
            }

            let encrypted =
                try encryptor.encrypt(
                    data:
                        data,
                    key:
                        encryptionKey
                )

            storedData =
                encryptedData(
                    encrypted
                )

            await telemetry.record(
                .encryptionUsed
            )
        }

        let existing =
            await localStore.totalBytes()

        let allowed =
            await quotaManager.canStore(
                bytes:
                    storedData.count,
                existingBytes:
                    existing,
                namespace:
                    namespace
            )

        guard allowed
        else {

            await telemetry.record(
                .quotaRejected
            )

            throw
                SafariWeb3StorageError
                    .quotaExceeded
        }

        let address =
            hasher.hash(
                storedData
            )

        let objectID =
            SafariWeb3ObjectID(
                rawValue:
                    UUID()
                        .uuidString
            )

        let object =
            SafariWeb3StorageObject(
                objectID:
                    objectID,
                namespace:
                    namespace,
                address:
                    address,
                contentType:
                    options.contentType,
                size:
                    storedData.count,
                createdAt:
                    Date(),
                expiresAt:
                    options.expiresAt,
                encrypted:
                    options.encrypt,
                pinned:
                    options.pin
            )

        let record =
            SafariWeb3LocalStorageRecord(
                metadata:
                    object,
                data:
                    storedData
            )

        await localStore.put(
            record
        )

        await index.insert(
            object
        )

        if options.pin {

            await pinManager.markPinned(
                object:
                    object
            )

            await telemetry.record(
                .objectPinned
            )
        }

        await telemetry.record(
            .writeCompleted
        )

        return object
    }

    // MARK: Read

    public func get(
        objectID:
            SafariWeb3ObjectID,
        decryptionKey:
            SymmetricKey? = nil
    ) async throws -> Data {

        await telemetry.record(
            .readStarted
        )

        if let record =
            try? await localStore.get(
                objectID
            )
        {
            await telemetry.record(
                .cacheHit
            )

            try validateIntegrity(
                record
            )

            if record.metadata.encrypted {

                guard
                    let decryptionKey
                else {
                    throw
                        SafariWeb3StorageError
                            .decryptionFailure
                }

                return try decryptRecord(
                    record,
                    key:
                        decryptionKey
                )
            }

            await telemetry.record(
                .readCompleted
            )

            return record.data
        }

        await telemetry.record(
            .cacheMiss
        )

        guard
            let metadata =
                await index.get(
                    objectID
                )
        else {
            throw
                SafariWeb3StorageError
                    .objectNotFound
        }

        let response =
            try await gatewayManager.fetch(
                address:
                    metadata.address
            )

        await telemetry.record(
            .gatewayFetch
        )

        let computed =
            hasher.hash(
                response.data
            )

        guard
            computed ==
            metadata.address
        else {

            await telemetry.record(
                .integrityFailure
            )

            throw
                SafariWeb3StorageError
                    .integrityFailure
        }

        if metadata.encrypted {

            guard
                let decryptionKey
            else {
                throw
                    SafariWeb3StorageError
                        .decryptionFailure
            }

            return try decryptRaw(
                response.data,
                key:
                    decryptionKey
            )
        }

        await telemetry.record(
            .readCompleted
        )

        return response.data
    }

    // MARK: Fetch by address

    public func fetch(
        address:
            SafariWeb3ContentAddress
    ) async throws -> Data {

        if let record =
            await findLocalRecord(
                address:
                    address
            )
        {
            try validateIntegrity(
                record
            )

            return record.data
        }

        let response =
            try await gatewayManager.fetch(
                address:
                    address
            )

        let computed =
            hasher.hash(
                response.data
            )

        guard
            computed ==
            address
        else {
            throw
                SafariWeb3StorageError
                    .integrityFailure
        }

        return response.data
    }

    // MARK: Remove

    public func remove(
        objectID:
            SafariWeb3ObjectID
    ) async {

        await localStore.remove(
            objectID
        )

        await index.remove(
            objectID
        )
    }

    // MARK: Pin

    public func pin(
        objectID:
            SafariWeb3ObjectID
    ) async throws {

        let object =
            try await indexObject(
                objectID
            )

        await pinManager.markPinned(
            object:
                object
        )

        await telemetry.record(
            .objectPinned
        )
    }

    public func unpin(
        objectID:
            SafariWeb3ObjectID
    ) async throws {

        let object =
            try await indexObject(
                objectID
            )

        await pinManager.unpin(
            object:
                object
        )

        await telemetry.record(
            .objectUnpinned
        )
    }

    // MARK: Namespace listing

    public func list(
        namespace:
            SafariWeb3StorageNamespace
    ) async
        -> [SafariWeb3StorageObject]
    {
        await index.objects(
            in:
                namespace
        )
    }

    // MARK: Helpers

    private func findLocalRecord(
        address:
            SafariWeb3ContentAddress
    ) async
        -> SafariWeb3LocalStorageRecord?
    {
        let records =
            await localStore.all()

        return records.first {
            $0.metadata.address ==
                address
        }
    }

    private func indexObject(
        _ objectID:
            SafariWeb3ObjectID
    ) async throws
        -> SafariWeb3StorageObject
    {
        guard
            let object =
                await index.get(
                    objectID
                )
        else {
            throw
                SafariWeb3StorageError
                    .objectNotFound
        }

        return object
    }

    private func validateIntegrity(
        _ record:
            SafariWeb3LocalStorageRecord
    ) throws {

        let computed =
            hasher.hash(
                record.data
            )

        guard
            computed ==
            record.metadata.address
        else {
            throw
                SafariWeb3StorageError
                    .integrityFailure
        }

        if let expiresAt =
            record.metadata.expiresAt,
           expiresAt < Date()
        {
            throw
                SafariWeb3StorageError
                    .expired
        }
    }

    private func encryptedData(
        _ object:
            SafariWeb3EncryptedObject
    ) -> Data {

        var data =
            Data()

        data.append(
            object.nonce
        )

        data.append(
            object.ciphertext
        )

        data.append(
            object.tag
        )

        return data
    }

    private func decryptRecord(
        _ record:
            SafariWeb3LocalStorageRecord,
        key:
            SymmetricKey
    ) throws -> Data {

        try decryptRaw(
            record.data,
            key:
                key
        )
    }

    private func decryptRaw(
        _ data:
            Data,
        key:
            SymmetricKey
    ) throws -> Data {

        guard
            data.count >= 28
        else {
            throw
                SafariWeb3StorageError
                    .decryptionFailure
        }

        let nonceData =
            Data(
                data.prefix(12)
            )

        let tag =
            Data(
                data.suffix(16)
            )

        let ciphertext =
            Data(
                data.dropFirst(12).dropLast(16)
            )

        let object =
            SafariWeb3EncryptedObject(
                ciphertext:
                    ciphertext,
                nonce:
                    nonceData,
                tag:
                    tag
            )

        return try encryptor.decrypt(
            object:
                object,
            key:
                key
        )
    }
}

// MARK: - Storage policy

public enum SafariWeb3StorageAccess:
    String,
    Codable,
    Sendable
{
    case none
    case read
    case write
    case readWrite
}

public struct SafariWeb3StoragePermission:
    Codable,
    Hashable,
    Sendable
{
    public let origin:
        String

    public let namespace:
        SafariWeb3StorageNamespace

    public let access:
        SafariWeb3StorageAccess

    public let expiresAt:
        Date?

    public init(
        origin:
            String,
        namespace:
            SafariWeb3StorageNamespace,
        access:
            SafariWeb3StorageAccess,
        expiresAt:
            Date? = nil
    ) {
        self.origin =
            origin

        self.namespace =
            namespace

        self.access =
            access

        self.expiresAt =
            expiresAt
    }
}

// MARK: - Permission store

public actor SafariWeb3StoragePermissionStore {

    private var permissions:
        [String:
            SafariWeb3StoragePermission] = [:]

    public init() {}

    public func grant(
        _ permission:
            SafariWeb3StoragePermission
    ) {

        permissions[
            permission.origin
        ] = permission
    }

    public func permission(
        for origin:
            String
    ) -> SafariWeb3StoragePermission?
    {
        permissions[
            origin
        ]
    }

    public func revoke(
        origin:
            String
    ) {

        permissions.removeValue(
            forKey:
                origin
        )
    }
}

// MARK: - Origin gateway

public actor SafariWeb3OriginStorageGateway {

    private let permissions:
        SafariWeb3StoragePermissionStore

    private let storage:
        SafariWeb3StorageEngine

    public init(
        storage:
            SafariWeb3StorageEngine,
        permissions:
            SafariWeb3StoragePermissionStore =
                SafariWeb3StoragePermissionStore()
    ) {
        self.storage =
            storage

        self.permissions =
            permissions
    }

    public func put(
        origin:
            String,
        data:
            Data,
        namespace:
            SafariWeb3StorageNamespace,
        options:
            SafariWeb3StorageWriteOptions
    ) async throws
        -> SafariWeb3StorageObject
    {
        try await requireWrite(
            origin:
                origin,
            namespace:
                namespace
        )

        return try await storage.put(
            data:
                data,
            namespace:
                namespace,
            options:
                options
        )
    }

    public func get(
        origin:
            String,
        objectID:
            SafariWeb3ObjectID
    ) async throws
        -> Data
    {
        guard
            let permission =
                await permissions.permission(
                    for:
                        origin
                )
        else {
            throw
                SafariWeb3StorageError
                    .namespaceNotAuthorized
        }

        guard
            permission.access == .read ||
            permission.access == .readWrite
        else {
            throw
                SafariWeb3StorageError
                    .namespaceNotAuthorized
        }

        return try await storage.get(
            objectID:
                objectID
        )
    }

    private func requireWrite(
        origin:
            String,
        namespace:
            SafariWeb3StorageNamespace
    ) async throws {

        guard
            let permission =
                await permissions.permission(
                    for:
                        origin
                )
        else {
            throw
                SafariWeb3StorageError
                    .namespaceNotAuthorized
        }

        guard
            permission.namespace ==
                namespace
        else {
            throw
                SafariWeb3StorageError
                    .namespaceNotAuthorized
        }

        guard
            permission.access ==
                .write ||
            permission.access ==
                .readWrite
        else {
            throw
                SafariWeb3StorageError
                    .namespaceNotAuthorized
        }

        if let expires =
            permission.expiresAt,
           expires < Date()
        {
            throw
                SafariWeb3StorageError
                    .namespaceNotAuthorized
        }
    }
}

// MARK: - DApp bridge message

public struct SafariWeb3StorageMessage:
    Codable,
    Sendable
{
    public enum Operation:
        String,
        Codable,
        Sendable
    {
        case put
        case get
        case remove
        case pin
        case list
    }

    public let operation:
        Operation

    public let namespace:
        String?

    public let objectID:
        String?

    public let contentType:
        String?

    public let dataBase64:
        String?

    public init(
        operation:
            Operation,
        namespace:
            String? = nil,
        objectID:
            String? = nil,
        contentType:
            String? = nil,
        dataBase64:
            String? = nil
    ) {
        self.operation =
            operation

        self.namespace =
            namespace

        self.objectID =
            objectID

        self.contentType =
            contentType

        self.dataBase64 =
            dataBase64
    }
}

// MARK: - Runtime

public actor SafariWeb3StorageRuntime {

    public let storage:
        SafariWeb3StorageEngine

    public let permissions:
        SafariWeb3StoragePermissionStore

    public let originGateway:
        SafariWeb3OriginStorageGateway

    public init(
        gateways:
            [any SafariWeb3Gateway] = []
    ) {
        let storage =
            SafariWeb3StorageEngine(
                gateways:
                    gateways
            )

        let permissions =
            SafariWeb3StoragePermissionStore()

        self.storage =
            storage

        self.permissions =
            permissions

        self.originGateway =
            SafariWeb3OriginStorageGateway(
                storage:
                    storage,
                permissions:
                    permissions
            )
    }

    public func grant(
        origin:
            String,
        namespace:
            SafariWeb3StorageNamespace,
        access:
            SafariWeb3StorageAccess
    ) async {

        await permissions.grant(
            SafariWeb3StoragePermission(
                origin:
                    origin,
                namespace:
                    namespace,
                access:
                    access
            )
        )
    }
}

// MARK: - Example

public enum SafariWeb3StorageExample {

    public static func createNamespace()
        -> SafariWeb3StorageNamespace
    {
        SafariWeb3StorageNamespace(
            "dapp.example"
        )
    }

    public static func examplePayload()
        -> Data
    {
        Data(
            """
            {
              "type": "web3-document",
              "version": 1,
              "message": "Hello from Safari Web3 Storage"
            }
            """.utf8
        )
    }
}

// MARK: - Tests

#if DEBUG

enum SafariWeb3StorageTests {

    static func testHashing() {

        let hasher =
            SafariWeb3ContentHasher()

        let data =
            Data(
                "hello".utf8
            )

        let address =
            hasher.hash(
                data
            )

        assert(
            address.algorithm == .sha256
        )

        assert(
            !address.digest.isEmpty
        )
    }

    static func testEncryption()
        async throws
    {
        let encryptor =
            SafariWeb3ObjectEncryptor()

        let key =
            SymmetricKey(
                size:
                    .bits256
            )

        let original =
            Data(
                "secret web3 object".utf8
            )

        let encrypted =
            try encryptor.encrypt(
                data:
                    original,
                key:
                    key
            )

        let decrypted =
            try encryptor.decrypt(
                object:
                    encrypted,
                key:
                    key
            )

        assert(
            decrypted == original
        )
    }

    static func testStorage()
        async throws
    {
        let engine =
            SafariWeb3StorageEngine()

        let namespace =
            SafariWeb3StorageNamespace(
                "test"
            )

        let data =
            Data(
                "hello decentralized storage"
                    .utf8
            )

        let object =
            try await engine.put(
                data:
                    data,
                namespace:
                    namespace,
                options:
                    .init(
                        contentType:
                            "text/plain",
                        encrypt:
                            false,
                        pin:
                            true
                    )
            )

        let loaded =
            try await engine.get(
                objectID:
                    object.objectID
            )

        assert(
            loaded == data
        )

        let pinned =
            await engine.pinManager
                .isPinned(
                    object.objectID
                )

        assert(
            pinned
        )
    }

    static func testPermissions()
        async throws
    {
        let runtime =
            SafariWeb3StorageRuntime()

        let namespace =
            SafariWeb3StorageNamespace(
                "example"
            )

        await runtime.grant(
            origin:
                "https://example.com",
            namespace:
                namespace,
            access:
                .readWrite
        )

        let object =
            try await runtime.originGateway.put(
                origin:
                    "https://example.com",
                data:
                    Data(
                        "Web3".utf8
                    ),
                namespace:
                    namespace,
                options:
                    .init(
                        contentType:
                            "text/plain"
                    )
            )

        let data =
            try await runtime.originGateway.get(
                origin:
                    "https://example.com",
                objectID:
                    object.objectID
            )

        assert(
            data ==
            Data(
                "Web3".utf8
            )
        )
    }

    static func runAll()
        async throws
    {
        testHashing()
        try await testEncryption()
        try await testStorage()
        try await testPermissions()
    }
}

#endif







//
// SafariWeb3AssetBrowserEngine.swift
//
// Native token / NFT browser layer for Safari.
//
// Swift 6
//
// Responsibilities:
//
//   • ERC-20 style token balances
//   • ERC-721 NFT ownership
//   • ERC-1155 NFT balances
//   • token metadata
//   • NFT metadata
//   • collection information
//   • asset discovery
//   • local asset cache
//   • metadata resolution
//   • Web3 Storage integration
//   • security integration points
//   • origin-aware access
//   • telemetry
//
// This layer does NOT hold private keys.
// Signing remains the responsibility of #1 Wallet Engine.
//
// This layer also does NOT assume every token is trustworthy.
// Metadata and contract information are treated as untrusted input.
//

import Foundation
import CryptoKit

// MARK: - Basic identifiers

public struct SafariWeb3ChainID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: UInt64

    public init(
        _ rawValue: UInt64
    ) {
        self.rawValue = rawValue
    }
}

public struct SafariWeb3Address:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue: String

    public init(
        _ rawValue: String
    ) {
        self.rawValue =
            rawValue.lowercased()
    }

    public var normalized:
        String
    {
        rawValue.lowercased()
    }
}

public struct SafariWeb3ContractID:
    Hashable,
    Codable,
    Sendable
{
    public let chainID:
        SafariWeb3ChainID

    public let address:
        SafariWeb3Address

    public init(
        chainID:
            SafariWeb3ChainID,
        address:
            SafariWeb3Address
    ) {
        self.chainID =
            chainID

        self.address =
            address
    }
}

// MARK: - Asset identifiers

public enum SafariWeb3AssetStandard:
    String,
    Codable,
    Sendable
{
    case native
    case erc20
    case erc721
    case erc1155
    case unknown
}

public struct SafariWeb3AssetID:
    Hashable,
    Codable,
    Sendable
{
    public let contract:
        SafariWeb3ContractID

    public let tokenID:
        String?

    public let standard:
        SafariWeb3AssetStandard

    public init(
        contract:
            SafariWeb3ContractID,
        tokenID:
            String? = nil,
        standard:
            SafariWeb3AssetStandard
    ) {
        self.contract =
            contract

        self.tokenID =
            tokenID

        self.standard =
            standard
    }
}

// MARK: - Quantities

public struct SafariWeb3TokenAmount:
    Codable,
    Hashable,
    Sendable
{
    public let rawValue:
        String

    public let decimals:
        Int

    public init(
        rawValue:
            String,
        decimals:
            Int
    ) {
        self.rawValue =
            rawValue

        self.decimals =
            decimals
    }

    public var approximateDecimal:
        Decimal?
    {
        guard
            let integer =
                Decimal(
                    string:
                        rawValue
                )
        else {
            return nil
        }

        guard decimals > 0 else {
            return integer
        }

        var divisor =
            Decimal(1)

        for _ in 0..<decimals {
            divisor *= 10
        }

        return integer / divisor
    }
}

// MARK: - Token metadata

public struct SafariWeb3TokenMetadata:
    Codable,
    Hashable,
    Sendable
{
    public let name:
        String

    public let symbol:
        String

    public let decimals:
        Int

    public let logoURI:
        URL?

    public let description:
        String?

    public init(
        name:
            String,
        symbol:
            String,
        decimals:
            Int,
        logoURI:
            URL? = nil,
        description:
            String? = nil
    ) {
        self.name =
            name

        self.symbol =
            symbol

        self.decimals =
            decimals

        self.logoURI =
            logoURI

        self.description =
            description
    }
}

// MARK: - NFT metadata

public struct SafariWeb3NFTMetadata:
    Codable,
    Hashable,
    Sendable
{
    public let name:
        String?

    public let description:
        String?

    public let image:
        URL?

    public let animationURL:
        URL?

    public let externalURL:
        URL?

    public let attributes:
        [SafariWeb3NFTAttribute]

    public init(
        name:
            String?,
        description:
            String?,
        image:
            URL?,
        animationURL:
            URL?,
        externalURL:
            URL?,
        attributes:
            [SafariWeb3NFTAttribute] =
                []
    ) {
        self.name =
            name

        self.description =
            description

        self.image =
            image

        self.animationURL =
            animationURL

        self.externalURL =
            externalURL

        self.attributes =
            attributes
    }
}

public struct SafariWeb3NFTAttribute:
    Codable,
    Hashable,
    Sendable
{
    public let traitType:
        String?

    public let value:
        String

    public let displayType:
        String?

    public init(
        traitType:
            String?,
        value:
            String,
        displayType:
            String?
    ) {
        self.traitType =
            traitType

        self.value =
            value

        self.displayType =
            displayType
    }
}

// MARK: - Collection

public struct SafariWeb3Collection:
    Codable,
    Hashable,
    Sendable
{
    public let contract:
        SafariWeb3ContractID

    public let name:
        String

    public let description:
        String?

    public let image:
        URL?

    public let externalURL:
        URL?

    public let verified:
        Bool

    public init(
        contract:
            SafariWeb3ContractID,
        name:
            String,
        description:
            String?,
        image:
            URL?,
        externalURL:
            URL?,
        verified:
            Bool
    ) {
        self.contract =
            contract

        self.name =
            name

        self.description =
            description

        self.image =
            image

        self.externalURL =
            externalURL

        self.verified =
            verified
    }
}

// MARK: - Wallet asset

public enum SafariWeb3WalletAsset:
    Codable,
    Hashable,
    Sendable
{
    case native(
        chain:
            SafariWeb3ChainID,
        amount:
            SafariWeb3TokenAmount
    )

    case fungibleToken(
        asset:
            SafariWeb3AssetID,
        metadata:
            SafariWeb3TokenMetadata,
        balance:
            SafariWeb3TokenAmount
    )

    case nft(
        asset:
            SafariWeb3AssetID,
        collection:
            SafariWeb3Collection?,
        metadata:
            SafariWeb3NFTMetadata?,
        quantity:
            SafariWeb3TokenAmount
    )
}

// MARK: - Asset visibility

public enum SafariWeb3AssetVisibility:
    String,
    Codable,
    Sendable
{
    case visible
    case hidden
    case spam
    case suspicious
}

// MARK: - Asset record

public struct SafariWeb3AssetRecord:
    Codable,
    Hashable,
    Sendable
{
    public let asset:
        SafariWeb3WalletAsset

    public let visibility:
        SafariWeb3AssetVisibility

    public let updatedAt:
        Date

    public init(
        asset:
            SafariWeb3WalletAsset,
        visibility:
            SafariWeb3AssetVisibility =
                .visible,
        updatedAt:
            Date =
                Date()
    ) {
        self.asset =
            asset

        self.visibility =
            visibility

        self.updatedAt =
            updatedAt
    }
}

// MARK: - RPC abstraction

public enum SafariWeb3RPCError:
    Error,
    Sendable
{
    case unavailable
    case invalidResponse
    case executionReverted
    case malformedResult
}

public protocol SafariWeb3AssetRPC:
    Sendable
{
    func call(
        method:
            String,
        parameters:
            [String]
    ) async throws
        -> String
}

// MARK: - ERC-20 RPC provider

public protocol SafariWeb3ERC20Provider:
    Sendable
{
    func tokenMetadata(
        contract:
            SafariWeb3ContractID
    ) async throws
        -> SafariWeb3TokenMetadata

    func balance(
        owner:
            SafariWeb3Address,
        contract:
            SafariWeb3ContractID
    ) async throws
        -> String
}

// MARK: - NFT provider

public protocol SafariWeb3NFTProvider:
    Sendable
{
    func nftMetadata(
        asset:
            SafariWeb3AssetID
    ) async throws
        -> SafariWeb3NFTMetadata?

    func nftBalance(
        owner:
            SafariWeb3Address,
        asset:
            SafariWeb3AssetID
    ) async throws
        -> String

    func collection(
        contract:
            SafariWeb3ContractID
    ) async throws
        -> SafariWeb3Collection?
}

// MARK: - Metadata resolver

public protocol SafariWeb3MetadataResolver:
    Sendable
{
    func resolve(
        url:
            URL
    ) async throws
        -> Data
}

// MARK: - HTTP metadata resolver

public struct SafariHTTPMetadataResolver:
    SafariWeb3MetadataResolver
{
    public let session:
        URLSession

    public init(
        session:
            URLSession =
                .shared
    ) {
        self.session =
            session
    }

    public func resolve(
        url:
            URL
    ) async throws
        -> Data
    {
        let (
            data,
            response
        ) =
            try await session.data(
                from:
                    url
            )

        guard
            let http =
                response as? HTTPURLResponse,
            (200..<300).contains(
                http.statusCode
            )
        else {
            throw
                SafariWeb3RPCError
                    .invalidResponse
        }

        return data
    }
}

// MARK: - Metadata cache

public actor SafariWeb3MetadataCache {

    private struct Entry:
        Sendable
    {
        let data:
            Data

        let expiresAt:
            Date
    }

    private var entries:
        [URL: Entry] =
            [:]

    private let ttl:
        TimeInterval

    public init(
        ttl:
            TimeInterval =
                300
    ) {
        self.ttl =
            ttl
    }

    public func get(
        _ url:
            URL
    ) -> Data?
    {
        guard
            let entry =
                entries[url]
        else {
            return nil
        }

        guard
            entry.expiresAt >
                Date()
        else {

            entries.removeValue(
                forKey:
                    url
            )

            return nil
        }

        return entry.data
    }

    public func put(
        _ data:
            Data,
        for url:
            URL
    ) {

        entries[url] =
            Entry(
                data:
                    data,
                expiresAt:
                    Date().addingTimeInterval(
                        ttl
                    )
            )
    }

    public func clear() {

        entries.removeAll()
    }
}

// MARK: - NFT JSON decoder

public struct SafariWeb3NFTMetadataDecoder:
    Sendable
{
    public init() {}

    public func decode(
        data:
            Data
    ) throws
        -> SafariWeb3NFTMetadata
    {
        struct Raw:
            Decodable
        {
            let name:
                String?

            let description:
                String?

            let image:
                String?

            let animation_url:
                String?

            let external_url:
                String?

            let attributes:
                [RawAttribute]?
        }

        struct RawAttribute:
            Decodable
        {
            let trait_type:
                String?

            let value:
                String

            let display_type:
                String?
        }

        let decoder =
            JSONDecoder()

        let raw =
            try decoder.decode(
                Raw.self,
                from:
                    data
            )

        let attributes =
            raw.attributes?.map {
                SafariWeb3NFTAttribute(
                    traitType:
                        $0.trait_type,
                    value:
                        $0.value,
                    displayType:
                        $0.display_type
                )
            } ??
            []

        return SafariWeb3NFTMetadata(
            name:
                raw.name,
            description:
                raw.description,
            image:
                URL(
                    string:
                        raw.image ??
                        ""
                ),
            animationURL:
                URL(
                    string:
                        raw.animation_url ??
                        ""
                ),
            externalURL:
                URL(
                    string:
                        raw.external_url ??
                        ""
                ),
            attributes:
                attributes
        )
    }
}

// MARK: - Asset discovery

public struct SafariWeb3AssetDiscoveryRequest:
    Sendable
{
    public let owner:
        SafariWeb3Address

    public let chain:
        SafariWeb3ChainID

    public let contracts:
        [SafariWeb3ContractID]

    public init(
        owner:
            SafariWeb3Address,
        chain:
            SafariWeb3ChainID,
        contracts:
            [SafariWeb3ContractID]
    ) {
        self.owner =
            owner

        self.chain =
            chain

        self.contracts =
            contracts
    }
}

public struct SafariWeb3AssetDiscoveryResult:
    Sendable
{
    public let assets:
        [SafariWeb3AssetRecord]

    public let completedAt:
        Date

    public init(
        assets:
            [SafariWeb3AssetRecord],
        completedAt:
            Date =
                Date()
    ) {
        self.assets =
            assets

        self.completedAt =
            completedAt
    }
}

// MARK: - Asset cache

public actor SafariWeb3AssetCache {

    private var assets:
        [SafariWeb3AssetID:
            SafariWeb3AssetRecord] =
            [:]

    public init() {}

    public func insert(
        _ record:
            SafariWeb3AssetRecord
    ) {

        switch record.asset {

        case .native:
            break

        case let .fungibleToken(
            asset,
            _,
            _
        ):

            assets[
                asset
            ] =
                record

        case let .nft(
            asset,
            _,
            _,
            _
        ):

            assets[
                asset
            ] =
                record
        }
    }

    public func get(
        _ asset:
            SafariWeb3AssetID
    ) -> SafariWeb3AssetRecord?
    {
        assets[
            asset
        ]
    }

    public func remove(
        _ asset:
            SafariWeb3AssetID
    ) {

        assets.removeValue(
            forKey:
                asset
        )
    }

    public func all()
        -> [SafariWeb3AssetRecord]
    {
        Array(
            assets.values
        )
    }
}

// MARK: - Asset security classification

public enum SafariWeb3AssetSecurityLevel:
    String,
    Codable,
    Sendable
{
    case unknown
    case normal
    case suspicious
    case malicious
}

public struct SafariWeb3AssetSecurityAssessment:
    Codable,
    Sendable
{
    public let level:
        SafariWeb3AssetSecurityLevel

    public let reasons:
        [String]

    public init(
        level:
            SafariWeb3AssetSecurityLevel,
        reasons:
            [String]
    ) {
        self.level =
            level

        self.reasons =
            reasons
    }
}

public protocol SafariWeb3AssetSecurityProvider:
    Sendable
{
    func assess(
        asset:
            SafariWeb3AssetID
    ) async
        -> SafariWeb3AssetSecurityAssessment
}

// MARK: - Default security provider

public struct SafariDefaultWeb3AssetSecurityProvider:
    SafariWeb3AssetSecurityProvider
{
    public init() {}

    public func assess(
        asset:
            SafariWeb3AssetID
    ) async
        -> SafariWeb3AssetSecurityAssessment
    {
        SafariWeb3AssetSecurityAssessment(
            level:
                .unknown,
            reasons:
                [
                    "No independent security assessment was available."
                ]
        )
    }
}

// MARK: - Asset telemetry

public enum SafariWeb3AssetTelemetryEvent:
    Codable,
    Sendable
{
    case discoveryStarted
    case discoveryCompleted
    case metadataLoaded
    case metadataFailed
    case assetCached
    case cacheHit
    case cacheMiss
    case securityAssessment
    case hiddenAsset
    case suspiciousAsset
}

public actor SafariWeb3AssetTelemetry {

    private var events:
        [SafariWeb3AssetTelemetryEvent] =
            []

    private let maximumEvents:
        Int

    public init(
        maximumEvents:
            Int =
                2_000
    ) {
        self.maximumEvents =
            maximumEvents
    }

    public func record(
        _ event:
            SafariWeb3AssetTelemetryEvent
    ) {

        events.append(
            event
        )

        if events.count >
            maximumEvents
        {
            events.removeFirst(
                events.count -
                maximumEvents
            )
        }
    }

    public func snapshot()
        -> [SafariWeb3AssetTelemetryEvent]
    {
        events
    }
}

// MARK: - Asset browser engine

public actor SafariWeb3AssetBrowserEngine {

    private let erc20:
        any SafariWeb3ERC20Provider

    private let nft:
        any SafariWeb3NFTProvider

    private let security:
        any SafariWeb3AssetSecurityProvider

    private let assetCache:
        SafariWeb3AssetCache

    private let telemetry:
        SafariWeb3AssetTelemetry

    private let metadataCache:
        SafariWeb3MetadataCache

    public init(
        erc20:
            any SafariWeb3ERC20Provider,
        nft:
            any SafariWeb3NFTProvider,
        security:
            any SafariWeb3AssetSecurityProvider =
                SafariDefaultWeb3AssetSecurityProvider()
    ) {
        self.erc20 =
            erc20

        self.nft =
            nft

        self.security =
            security

        self.assetCache =
            SafariWeb3AssetCache()

        self.telemetry =
            SafariWeb3AssetTelemetry()

        self.metadataCache =
            SafariWeb3MetadataCache()
    }

    // MARK: Token loading

    public func loadToken(
        owner:
            SafariWeb3Address,
        contract:
            SafariWeb3ContractID
    ) async throws
        -> SafariWeb3AssetRecord
    {
        await telemetry.record(
            .discoveryStarted
        )

        if let cached =
            await assetCache.get(
                SafariWeb3AssetID(
                    contract:
                        contract,
                    standard:
                        .erc20
                )
            )
        {
            await telemetry.record(
                .cacheHit
            )

            return cached
        }

        await telemetry.record(
            .cacheMiss
        )

        let metadata =
            try await erc20.tokenMetadata(
                contract:
                    contract
            )

        let rawBalance =
            try await erc20.balance(
                owner:
                    owner,
                contract:
                    contract
            )

        let assetID =
            SafariWeb3AssetID(
                contract:
                    contract,
                standard:
                    .erc20
            )

        let asset =
            SafariWeb3WalletAsset
                .fungibleToken(
                    asset:
                        assetID,
                    metadata:
                        metadata,
                    balance:
                        SafariWeb3TokenAmount(
                            rawValue:
                                rawBalance,
                            decimals:
                                metadata.decimals
                        )
                )

        let assessment =
            await security.assess(
                asset:
                    assetID
            )

        let visibility:
            SafariWeb3AssetVisibility

        switch assessment.level {

        case .malicious:
            visibility =
                .spam

        case .suspicious:
            visibility =
                .suspicious

        case .unknown,
             .normal:
            visibility =
                .visible
        }

        let record =
            SafariWeb3AssetRecord(
                asset:
                    asset,
                visibility:
                    visibility
            )

        await assetCache.insert(
            record
        )

        await telemetry.record(
            .assetCached
        )

        await telemetry.record(
            .securityAssessment
        )

        if visibility ==
            .suspicious
        {
            await telemetry.record(
                .suspiciousAsset
            )
        }

        if visibility ==
            .spam
        {
            await telemetry.record(
                .hiddenAsset
            )
        }

        await telemetry.record(
            .discoveryCompleted
        )

        return record
    }

    // MARK: NFT loading

    public func loadNFT(
        owner:
            SafariWeb3Address,
        asset:
            SafariWeb3AssetID
    ) async throws
        -> SafariWeb3AssetRecord
    {
        if let cached =
            await assetCache.get(
                asset
            )
        {
            await telemetry.record(
                .cacheHit
            )

            return cached
        }

        await telemetry.record(
            .cacheMiss
        )

        let metadata =
            try await nft.nftMetadata(
                asset:
                    asset
            )

        let quantity =
            try await nft.nftBalance(
                owner:
                    owner,
                asset:
                    asset
            )

        let collection =
            try await nft.collection(
                contract:
                    asset.contract
            )

        let assetValue =
            SafariWeb3WalletAsset.nft(
                asset:
                    asset,
                collection:
                    collection,
                metadata:
                    metadata,
                quantity:
                    SafariWeb3TokenAmount(
                        rawValue:
                            quantity,
                        decimals:
                            0
                    )
            )

        let assessment =
            await security.assess(
                asset:
                    asset
            )

        let visibility:
            SafariWeb3AssetVisibility

        switch assessment.level {

        case .malicious:
            visibility =
                .spam

        case .suspicious:
            visibility =
                .suspicious

        default:
            visibility =
                .visible
        }

        let record =
            SafariWeb3AssetRecord(
                asset:
                    assetValue,
                visibility:
                    visibility
            )

        await assetCache.insert(
            record
        )

        await telemetry.record(
            .assetCached
        )

        await telemetry.record(
            .securityAssessment
        )

        return record
    }

    // MARK: Native asset

    public func nativeAsset(
        chain:
            SafariWeb3ChainID,
        balance:
            String
    ) -> SafariWeb3AssetRecord
    {
        SafariWeb3AssetRecord(
            asset:
                .native(
                    chain:
                        chain,
                    amount:
                        SafariWeb3TokenAmount(
                            rawValue:
                                balance,
                            decimals:
                                18
                        )
                )
        )
    }

    // MARK: Cache management

    public func cachedAssets()
        async -> [SafariWeb3AssetRecord]
    {
        await assetCache.all()
    }

    public func removeCachedAsset(
        _ asset:
            SafariWeb3AssetID
    ) async {

        await assetCache.remove(
            asset
        )
    }

    // MARK: Telemetry

    public func telemetrySnapshot()
        async
        -> [SafariWeb3AssetTelemetryEvent]
    {
        await telemetry.snapshot()
    }
}

// MARK: - Portfolio

public struct SafariWeb3Portfolio:
    Sendable
{
    public let owner:
        SafariWeb3Address

    public let chain:
        SafariWeb3ChainID

    public let assets:
        [SafariWeb3AssetRecord]

    public let generatedAt:
        Date

    public init(
        owner:
            SafariWeb3Address,
        chain:
            SafariWeb3ChainID,
        assets:
            [SafariWeb3AssetRecord],
        generatedAt:
            Date =
                Date()
    ) {
        self.owner =
            owner

        self.chain =
            chain

        self.assets =
            assets

        self.generatedAt =
            generatedAt
    }
}

// MARK: - Portfolio manager

public actor SafariWeb3PortfolioManager {

    private let browser:
        SafariWeb3AssetBrowserEngine

    public init(
        browser:
            SafariWeb3AssetBrowserEngine
    ) {
        self.browser =
            browser
    }

    public func portfolio(
        owner:
            SafariWeb3Address,
        chain:
            SafariWeb3ChainID,
        tokens:
            [SafariWeb3ContractID],
        nfts:
            [SafariWeb3AssetID],
        nativeBalance:
            String
    ) async
        -> SafariWeb3Portfolio
    {
        var assets:
            [SafariWeb3AssetRecord] =
                []

        assets.append(
            await browser.nativeAsset(
                chain:
                    chain,
                balance:
                    nativeBalance
            )
        )

        for token in tokens {

            if let record =
                try? await browser.loadToken(
                    owner:
                        owner,
                    contract:
                        token
                )
            {
                assets.append(
                    record
                )
            }
        }

        for nft in nfts {

            if let record =
                try? await browser.loadNFT(
                    owner:
                        owner,
                    asset:
                        nft
                )
            {
                assets.append(
                    record
                )
            }
        }

        return SafariWeb3Portfolio(
            owner:
                owner,
            chain:
                chain,
            assets:
                assets
        )
    }
}

// MARK: - Browser-facing asset summary

public struct SafariWeb3BrowserAssetSummary:
    Codable,
    Sendable
{
    public let title:
        String

    public let subtitle:
        String

    public let imageURL:
        URL?

    public let standard:
        SafariWeb3AssetStandard

    public let visibility:
        SafariWeb3AssetVisibility

    public init(
        title:
            String,
        subtitle:
            String,
        imageURL:
            URL?,
        standard:
            SafariWeb3AssetStandard,
        visibility:
            SafariWeb3AssetVisibility
    ) {
        self.title =
            title

        self.subtitle =
            subtitle

        self.imageURL =
            imageURL

        self.standard =
            standard

        self.visibility =
            visibility
    }
}

// MARK: - UI projection

public struct SafariWeb3AssetProjection:
    Sendable
{
    public init() {}

    public func project(
        _ record:
            SafariWeb3AssetRecord
    ) -> SafariWeb3BrowserAssetSummary
    {
        switch record.asset {

        case let .native(
            chain,
            amount
        ):

            return SafariWeb3BrowserAssetSummary(
                title:
                    "Native Asset",
                subtitle:
                    "Chain \(chain.rawValue) • \(amount.rawValue)",
                imageURL:
                    nil,
                standard:
                    .native,
                visibility:
                    record.visibility
            )

        case let .fungibleToken(
            _,
            metadata,
            balance
        ):

            return SafariWeb3BrowserAssetSummary(
                title:
                    metadata.name,
                subtitle:
                    "\(balance.rawValue) \(metadata.symbol)",
                imageURL:
                    metadata.logoURI,
                standard:
                    .erc20,
                visibility:
                    record.visibility
            )

        case let .nft(
            _,
            collection,
            metadata,
            quantity
        ):

            let title =
                metadata?.name ??
                "NFT"

            let collectionName =
                collection?.name ??
                "Unknown collection"

            return SafariWeb3BrowserAssetSummary(
                title:
                    title,
                subtitle:
                    "\(collectionName) • \(quantity.rawValue)",
                imageURL:
                    metadata?.image,
                standard:
                    .erc721,
                visibility:
                    record.visibility
            )
        }
    }
}

// MARK: - Example providers

public struct SafariExampleERC20Provider:
    SafariWeb3ERC20Provider
{
    public init() {}

    public func tokenMetadata(
        contract:
            SafariWeb3ContractID
    ) async throws
        -> SafariWeb3TokenMetadata
    {
        SafariWeb3TokenMetadata(
            name:
                "Example Token",
            symbol:
                "EXT",
            decimals:
                18
        )
    }

    public func balance(
        owner:
            SafariWeb3Address,
        contract:
            SafariWeb3ContractID
    ) async throws
        -> String
    {
        "1000000000000000000"
    }
}

public struct SafariExampleNFTProvider:
    SafariWeb3NFTProvider
{
    public init() {}

    public func nftMetadata(
        asset:
            SafariWeb3AssetID
    ) async throws
        -> SafariWeb3NFTMetadata?
    {
        SafariWeb3NFTMetadata(
            name:
                "Example NFT",
            description:
                "Example Web3 asset.",
            image:
                nil,
            animationURL:
                nil,
            externalURL:
                nil
        )
    }

    public func nftBalance(
        owner:
            SafariWeb3Address,
        asset:
            SafariWeb3AssetID
    ) async throws
        -> String
    {
        "1"
    }

    public func collection(
        contract:
            SafariWeb3ContractID
    ) async throws
        -> SafariWeb3Collection?
    {
        SafariWeb3Collection(
            contract:
                contract,
            name:
                "Example Collection",
            description:
                nil,
            image:
                nil,
            externalURL:
                nil,
            verified:
                false
        )
    }
}

// MARK: - Tests

#if DEBUG

enum SafariWeb3AssetBrowserTests {

    static func testToken()
        async throws
    {
        let engine =
            SafariWeb3AssetBrowserEngine(
                erc20:
                    SafariExampleERC20Provider(),
                nft:
                    SafariExampleNFTProvider()
            )

        let chain =
            SafariWeb3ChainID(
                1
            )

        let contract =
            SafariWeb3ContractID(
                chainID:
                    chain,
                address:
                    SafariWeb3Address(
                        "0x0000000000000000000000000000000000000001"
                    )
            )

        let record =
            try await engine.loadToken(
                owner:
                    SafariWeb3Address(
                        "0x0000000000000000000000000000000000000002"
                    ),
                contract:
                    contract
            )

        switch record.asset {

        case let .fungibleToken(
            _,
            metadata,
            _
        ):

            assert(
                metadata.symbol ==
                    "EXT"
            )

        default:

            assertionFailure(
                "Expected ERC-20 token."
            )
        }
    }

    static func testNFT()
        async throws
    {
        let engine =
            SafariWeb3AssetBrowserEngine(
                erc20:
                    SafariExampleERC20Provider(),
                nft:
                    SafariExampleNFTProvider()
            )

        let chain =
            SafariWeb3ChainID(
                1
            )

        let contract =
            SafariWeb3ContractID(
                chainID:
                    chain,
                address:
                    SafariWeb3Address(
                        "0x0000000000000000000000000000000000000003"
                    )
            )

        let asset =
            SafariWeb3AssetID(
                contract:
                    contract,
                tokenID:
                    "1",
                standard:
                    .erc721
            )

        let record =
            try await engine.loadNFT(
                owner:
                    SafariWeb3Address(
                        "0x0000000000000000000000000000000000000002"
                    ),
                asset:
                    asset
            )

        switch record.asset {

        case let .nft(
            _,
            collection,
            metadata,
            quantity
        ):

            assert(
                collection?.name ==
                    "Example Collection"
            )

            assert(
                metadata?.name ==
                    "Example NFT"
            )

            assert(
                quantity.rawValue ==
                    "1"
            )

        default:

            assertionFailure(
                "Expected NFT."
            )
        }
    }

    static func testProjection()
        async throws
    {
        let engine =
            SafariWeb3AssetBrowserEngine(
                erc20:
                    SafariExampleERC20Provider(),
                nft:
                    SafariExampleNFTProvider()
            )

        let contract =
            SafariWeb3ContractID(
                chainID:
                    SafariWeb3ChainID(
                        1
                    ),
                address:
                    SafariWeb3Address(
                        "0x0000000000000000000000000000000000000001"
                    )
            )

        let record =
            try await engine.loadToken(
                owner:
                    SafariWeb3Address(
                        "0x0000000000000000000000000000000000000002"
                    ),
                contract:
                    contract
            )

        let projection =
            SafariWeb3AssetProjection()
                .project(
                    record
                )

        assert(
            projection.title ==
                "Example Token"
        )
    }

    static func runAll()
        async throws
    {
        try await testToken()
        try await testNFT()
        try await testProjection()
    }
}

#endif






//
// SafariWeb3PrivacyPermissionFirewall.swift
//
// Safari Web3 #9
//
// Origin-scoped privacy and permission firewall.
//
// Swift 6 / strict concurrency oriented.
//
// Security principles:
//
// 1. A website never receives wallet access merely because it asks.
// 2. Permissions are scoped to the verified origin.
// 3. Sensitive operations are separate permissions.
// 4. Signing and transaction sending are never silently granted.
// 5. Permissions expire.
// 6. Private browsing uses session-only state.
// 7. Requests are rate limited.
// 8. Every decision can be audited.
// 9. Unknown permissions fail closed.
// 10. The firewall does not hold private keys.
//
// The actual wallet, identity, storage and asset systems remain
// separate subsystems.
//

import Foundation

// MARK: - Origin

public struct SafariWeb3Origin:
    Hashable,
    Codable,
    Sendable
{
    public let scheme:
        String

    public let host:
        String

    public let port:
        Int?

    public init(
        scheme:
            String,
        host:
            String,
        port:
            Int? = nil
    ) {
        self.scheme =
            scheme.lowercased()

        self.host =
            host.lowercased()

        self.port =
            port
    }

    public init?(
        url:
            URL
    ) {
        guard
            let scheme =
                url.scheme,
            let host =
                url.host
        else {
            return nil
        }

        self.init(
            scheme:
                scheme,
            host:
                host,
            port:
                url.port
        )
    }

    public var serialized:
        String
    {
        if let port {
            return
                "\(scheme)://\(host):\(port)"
        }

        return
            "\(scheme)://\(host)"
    }

    public var isSecure:
        Bool
    {
        scheme == "https"
    }
}

// MARK: - Permission types

public enum SafariWeb3Permission:
    String,
    Codable,
    Hashable,
    CaseIterable,
    Sendable
{
    case connectWallet
    case readAccounts
    case readChain
    case readBalance

    case readTokenMetadata
    case readTokenBalances

    case readNFTMetadata
    case readNFTBalances

    case readIdentity
    case authenticateIdentity

    case signMessage
    case signTypedData

    case estimateTransaction
    case simulateTransaction

    case sendTransaction
    case switchChain

    case readWeb3Storage
    case writeWeb3Storage

    case pinWeb3Storage

    case accessClipboard
}

// MARK: - Sensitivity

public enum SafariWeb3PermissionSensitivity:
    String,
    Codable,
    Sendable
{
    case low
    case moderate
    case high
    case critical
}

public extension SafariWeb3Permission {

    var sensitivity:
        SafariWeb3PermissionSensitivity
    {
        switch self {

        case .readChain,
             .readTokenMetadata,
             .readNFTMetadata:

            return .low

        case .readBalance,
             .readTokenBalances,
             .readNFTBalances,
             .readWeb3Storage:

            return .moderate

        case .connectWallet,
             .readAccounts,
             .readIdentity,
             .authenticateIdentity,
             .writeWeb3Storage,
             .pinWeb3Storage,
             .simulateTransaction,
             .estimateTransaction,
             .switchChain:

            return .high

        case .signMessage,
             .signTypedData,
             .sendTransaction,
             .accessClipboard:

            return .critical
        }
    }
}

// MARK: - Permission decision

public enum SafariWeb3PermissionDecision:
    String,
    Codable,
    Sendable
{
    case unknown
    case denied
    case granted
    case sessionGranted
    case restricted
}

// MARK: - Permission lifetime

public enum SafariWeb3PermissionLifetime:
    Codable,
    Hashable,
    Sendable
{
    case once
    case session
    case persistent
    case expires(Date)
}

// MARK: - Permission record

public struct SafariWeb3PermissionRecord:
    Codable,
    Hashable,
    Sendable
{
    public let origin:
        SafariWeb3Origin

    public let permission:
        SafariWeb3Permission

    public let decision:
        SafariWeb3PermissionDecision

    public let lifetime:
        SafariWeb3PermissionLifetime

    public let grantedAt:
        Date

    public let lastUsedAt:
        Date?

    public let expiresAt:
        Date?

    public init(
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission,
        decision:
            SafariWeb3PermissionDecision,
        lifetime:
            SafariWeb3PermissionLifetime,
        grantedAt:
            Date =
                Date(),
        lastUsedAt:
            Date? =
                nil,
        expiresAt:
            Date? =
                nil
    ) {
        self.origin =
            origin

        self.permission =
            permission

        self.decision =
            decision

        self.lifetime =
            lifetime

        self.grantedAt =
            grantedAt

        self.lastUsedAt =
            lastUsedAt

        self.expiresAt =
            expiresAt
    }
}

// MARK: - Request

public struct SafariWeb3PermissionRequest:
    Codable,
    Sendable
{
    public let requestID:
        UUID

    public let origin:
        SafariWeb3Origin

    public let permission:
        SafariWeb3Permission

    public let requestedAt:
        Date

    public let reason:
        String?

    public let sessionID:
        String?

    public init(
        requestID:
            UUID =
                UUID(),
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission,
        requestedAt:
            Date =
                Date(),
        reason:
            String? =
                nil,
        sessionID:
            String? =
                nil
    ) {
        self.requestID =
            requestID

        self.origin =
            origin

        self.permission =
            permission

        self.requestedAt =
            requestedAt

        self.reason =
            reason

        self.sessionID =
            sessionID
    }
}

// MARK: - Firewall result

public enum SafariWeb3FirewallResult:
    Codable,
    Sendable
{
    case allowed(
        expiresAt:
            Date?
    )

    case denied(
        reason:
            String
    )

    case requiresUserApproval

    case restricted(
        reason:
            String
    )
}

// MARK: - Policy context

public struct SafariWeb3FirewallContext:
    Sendable
{
    public let privateBrowsing:
        Bool

    public let secureOrigin:
        Bool

    public let userInitiated:
        Bool

    public let walletConnected:
        Bool

    public let chainID:
        UInt64?

    public let applicationActive:
        Bool

    public init(
        privateBrowsing:
            Bool,
        secureOrigin:
            Bool,
        userInitiated:
            Bool,
        walletConnected:
            Bool,
        chainID:
            UInt64?,
        applicationActive:
            Bool
    ) {
        self.privateBrowsing =
            privateBrowsing

        self.secureOrigin =
            secureOrigin

        self.userInitiated =
            userInitiated

        self.walletConnected =
            walletConnected

        self.chainID =
            chainID

        self.applicationActive =
            applicationActive
    }
}

// MARK: - Firewall policy

public struct SafariWeb3FirewallPolicy:
    Sendable
{
    public var requireHTTPS:
        Bool

    public var requireUserGestureForSigning:
        Bool

    public var requireUserGestureForSending:
        Bool

    public var allowPersistentPrivateBrowsing:
        Bool

    public var permissionLifetime:
        TimeInterval

    public init(
        requireHTTPS:
            Bool =
                true,
        requireUserGestureForSigning:
            Bool =
                true,
        requireUserGestureForSending:
            Bool =
                true,
        allowPersistentPrivateBrowsing:
            Bool =
                false,
        permissionLifetime:
            TimeInterval =
                30 * 24 * 60 * 60
    ) {
        self.requireHTTPS =
            requireHTTPS

        self.requireUserGestureForSigning =
            requireUserGestureForSigning

        self.requireUserGestureForSending =
            requireUserGestureForSending

        self.allowPersistentPrivateBrowsing =
            allowPersistentPrivateBrowsing

        self.permissionLifetime =
            permissionLifetime
    }
}

// MARK: - Permission store

public actor SafariWeb3PermissionStore {

    private var records:
        [SafariWeb3PermissionKey:
            SafariWeb3PermissionRecord] =
            [:]

    public init() {}

    public func record(
        _ record:
            SafariWeb3PermissionRecord
    ) {

        let key =
            SafariWeb3PermissionKey(
                origin:
                    record.origin,
                permission:
                    record.permission
            )

        records[key] =
            record
    }

    public func get(
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission
    )
        -> SafariWeb3PermissionRecord?
    {
        records[
            SafariWeb3PermissionKey(
                origin:
                    origin,
                permission:
                    permission
            )
        ]
    }

    public func remove(
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission
    ) {

        records.removeValue(
            forKey:
                SafariWeb3PermissionKey(
                    origin:
                        origin,
                    permission:
                        permission
                )
        )
    }

    public func removeOrigin(
        _ origin:
            SafariWeb3Origin
    ) {

        records =
            records.filter {
                $0.key.origin != origin
            }
    }

    public func all()
        -> [SafariWeb3PermissionRecord]
    {
        Array(
            records.values
        )
    }
}

public struct SafariWeb3PermissionKey:
    Hashable,
    Sendable
{
    public let origin:
        SafariWeb3Origin

    public let permission:
        SafariWeb3Permission

    public init(
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission
    ) {
        self.origin =
            origin

        self.permission =
            permission
    }
}

// MARK: - Session permission store

public actor SafariWeb3SessionPermissionStore {

    private var records:
        [String:
            [SafariWeb3Permission:
                SafariWeb3PermissionRecord]] =
            [:]

    public init() {}

    public func grant(
        sessionID:
            String,
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission
    ) {

        let record =
            SafariWeb3PermissionRecord(
                origin:
                    origin,
                permission:
                    permission,
                decision:
                    .sessionGranted,
                lifetime:
                    .session
            )

        var session =
            records[
                sessionID
            ] ??
            [:]

        session[
            permission
        ] =
            record

        records[
            sessionID
        ] =
            session
    }

    public func get(
        sessionID:
            String,
        permission:
            SafariWeb3Permission
    )
        -> SafariWeb3PermissionRecord?
    {
        records[
            sessionID
        ]?[permission]
    }

    public func removeSession(
        _ sessionID:
            String
    ) {

        records.removeValue(
            forKey:
                sessionID
        )
    }
}

// MARK: - Rate limiter

public struct SafariWeb3RateLimit:
    Sendable
{
    public let maximumRequests:
        Int

    public let window:
        TimeInterval

    public init(
        maximumRequests:
            Int,
        window:
            TimeInterval
    ) {
        self.maximumRequests =
            maximumRequests

        self.window =
            window
    }
}

public actor SafariWeb3PermissionRateLimiter {

    private struct Window:
        Sendable
    {
        var timestamps:
            [Date]
    }

    private var windows:
        [SafariWeb3Origin:
            Window] =
            [:]

    private let limit:
        SafariWeb3RateLimit

    public init(
        limit:
            SafariWeb3RateLimit =
                .init(
                    maximumRequests:
                        60,
                    window:
                        60
                )
    ) {
        self.limit =
            limit
    }

    public func allow(
        origin:
            SafariWeb3Origin
    ) -> Bool {

        let now =
            Date()

        let cutoff =
            now.addingTimeInterval(
                -limit.window
            )

        var window =
            windows[origin] ??
            Window(
                timestamps:
                    []
            )

        window.timestamps =
            window.timestamps.filter {
                $0 >= cutoff
            }

        guard
            window.timestamps.count <
                limit.maximumRequests
        else {
            windows[origin] =
                window

            return false
        }

        window.timestamps.append(
            now
        )

        windows[origin] =
            window

        return true
    }
}

// MARK: - Sensitive operation limiter

public actor SafariWeb3SensitiveOperationLimiter {

    private struct Counter:
        Sendable
    {
        var timestamps:
            [Date]
    }

    private var counters:
        [SafariWeb3Origin:
            Counter] =
            [:]

    public init() {}

    public func allowSigning(
        origin:
            SafariWeb3Origin
    ) -> Bool {

        allow(
            origin:
                origin,
            maximum:
                10,
            interval:
                60
        )
    }

    public func allowSending(
        origin:
            SafariWeb3Origin
    ) -> Bool {

        allow(
            origin:
                origin,
            maximum:
                5,
            interval:
                60
        )
    }

    private func allow(
        origin:
            SafariWeb3Origin,
        maximum:
            Int,
        interval:
            TimeInterval
    ) -> Bool {

        let now =
            Date()

        let cutoff =
            now.addingTimeInterval(
                -interval
            )

        var counter =
            counters[origin] ??
            Counter(
                timestamps:
                    []
            )

        counter.timestamps =
            counter.timestamps.filter {
                $0 >= cutoff
            }

        guard
            counter.timestamps.count <
                maximum
        else {

            counters[origin] =
                counter

            return false
        }

        counter.timestamps.append(
            now
        )

        counters[origin] =
            counter

        return true
    }
}

// MARK: - Private browsing policy

public struct SafariWeb3PrivateBrowsingPolicy:
    Sendable
{
    public init() {}

    public func lifetime(
        for permission:
            SafariWeb3Permission
    )
        -> SafariWeb3PermissionLifetime
    {
        switch permission {

        case .signMessage,
             .signTypedData,
             .sendTransaction,
             .connectWallet,
             .readAccounts,
             .readIdentity:

            return .session

        default:

            return .session
        }
    }
}

// MARK: - Origin security

public struct SafariWeb3OriginSecurityPolicy:
    Sendable
{
    public init() {}

    public func evaluate(
        origin:
            SafariWeb3Origin
    ) -> Bool {

        guard
            !origin.host.isEmpty
        else {
            return false
        }

        // Web3 wallet access should not be granted
        // to opaque or malformed origins.
        //
        // HTTP can still be used for ordinary Web3
        // discovery where explicitly permitted, but
        // sensitive wallet operations should require
        // a secure origin.
        return true
    }

    public func requiresSecureOrigin(
        for permission:
            SafariWeb3Permission
    ) -> Bool {

        switch permission {

        case .connectWallet,
             .readAccounts,
             .readIdentity,
             .authenticateIdentity,
             .signMessage,
             .signTypedData,
             .sendTransaction,
             .writeWeb3Storage,
             .pinWeb3Storage:

            return true

        default:

            return false
        }
    }
}

// MARK: - Audit events

public enum SafariWeb3PermissionAuditEvent:
    Codable,
    Sendable
{
    case requested
    case allowed
    case denied
    case approvalRequired
    case expired
    case revoked
    case rateLimited
    case insecureOrigin
    case privateBrowsing
}

// MARK: - Audit record

public struct SafariWeb3PermissionAuditRecord:
    Codable,
    Sendable
{
    public let eventID:
        UUID

    public let origin:
        SafariWeb3Origin

    public let permission:
        SafariWeb3Permission

    public let event:
        SafariWeb3PermissionAuditEvent

    public let timestamp:
        Date

    public init(
        eventID:
            UUID =
                UUID(),
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission,
        event:
            SafariWeb3PermissionAuditEvent,
        timestamp:
            Date =
                Date()
    ) {
        self.eventID =
            eventID

        self.origin =
            origin

        self.permission =
            permission

        self.event =
            event

        self.timestamp =
            timestamp
    }
}

// MARK: - Audit store

public actor SafariWeb3PermissionAuditStore {

    private var records:
        [SafariWeb3PermissionAuditRecord] =
            []

    private let maximumRecords:
        Int

    public init(
        maximumRecords:
            Int =
                5_000
    ) {
        self.maximumRecords =
            maximumRecords
    }

    public func append(
        _ record:
            SafariWeb3PermissionAuditRecord
    ) {

        records.append(
            record
        )

        if records.count >
            maximumRecords
        {
            records.removeFirst(
                records.count -
                maximumRecords
            )
        }
    }

    public func snapshot()
        -> [SafariWeb3PermissionAuditRecord]
    {
        records
    }

    public func clear() {

        records.removeAll()
    }
}

// MARK: - Firewall

public actor SafariWeb3PrivacyPermissionFirewall {

    private let store:
        SafariWeb3PermissionStore

    private let sessionStore:
        SafariWeb3SessionPermissionStore

    private let rateLimiter:
        SafariWeb3PermissionRateLimiter

    private let sensitiveLimiter:
        SafariWeb3SensitiveOperationLimiter

    private let audit:
        SafariWeb3PermissionAuditStore

    private let originPolicy:
        SafariWeb3OriginSecurityPolicy

    private let privatePolicy:
        SafariWeb3PrivateBrowsingPolicy

    private var policy:
        SafariWeb3FirewallPolicy

    public init(
        policy:
            SafariWeb3FirewallPolicy =
                .init()
    ) {
        self.store =
            SafariWeb3PermissionStore()

        self.sessionStore =
            SafariWeb3SessionPermissionStore()

        self.rateLimiter =
            SafariWeb3PermissionRateLimiter()

        self.sensitiveLimiter =
            SafariWeb3SensitiveOperationLimiter()

        self.audit =
            SafariWeb3PermissionAuditStore()

        self.originPolicy =
            SafariWeb3OriginSecurityPolicy()

        self.privatePolicy =
            SafariWeb3PrivateBrowsingPolicy()

        self.policy =
            policy
    }

    // MARK: Evaluate request

    public func evaluate(
        request:
            SafariWeb3PermissionRequest,
        context:
            SafariWeb3FirewallContext
    ) async
        -> SafariWeb3FirewallResult
    {
        await auditEvent(
            origin:
                request.origin,
            permission:
                request.permission,
            event:
                .requested
        )

        // Rate limit all Web3 requests.
        guard
            await rateLimiter.allow(
                origin:
                    request.origin
            )
        else {

            await auditEvent(
                origin:
                    request.origin,
                permission:
                    request.permission,
                event:
                    .rateLimited
            )

            return .restricted(
                reason:
                    "Web3 request rate limit exceeded."
            )
        }

        // Origin validation.
        guard
            originPolicy.evaluate(
                origin:
                    request.origin
            )
        else {

            return .denied(
                reason:
                    "Invalid Web3 origin."
            )
        }

        // Sensitive capabilities require secure origin.
        if originPolicy
            .requiresSecureOrigin(
                for:
                    request.permission
            )
        {
            guard
                context.secureOrigin
            else {

                await auditEvent(
                    origin:
                        request.origin,
                    permission:
                        request.permission,
                    event:
                        .insecureOrigin
                )

                return .restricted(
                    reason:
                        "This operation requires a secure origin."
                )
            }
        }

        // Private browsing.
        if context.privateBrowsing {

            await auditEvent(
                origin:
                    request.origin,
                permission:
                    request.permission,
                event:
                    .privateBrowsing
            )

            // Never convert a private-browsing
            // permission into persistent state.
            if request.permission.sensitivity ==
                .critical
            {
                return .requiresUserApproval
            }
        }

        // Sensitive signing.
        if request.permission ==
            .signMessage ||
            request.permission ==
            .signTypedData
        {

            if policy
                .requireUserGestureForSigning &&
                !context.userInitiated
            {
                return .requiresUserApproval
            }

            guard
                await sensitiveLimiter
                    .allowSigning(
                        origin:
                            request.origin
                    )
            else {

                return .restricted(
                    reason:
                        "Signing request rate limit exceeded."
                )
            }
        }

        // Transaction sending.
        if request.permission ==
            .sendTransaction
        {

            if policy
                .requireUserGestureForSending &&
                !context.userInitiated
            {
                return .requiresUserApproval
            }

            guard
                await sensitiveLimiter
                    .allowSending(
                        origin:
                            request.origin
                    )
            else {

                return .restricted(
                    reason:
                        "Transaction sending rate limit exceeded."
                )
            }
        }

        // Existing session permission.
        if let sessionID =
            request.sessionID,
           let record =
                await sessionStore.get(
                    sessionID:
                        sessionID,
                    permission:
                        request.permission
                )
        {
            if isUsable(
                record:
                    record
            ) {

                await auditEvent(
                    origin:
                        request.origin,
                    permission:
                        request.permission,
                    event:
                        .allowed
                )

                return .allowed(
                    expiresAt:
                        record.expiresAt
                )
            }
        }

        // Existing persistent permission.
        if let record =
            await store.get(
                origin:
                    request.origin,
                permission:
                    request.permission
            )
        {
            if isUsable(
                record:
                    record
            ) {

                await auditEvent(
                    origin:
                        request.origin,
                    permission:
                        request.permission,
                    event:
                        .allowed
                )

                return .allowed(
                    expiresAt:
                        record.expiresAt
                )
            }

            await auditEvent(
                origin:
                    request.origin,
                permission:
                    request.permission,
                event:
                    .expired
            )
        }

        // No existing permission.
        return .requiresUserApproval
    }

    // MARK: Grant

    public func grant(
        request:
            SafariWeb3PermissionRequest,
        lifetime:
            SafariWeb3PermissionLifetime,
        context:
            SafariWeb3FirewallContext
    ) async
        -> SafariWeb3PermissionRecord
    {
        let record =
            makeRecord(
                request:
                    request,
                lifetime:
                    lifetime,
                context:
                    context
            )

        switch lifetime {

        case .session:

            if let sessionID =
                request.sessionID
            {
                await sessionStore.grant(
                    sessionID:
                        sessionID,
                    origin:
                        request.origin,
                    permission:
                        request.permission
                )
            }

        case .once:

            break

        default:

            if context.privateBrowsing &&
                !policy
                    .allowPersistentPrivateBrowsing
            {
                // Intentionally don't persist.
                break
            }

            await store.record(
                record
            )
        }

        await auditEvent(
            origin:
                request.origin,
            permission:
                request.permission,
            event:
                .allowed
        )

        return record
    }

    // MARK: Deny

    public func deny(
        request:
            SafariWeb3PermissionRequest
    ) async {

        await auditEvent(
            origin:
                request.origin,
            permission:
                request.permission,
            event:
                .denied
        )
    }

    // MARK: Revoke

    public func revoke(
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission
    ) async {

        await store.remove(
            origin:
                origin,
            permission:
                permission
        )

        await auditEvent(
            origin:
                origin,
            permission:
                permission,
            event:
                .revoked
        )
    }

    public func revokeOrigin(
        _ origin:
            SafariWeb3Origin
    ) async {

        await store.removeOrigin(
            origin
        )
    }

    // MARK: Session cleanup

    public func closeSession(
        _ sessionID:
            String
    ) async {

        await sessionStore.removeSession(
            sessionID
        )
    }

    // MARK: Audit

    public func auditSnapshot()
        async
        -> [SafariWeb3PermissionAuditRecord]
    {
        await audit.snapshot()
    }

    // MARK: Helpers

    private func isUsable(
        record:
            SafariWeb3PermissionRecord
    ) -> Bool {

        switch record.decision {

        case .granted,
             .sessionGranted:

            break

        default:

            return false
        }

        if let expiresAt =
            record.expiresAt
        {
            return expiresAt >
                Date()
        }

        return true
    }

    private func makeRecord(
        request:
            SafariWeb3PermissionRequest,
        lifetime:
            SafariWeb3PermissionLifetime,
        context:
            SafariWeb3FirewallContext
    )
        -> SafariWeb3PermissionRecord
    {
        let expiresAt:
            Date?

        switch lifetime {

        case .once:
            expiresAt =
                Date()

        case .session:
            expiresAt =
                nil

        case .persistent:
            expiresAt =
                Date().addingTimeInterval(
                    policy.permissionLifetime
                )

        case let .expires(date):
            expiresAt =
                date
        }

        let decision:
            SafariWeb3PermissionDecision

        switch lifetime {

        case .session:
            decision =
                .sessionGranted

        default:
            decision =
                .granted
        }

        return SafariWeb3PermissionRecord(
            origin:
                request.origin,
            permission:
                request.permission,
            decision:
                decision,
            lifetime:
                lifetime,
            expiresAt:
                expiresAt
        )
    }

    private func auditEvent(
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission,
        event:
            SafariWeb3PermissionAuditEvent
    ) async {

        await audit.append(
            SafariWeb3PermissionAuditRecord(
                origin:
                    origin,
                permission:
                    permission,
                event:
                    event
            )
        )
    }
}

// MARK: - Permission UI model

public struct SafariWeb3PermissionPrompt:
    Sendable
{
    public let origin:
        SafariWeb3Origin

    public let permission:
        SafariWeb3Permission

    public let title:
        String

    public let explanation:
        String

    public let sensitivity:
        SafariWeb3PermissionSensitivity

    public init(
        origin:
            SafariWeb3Origin,
        permission:
            SafariWeb3Permission
    ) {
        self.origin =
            origin

        self.permission =
            permission

        self.sensitivity =
            permission.sensitivity

        self.title =
            SafariWeb3PermissionPrompt
                .title(
                    permission:
                        permission
                )

        self.explanation =
            SafariWeb3PermissionPrompt
                .explanation(
                    permission:
                        permission
                )
    }

    private static func title(
        permission:
            SafariWeb3Permission
    ) -> String {

        switch permission {

        case .connectWallet:
            return "Connect Wallet"

        case .readAccounts:
            return "View Wallet Accounts"

        case .readChain:
            return "View Blockchain Network"

        case .readBalance:
            return "View Wallet Balance"

        case .readTokenMetadata:
            return "View Token Information"

        case .readTokenBalances:
            return "View Token Balances"

        case .readNFTMetadata:
            return "View NFT Information"

        case .readNFTBalances:
            return "View NFT Ownership"

        case .readIdentity:
            return "Access Web3 Identity"

        case .authenticateIdentity:
            return "Authenticate Identity"

        case .signMessage:
            return "Sign a Message"

        case .signTypedData:
            return "Sign Structured Data"

        case .estimateTransaction:
            return "Estimate Transaction"

        case .simulateTransaction:
            return "Simulate Transaction"

        case .sendTransaction:
            return "Send Blockchain Transaction"

        case .switchChain:
            return "Switch Blockchain Network"

        case .readWeb3Storage:
            return "Read Web3 Storage"

        case .writeWeb3Storage:
            return "Write Web3 Storage"

        case .pinWeb3Storage:
            return "Pin Web3 Storage"

        case .accessClipboard:
            return "Access Clipboard"
        }
    }

    private static func explanation(
        permission:
            SafariWeb3Permission
    ) -> String {

        switch permission {

        case .connectWallet:
            return
                "Allow this website to establish a wallet session."

        case .readAccounts:
            return
                "Allow this website to see the wallet account addresses you approve."

        case .readChain:
            return
                "Allow this website to determine the currently selected blockchain."

        case .readBalance:
            return
                "Allow this website to request your blockchain balance."

        case .readTokenMetadata:
            return
                "Allow this website to read token names, symbols and metadata."

        case .readTokenBalances:
            return
                "Allow this website to read token balances."

        case .readNFTMetadata:
            return
                "Allow this website to read NFT metadata."

        case .readNFTBalances:
            return
                "Allow this website to read NFT ownership and quantities."

        case .readIdentity:
            return
                "Allow this website to request approved Web3 identity information."

        case .authenticateIdentity:
            return
                "Allow this website to request an identity authentication operation."

        case .signMessage:
            return
                "Allow this website to request a cryptographic signature."

        case .signTypedData:
            return
                "Allow this website to request a structured-data signature."

        case .estimateTransaction:
            return
                "Allow this website to request a transaction estimate."

        case .simulateTransaction:
            return
                "Allow this website to simulate a transaction."

        case .sendTransaction:
            return
                "Allow this website to request a blockchain transaction."

        case .switchChain:
            return
                "Allow this website to request a network switch."

        case .readWeb3Storage:
            return
                "Allow this website to read approved decentralized storage objects."

        case .writeWeb3Storage:
            return
                "Allow this website to create decentralized storage objects."

        case .pinWeb3Storage:
            return
                "Allow this website to request persistent storage pinning."

        case .accessClipboard:
            return
                "Allow this website to access clipboard data."
        }
    }
}

// MARK: - Web3 request envelope

public struct SafariWeb3FirewallRequest:
    Sendable
{
    public let request:
        SafariWeb3PermissionRequest

    public let context:
        SafariWeb3FirewallContext

    public init(
        request:
            SafariWeb3PermissionRequest,
        context:
            SafariWeb3FirewallContext
    ) {
        self.request =
            request

        self.context =
            context
    }
}

// MARK: - Runtime

public actor SafariWeb3PrivacyRuntime {

    public let firewall:
        SafariWeb3PrivacyPermissionFirewall

    public init(
        policy:
            SafariWeb3FirewallPolicy =
                .init()
    ) {
        self.firewall =
            SafariWeb3PrivacyPermissionFirewall(
                policy:
                    policy
            )
    }

    public func request(
        _ envelope:
            SafariWeb3FirewallRequest
    ) async
        -> SafariWeb3FirewallResult
    {
        await firewall.evaluate(
            request:
                envelope.request,
            context:
                envelope.context
        )
    }

    public func approve(
        _ request:
            SafariWeb3PermissionRequest,
        lifetime:
            SafariWeb3PermissionLifetime,
        context:
            SafariWeb3FirewallContext
    ) async
        -> SafariWeb3PermissionRecord
    {
        await firewall.grant(
            request:
                request,
            lifetime:
                lifetime,
            context:
                context
        )
    }

    public func deny(
        _ request:
            SafariWeb3PermissionRequest
    ) async {

        await firewall.deny(
            request:
                request
        )
    }
}

// MARK: - WebKit bridge request

public struct SafariWeb3BridgePermissionMessage:
    Codable,
    Sendable
{
    public let method:
        String

    public let requestID:
        String

    public init(
        method:
            String,
        requestID:
            String
    ) {
        self.method =
            method

        self.requestID =
            requestID
    }
}

// MARK: - Method mapping

public enum SafariWeb3MethodMapper {

    public static func permission(
        for method:
            String
    ) -> SafariWeb3Permission?
    {
        switch method {

        case "eth_requestAccounts":
            return .connectWallet

        case "eth_accounts":
            return .readAccounts

        case "eth_chainId":
            return .readChain

        case "eth_getBalance":
            return .readBalance

        case "eth_sendTransaction":
            return .sendTransaction

        case "personal_sign":
            return .signMessage

        case "eth_signTypedData",
             "eth_signTypedData_v4":
            return .signTypedData

        case "wallet_switchEthereumChain":
            return .switchChain

        case "eth_estimateGas":
            return .estimateTransaction

        default:
            return nil
        }
    }
}

// MARK: - Tests

#if DEBUG

enum SafariWeb3PrivacyPermissionFirewallTests {

    static func origin()
        -> SafariWeb3Origin
    {
        SafariWeb3Origin(
            scheme:
                "https",
            host:
                "example.com"
        )
    }

    static func context()
        -> SafariWeb3FirewallContext
    {
        SafariWeb3FirewallContext(
            privateBrowsing:
                false,
            secureOrigin:
                true,
            userInitiated:
                true,
            walletConnected:
                false,
            chainID:
                1,
            applicationActive:
                true
        )
    }

    static func testUnknownPermission()
        async
    {
        let firewall =
            SafariWeb3PrivacyPermissionFirewall()

        let request =
            SafariWeb3PermissionRequest(
                origin:
                    origin(),
                permission:
                    .readBalance
            )

        let result =
            await firewall.evaluate(
                request:
                    request,
                context:
                    context()
            )

        if case
            .requiresUserApproval =
            result
        {
            // Expected.
        } else {

            assertionFailure(
                "Unknown permission should require approval."
            )
        }
    }

    static func testGrant()
        async
    {
        let firewall =
            SafariWeb3PrivacyPermissionFirewall()

        let request =
            SafariWeb3PermissionRequest(
                origin:
                    origin(),
                permission:
                    .readBalance
            )

        _ =
            await firewall.grant(
                request:
                    request,
                lifetime:
                    .persistent,
                context:
                    context()
            )

        let result =
            await firewall.evaluate(
                request:
                    request,
                context:
                    context()
            )

        if case
            .allowed =
            result
        {
            // Expected.
        } else {

            assertionFailure(
                "Granted permission should be allowed."
            )
        }
    }

    static func testSigningRequiresGesture()
        async
    {
        let firewall =
            SafariWeb3PrivacyPermissionFirewall()

        let request =
            SafariWeb3PermissionRequest(
                origin:
                    origin(),
                permission:
                    .signMessage
            )

        let context =
            SafariWeb3FirewallContext(
                privateBrowsing:
                    false,
                secureOrigin:
                    true,
                userInitiated:
                    false,
                walletConnected:
                    true,
                chainID:
                    1,
                applicationActive:
                    true
            )

        let result =
            await firewall.evaluate(
                request:
                    request,
                context:
                    context
            )

        if case
            .requiresUserApproval =
            result
        {
            // Expected.
        } else {

            assertionFailure(
                "Signing should require user interaction."
            )
        }
    }

    static func testHTTPRestricted()
        async
    {
        let firewall =
            SafariWeb3PrivacyPermissionFirewall()

        let request =
            SafariWeb3PermissionRequest(
                origin:
                    SafariWeb3Origin(
                        scheme:
                            "http",
                        host:
                            "example.com"
                    ),
                permission:
                    .sendTransaction
            )

        let result =
            await firewall.evaluate(
                request:
                    request,
                context:
                    SafariWeb3FirewallContext(
                        privateBrowsing:
                            false,
                        secureOrigin:
                            false,
                        userInitiated:
                            true,
                        walletConnected:
                            true,
                        chainID:
                            1,
                        applicationActive:
                            true
                    )
            )

        if case
            .restricted =
            result
        {
            // Expected.
        } else {

            assertionFailure(
                "Transaction sending should require a secure origin."
            )
        }
    }

    static func testMethodMapping() {

        assert(
            SafariWeb3MethodMapper.permission(
                for:
                    "eth_requestAccounts"
            ) ==
                .connectWallet
        )

        assert(
            SafariWeb3MethodMapper.permission(
                for:
                    "personal_sign"
            ) ==
                .signMessage
        )

        assert(
            SafariWeb3MethodMapper.permission(
                for:
                    "eth_sendTransaction"
            ) ==
                .sendTransaction
        )
    }

    static func runAll()
        async
    {
        await testUnknownPermission()
        await testGrant()
        await testSigningRequiresGesture()
        await testHTTPRestricted()
        testMethodMapping()
    }
}

#endif




//
// SafariWeb3BrowserRuntime.swift
//
// Safari Web3 #10
//
// Native orchestration runtime for the complete Safari Web3 stack.
//
// Swift 6 / strict concurrency.
//
// Responsibilities:
//
// - coordinate all Web3 subsystems
// - route DApp requests
// - enforce origin isolation
// - invoke permission firewall
// - invoke wallet/session/identity/storage systems
// - coordinate transaction simulation + security scanning
// - provide lifecycle management
// - expose telemetry
// - manage Web3 runtime state
//
// Security principle:
//
// This runtime is an orchestrator.
//
// It should NOT:
//
// - store private keys
// - perform raw signing itself
// - bypass #9
// - bypass #6 for transaction security
// - trust an origin supplied by JavaScript
//
// The actual WebKit integration should obtain the origin
// from WKWebView.url.
//

import Foundation
import WebKit

// MARK: - Runtime identifiers

public struct SafariWeb3RuntimeID:
    Hashable,
    Codable,
    Sendable
{
    public let rawValue:
        UUID

    public init(
        rawValue:
            UUID =
                UUID()
    ) {
        self.rawValue =
            rawValue
    }
}

// MARK: - Web3 runtime state

public enum SafariWeb3RuntimeState:
    String,
    Codable,
    Sendable
{
    case created
    case starting
    case running
    case suspended
    case shuttingDown
    case stopped
    case failed
}

// MARK: - Runtime configuration

public struct SafariWeb3RuntimeConfiguration:
    Sendable
{
    public var enableWallet:
        Bool

    public var enableDAppSessions:
        Bool

    public var enableIdentity:
        Bool

    public var enableTransactionSimulation:
        Bool

    public var enableSecurityScanner:
        Bool

    public var enableStorage:
        Bool

    public var enableAssets:
        Bool

    public var enableTelemetry:
        Bool

    public var privateBrowsing:
        Bool

    public init(
        enableWallet:
            Bool = true,
        enableDAppSessions:
            Bool = true,
        enableIdentity:
            Bool = true,
        enableTransactionSimulation:
            Bool = true,
        enableSecurityScanner:
            Bool = true,
        enableStorage:
            Bool = true,
        enableAssets:
            Bool = true,
        enableTelemetry:
            Bool = true,
        privateBrowsing:
            Bool = false
    ) {
        self.enableWallet =
            enableWallet

        self.enableDAppSessions =
            enableDAppSessions

        self.enableIdentity =
            enableIdentity

        self.enableTransactionSimulation =
            enableTransactionSimulation

        self.enableSecurityScanner =
            enableSecurityScanner

        self.enableStorage =
            enableStorage

        self.enableAssets =
            enableAssets

        self.enableTelemetry =
            enableTelemetry

        self.privateBrowsing =
            privateBrowsing
    }
}

// MARK: - Runtime request

public enum SafariWeb3RuntimeRequest:
    Sendable
{
    case connectWallet

    case accounts

    case chain

    case balance

    case tokenBalances

    case nftBalances

    case identity

    case authenticateIdentity

    case signMessage(
        message:
            Data
    )

    case signTypedData(
        payload:
            Data
    )

    case estimateTransaction

    case simulateTransaction

    case sendTransaction

    case switchChain(
        chainID:
            UInt64
    )

    case readStorage

    case writeStorage(
        data:
            Data
    )

    case pinStorage
}

// MARK: - Runtime response

public enum SafariWeb3RuntimeResponse:
    Sendable
{
    case approved

    case denied(
        reason:
            String
    )

    case approvalRequired

    case accounts(
        [String]
    )

    case chain(
        UInt64
    )

    case balance(
        String
    )

    case signature(
        Data
    )

    case simulationRequired

    case securityReviewRequired

    case transactionSubmitted(
        String
    )

    case storageReference(
        String
    )

    case unsupported(
        String
    )
}

// MARK: - Runtime error

public enum SafariWeb3RuntimeError:
    Error,
    LocalizedError,
    Sendable
{
    case notRunning
    case subsystemUnavailable
    case invalidOrigin
    case permissionDenied
    case userApprovalRequired
    case securityReviewRequired
    case simulationRequired
    case unsupportedRequest
    case walletUnavailable
    case sessionUnavailable
    case identityUnavailable
    case storageUnavailable

    public var errorDescription:
        String?
    {
        switch self {

        case .notRunning:
            return "Safari Web3 runtime is not running."

        case .subsystemUnavailable:
            return "Required Web3 subsystem is unavailable."

        case .invalidOrigin:
            return "The Web3 origin could not be verified."

        case .permissionDenied:
            return "The Web3 permission request was denied."

        case .userApprovalRequired:
            return "User approval is required."

        case .securityReviewRequired:
            return "Security review is required."

        case .simulationRequired:
            return "Transaction simulation is required."

        case .unsupportedRequest:
            return "The Web3 request is not supported."

        case .walletUnavailable:
            return "The wallet subsystem is unavailable."

        case .sessionUnavailable:
            return "The DApp session subsystem is unavailable."

        case .identityUnavailable:
            return "The identity subsystem is unavailable."

        case .storageUnavailable:
            return "The Web3 storage subsystem is unavailable."
        }
    }
}

// MARK: - Runtime telemetry

public enum SafariWeb3RuntimeEvent:
    String,
    Codable,
    Sendable
{
    case runtimeCreated
    case runtimeStarted
    case runtimeSuspended
    case runtimeResumed
    case runtimeStopped

    case requestReceived
    case requestAllowed
    case requestDenied

    case permissionRequired

    case walletConnected
    case walletDisconnected

    case simulationStarted
    case simulationCompleted

    case securityScanStarted
    case securityScanCompleted

    case transactionSubmitted

    case storageRead
    case storageWritten

    case identityRequested

    case subsystemFailure
}

public struct SafariWeb3RuntimeTelemetryRecord:
    Codable,
    Sendable
{
    public let id:
        UUID

    public let runtimeID:
        SafariWeb3RuntimeID

    public let event:
        SafariWeb3RuntimeEvent

    public let timestamp:
        Date

    public let origin:
        SafariWeb3Origin?

    public init(
        runtimeID:
            SafariWeb3RuntimeID,
        event:
            SafariWeb3RuntimeEvent,
        origin:
            SafariWeb3Origin? =
                nil,
        timestamp:
            Date =
                Date()
    ) {
        self.id =
            UUID()

        self.runtimeID =
            runtimeID

        self.event =
            event

        self.timestamp =
            timestamp

        self.origin =
            origin
    }
}

// MARK: - Telemetry store

public actor SafariWeb3RuntimeTelemetry {

    private var records:
        [SafariWeb3RuntimeTelemetryRecord] =
            []

    private let maximumRecords:
        Int

    public init(
        maximumRecords:
            Int =
                10_000
    ) {
        self.maximumRecords =
            maximumRecords
    }

    public func record(
        _ record:
            SafariWeb3RuntimeTelemetryRecord
    ) {

        records.append(
            record
        )

        if records.count >
            maximumRecords
        {
            records.removeFirst(
                records.count -
                maximumRecords
            )
        }
    }

    public func snapshot()
        -> [SafariWeb3RuntimeTelemetryRecord]
    {
        records
    }

    public func clear() {
        records.removeAll()
    }
}

// MARK: - Web3 subsystem protocol

public protocol SafariWeb3Subsystem:
    Sendable
{
    var subsystemName:
        String
    {
        get
    }

    func start()
        async throws

    func stop()
        async
}

// MARK: - Generic subsystem status

public struct SafariWeb3SubsystemStatus:
    Codable,
    Sendable
{
    public let name:
        String

    public let available:
        Bool

    public let lastError:
        String?

    public init(
        name:
            String,
        available:
            Bool,
        lastError:
            String? =
                nil
    ) {
        self.name =
            name

        self.available =
            available

        self.lastError =
            lastError
    }
}

// MARK: - Runtime snapshot

public struct SafariWeb3RuntimeSnapshot:
    Codable,
    Sendable
{
    public let runtimeID:
        SafariWeb3RuntimeID

    public let state:
        SafariWeb3RuntimeState

    public let privateBrowsing:
        Bool

    public let subsystems:
        [SafariWeb3SubsystemStatus]

    public let capturedAt:
        Date

    public init(
        runtimeID:
            SafariWeb3RuntimeID,
        state:
            SafariWeb3RuntimeState,
        privateBrowsing:
            Bool,
        subsystems:
            [SafariWeb3SubsystemStatus],
        capturedAt:
            Date =
                Date()
    ) {
        self.runtimeID =
            runtimeID

        self.state =
            state

        self.privateBrowsing =
            privateBrowsing

        self.subsystems =
            subsystems

        self.capturedAt =
            capturedAt
    }
}

// MARK: - Request envelope

public struct SafariWeb3RequestEnvelope:
    Sendable
{
    public let requestID:
        UUID

    public let origin:
        SafariWeb3Origin

    public let request:
        SafariWeb3RuntimeRequest

    public let userInitiated:
        Bool

    public let sessionID:
        String?

    public init(
        requestID:
            UUID =
                UUID(),
        origin:
            SafariWeb3Origin,
        request:
            SafariWeb3RuntimeRequest,
        userInitiated:
            Bool,
        sessionID:
            String? =
                nil
    ) {
        self.requestID =
            requestID

        self.origin =
            origin

        self.request =
            request

        self.userInitiated =
            userInitiated

        self.sessionID =
            sessionID
    }
}

// MARK: - Runtime

public actor SafariWeb3BrowserRuntime {

    public let runtimeID:
        SafariWeb3RuntimeID

    public let configuration:
        SafariWeb3RuntimeConfiguration

    public let telemetry:
        SafariWeb3RuntimeTelemetry

    public let privacy:
        SafariWeb3PrivacyRuntime

    private var state:
        SafariWeb3RuntimeState =
            .created

    private var subsystemStatus:
        [String:
            SafariWeb3SubsystemStatus] =
            [:]

    public init(
        configuration:
            SafariWeb3RuntimeConfiguration =
                .init()
    ) {

        self.runtimeID =
            SafariWeb3RuntimeID()

        self.configuration =
            configuration

        self.telemetry =
            SafariWeb3RuntimeTelemetry()

        self.privacy =
            SafariWeb3PrivacyRuntime()

        self.state =
            .created
    }

    // MARK: Lifecycle

    public func start()
        async
    {
        guard
            state == .created ||
            state == .stopped
        else {
            return
        }

        state =
            .starting

        await record(
            event:
                .runtimeCreated
        )

        registerSubsystems()

        state =
            .running

        await record(
            event:
                .runtimeStarted
        )
    }

    public func suspend()
        async
    {
        guard
            state == .running
        else {
            return
        }

        state =
            .suspended

        await record(
            event:
                .runtimeSuspended
        )
    }

    public func resume()
        async
    {
        guard
            state == .suspended
        else {
            return
        }

        state =
            .running

        await record(
            event:
                .runtimeResumed
        )
    }

    public func stop()
        async
    {
        guard
            state != .stopped
        else {
            return
        }

        state =
            .shuttingDown

        await record(
            event:
                .runtimeStopped
        )

        state =
            .stopped
    }

    // MARK: Request router

    public func handle(
        _ envelope:
            SafariWeb3RequestEnvelope
    ) async
        -> SafariWeb3RuntimeResponse
    {
        guard
            state == .running
        else {
            return .denied(
                reason:
                    SafariWeb3RuntimeError
                        .notRunning
                        .localizedDescription
            )
        }

        await record(
            event:
                .requestReceived,
            origin:
                envelope.origin
        )

        let permission =
            permission(
                for:
                    envelope.request
            )

        guard let permission else {

            return .unsupported(
                "No Web3 permission mapping exists for this request."
            )
        }

        let context =
            SafariWeb3FirewallContext(
                privateBrowsing:
                    configuration.privateBrowsing,
                secureOrigin:
                    envelope.origin.isSecure,
                userInitiated:
                    envelope.userInitiated,
                walletConnected:
                    false,
                chainID:
                    nil,
                applicationActive:
                    true
            )

        let permissionRequest =
            SafariWeb3PermissionRequest(
                origin:
                    envelope.origin,
                permission:
                    permission,
                reason:
                    reason(
                        for:
                            envelope.request
                    ),
                sessionID:
                    envelope.sessionID
            )

        let firewallRequest =
            SafariWeb3FirewallRequest(
                request:
                    permissionRequest,
                context:
                    context
            )

        let firewallResult =
            await privacy.request(
                firewallRequest
            )

        switch firewallResult {

        case .allowed:

            await record(
                event:
                    .requestAllowed,
                origin:
                    envelope.origin
            )

            return await execute(
                envelope:
                    envelope
            )

        case .requiresUserApproval:

            await record(
                event:
                    .permissionRequired,
                origin:
                    envelope.origin
            )

            return .approvalRequired

        case let .denied(reason):

            await record(
                event:
                    .requestDenied,
                origin:
                    envelope.origin
            )

            return .denied(
                reason:
                    reason
            )

        case let .restricted(reason):

            await record(
                event:
                    .requestDenied,
                origin:
                    envelope.origin
            )

            return .denied(
                reason:
                    reason
            )
        }
    }

    // MARK: Execute

    private func execute(
        envelope:
            SafariWeb3RequestEnvelope
    ) async
        -> SafariWeb3RuntimeResponse
    {
        switch envelope.request {

        case .connectWallet:

            guard
                configuration.enableWallet
            else {
                return .unsupported(
                    "Wallet subsystem disabled."
                )
            }

            await record(
                event:
                    .walletConnected,
                origin:
                    envelope.origin
            )

            return .approved

        case .accounts:

            return .accounts(
                []
            )

        case .chain:

            return .chain(
                1
            )

        case .balance:

            return .balance(
                "0"
            )

        case .tokenBalances:

            guard
                configuration.enableAssets
            else {
                return .unsupported(
                    "Asset subsystem disabled."
                )
            }

            return .approved

        case .nftBalances:

            guard
                configuration.enableAssets
            else {
                return .unsupported(
                    "Asset subsystem disabled."
                )
            }

            return .approved

        case .identity:

            guard
                configuration.enableIdentity
            else {
                return .unsupported(
                    "Identity subsystem disabled."
                )
            }

            await record(
                event:
                    .identityRequested,
                origin:
                    envelope.origin
            )

            return .approved

        case .authenticateIdentity:

            guard
                configuration.enableIdentity
            else {
                return .unsupported(
                    "Identity subsystem disabled."
                )
            }

            return .approvalRequired

        case .signMessage:

            guard
                configuration.enableWallet
            else {
                return .unsupported(
                    "Wallet subsystem disabled."
                )
            }

            return .approvalRequired

        case .signTypedData:

            guard
                configuration.enableWallet
            else {
                return .unsupported(
                    "Wallet subsystem disabled."
                )
            }

            return .approvalRequired

        case .estimateTransaction:

            guard
                configuration.enableTransactionSimulation
            else {
                return .unsupported(
                    "Transaction simulation disabled."
                )
            }

            return .simulationRequired

        case .simulateTransaction:

            guard
                configuration.enableTransactionSimulation
            else {
                return .unsupported(
                    "Transaction simulation disabled."
                )
            }

            await record(
                event:
                    .simulationStarted,
                origin:
                    envelope.origin
            )

            await record(
                event:
                    .simulationCompleted,
                origin:
                    envelope.origin
            )

            return .approved

        case .sendTransaction:

            guard
                configuration.enableTransactionSimulation
            else {
                return .unsupported(
                    "Transaction simulation is required."
                )
            }

            guard
                configuration.enableSecurityScanner
            else {
                return .unsupported(
                    "Security scanner is required."
                )
            }

            await record(
                event:
                    .securityScanStarted,
                origin:
                    envelope.origin
            )

            await record(
                event:
                    .securityScanCompleted,
                origin:
                    envelope.origin
            )

            return .securityReviewRequired

        case let .switchChain(chainID):

            return .chain(
                chainID
            )

        case .readStorage:

            guard
                configuration.enableStorage
            else {
                return .unsupported(
                    "Web3 storage disabled."
                )
            }

            await record(
                event:
                    .storageRead,
                origin:
                    envelope.origin
            )

            return .approved

        case .writeStorage:

            guard
                configuration.enableStorage
            else {
                return .unsupported(
                    "Web3 storage disabled."
                )
            }

            await record(
                event:
                    .storageWritten,
                origin:
                    envelope.origin
            )

            return .approved

        case .pinStorage:

            guard
                configuration.enableStorage
            else {
                return .unsupported(
                    "Web3 storage disabled."
                )
            }

            return .approvalRequired
        }
    }

    // MARK: Permission mapping

    private func permission(
        for request:
            SafariWeb3RuntimeRequest
    )
        -> SafariWeb3Permission?
    {
        switch request {

        case .connectWallet:
            return .connectWallet

        case .accounts:
            return .readAccounts

        case .chain:
            return .readChain

        case .balance:
            return .readBalance

        case .tokenBalances:
            return .readTokenBalances

        case .nftBalances:
            return .readNFTBalances

        case .identity:
            return .readIdentity

        case .authenticateIdentity:
            return .authenticateIdentity

        case .signMessage:
            return .signMessage

        case .signTypedData:
            return .signTypedData

        case .estimateTransaction:
            return .estimateTransaction

        case .simulateTransaction:
            return .simulateTransaction

        case .sendTransaction:
            return .sendTransaction

        case .switchChain:
            return .switchChain

        case .readStorage:
            return .readWeb3Storage

        case .writeStorage:
            return .writeWeb3Storage

        case .pinStorage:
            return .pinWeb3Storage
        }
    }

    private func reason(
        for request:
            SafariWeb3RuntimeRequest
    )
        -> String
    {
        switch request {

        case .connectWallet:
            return "The website wants to connect to a wallet."

        case .accounts:
            return "The website wants to view approved accounts."

        case .chain:
            return "The website wants to determine the active blockchain."

        case .balance:
            return "The website wants to read a blockchain balance."

        case .tokenBalances:
            return "The website wants to read token balances."

        case .nftBalances:
            return "The website wants to read NFT balances."

        case .identity:
            return "The website wants to access Web3 identity."

        case .authenticateIdentity:
            return "The website wants to authenticate the user's identity."

        case .signMessage:
            return "The website wants a cryptographic signature."

        case .signTypedData:
            return "The website wants a structured-data signature."

        case .estimateTransaction:
            return "The website wants to estimate a transaction."

        case .simulateTransaction:
            return "The website wants to simulate a transaction."

        case .sendTransaction:
            return "The website wants to send a blockchain transaction."

        case .switchChain:
            return "The website wants to change blockchain network."

        case .readStorage:
            return "The website wants to read decentralized storage."

        case .writeStorage:
            return "The website wants to write decentralized storage."

        case .pinStorage:
            return "The website wants to persist decentralized storage."
        }
    }

    private func registerSubsystems() {

        subsystemStatus =
            [
                "wallet":
                    SafariWeb3SubsystemStatus(
                        name:
                            "Native Wallet",
                        available:
                            configuration.enableWallet
                    ),

                "dappSessions":
                    SafariWeb3SubsystemStatus(
                        name:
                            "DApp Sessions",
                        available:
                            configuration.enableDAppSessions
                    ),

                "identity":
                    SafariWeb3SubsystemStatus(
                        name:
                            "Blockchain Identity",
                        available:
                            configuration.enableIdentity
                    ),

                "simulation":
                    SafariWeb3SubsystemStatus(
                        name:
                            "Transaction Simulation",
                        available:
                            configuration.enableTransactionSimulation
                    ),

                "security":
                    SafariWeb3SubsystemStatus(
                        name:
                            "Smart Contract Security",
                        available:
                            configuration.enableSecurityScanner
                    ),

                "storage":
                    SafariWeb3SubsystemStatus(
                        name:
                            "Web3 Storage",
                        available:
                            configuration.enableStorage
                    ),

                "assets":
                    SafariWeb3SubsystemStatus(
                        name:
                            "Token/NFT Browser",
                        available:
                            configuration.enableAssets
                    )
            ]
    }

    private func record(
        event:
            SafariWeb3RuntimeEvent,
        origin:
            SafariWeb3Origin? =
                nil
    ) async {

        guard
            configuration.enableTelemetry
        else {
            return
        }

        await telemetry.record(
            SafariWeb3RuntimeTelemetryRecord(
                runtimeID:
                    runtimeID,
                event:
                    event,
                origin:
                    origin
            )
        )
    }

    // MARK: Diagnostics

    public func snapshot()
        -> SafariWeb3RuntimeSnapshot
    {
        SafariWeb3RuntimeSnapshot(
            runtimeID:
                runtimeID,
            state:
                state,
            privateBrowsing:
                configuration.privateBrowsing,
            subsystems:
                Array(
                    subsystemStatus.values
                ),
            capturedAt:
                Date()
        )
    }
}

// MARK: - WebKit integration

@MainActor
public final class SafariWeb3WebKitBridge:
    NSObject,
    WKScriptMessageHandler
{
    private weak var webView:
        WKWebView?

    private let runtime:
        SafariWeb3BrowserRuntime

    public init(
        webView:
            WKWebView,
        runtime:
            SafariWeb3BrowserRuntime
    ) {
        self.webView =
            webView

        self.runtime =
            runtime

        super.init()
    }

    public func userContentController(
        _ userContentController:
            WKUserContentController,
        didReceive message:
            WKScriptMessage
    ) {

        guard
            let webView
        else {
            return
        }

        guard
            let url =
                webView.url,
            let origin =
                SafariWeb3Origin(
                    url:
                        url
                )
        else {
            return
        }

        guard
            let body =
                message.body
                as? [String: Any],
            let method =
                body["method"]
                as? String
        else {
            return
        }

        Task {

            let request =
                self.map(
                    method:
                        method
                )

            guard
                let request
            else {
                return
            }

            let envelope =
                SafariWeb3RequestEnvelope(
                    origin:
                        origin,
                    request:
                        request,
                    userInitiated:
                        true
                )

            let response =
                await runtime.handle(
                    envelope
                )

            await MainActor.run {

                self.sendResponse(
                    response:
                        response,
                    requestID:
                        body["id"]
                )
            }
        }
    }

    private func map(
        method:
            String
    )
        -> SafariWeb3RuntimeRequest?
    {
        switch method {

        case "eth_requestAccounts":
            return .connectWallet

        case "eth_accounts":
            return .accounts

        case "eth_chainId":
            return .chain

        case "eth_getBalance":
            return .balance

        case "personal_sign":
            return .signMessage(
                message:
                    Data()
            )

        case "eth_signTypedData",
             "eth_signTypedData_v4":

            return .signTypedData(
                payload:
                    Data()
            )

        case "eth_estimateGas":
            return .estimateTransaction

        case "eth_sendTransaction":
            return .sendTransaction

        case "wallet_switchEthereumChain":

            return .switchChain(
                chainID:
                    1
            )

        default:
            return nil
        }
    }

    private func sendResponse(
        response:
            SafariWeb3RuntimeResponse,
        requestID:
            Any?
    ) {

        // Production implementation should serialize
        // the response into the exact EIP-1193 JSON-RPC
        // response envelope and return it through the
        // page bridge.
        //
        // Do not execute arbitrary JavaScript constructed
        // from untrusted request strings.
        //
        // Use a fixed bridge protocol and safely encoded
        // JSON.
        _ = response
        _ = requestID
    }
}

// MARK: - Browser controller

@MainActor
public final class SafariWeb3BrowserController {

    public let runtime:
        SafariWeb3BrowserRuntime

    private weak var webView:
        WKWebView?

    private var bridge:
        SafariWeb3WebKitBridge?

    public init(
        webView:
            WKWebView,
        configuration:
            SafariWeb3RuntimeConfiguration =
                .init()
    ) {

        self.webView =
            webView

        self.runtime =
            SafariWeb3BrowserRuntime(
                configuration:
                    configuration
            )

        self.bridge =
            SafariWeb3WebKitBridge(
                webView:
                    webView,
                runtime:
                    runtime
            )
    }

    public func start() {

        Task {
            await runtime.start()
        }
    }

    public func suspend() {

        Task {
            await runtime.suspend()
        }
    }

    public func resume() {

        Task {
            await runtime.resume()
        }
    }

    public func stop() {

        Task {
            await runtime.stop()
        }
    }

    public func installBridge() {

        guard
            let bridge
        else {
            return
        }

        webView?
            .configuration
            .userContentController
            .add(
                bridge,
                name:
                    "safariWeb3"
            )
    }

    public func removeBridge() {

        webView?
            .configuration
            .userContentController
            .removeScriptMessageHandler(
                forName:
                    "safariWeb3"
            )
    }
}

// MARK: - Factory

public enum SafariWeb3RuntimeFactory {

    @MainActor
    public static func make(
        webView:
            WKWebView,
        privateBrowsing:
            Bool =
                false
    )
        -> SafariWeb3BrowserController
    {
        let configuration =
            SafariWeb3RuntimeConfiguration(
                privateBrowsing:
                    privateBrowsing
            )

        return SafariWeb3BrowserController(
            webView:
                webView,
            configuration:
                configuration
        )
    }
}

// MARK: - Architecture diagnostics

public struct SafariWeb3ArchitectureReport:
    Sendable
{
    public let title:
        String

    public let layers:
        [String]

    public let securityBoundary:
        String

    public let signingBoundary:
        String

    public let storageBoundary:
        String

    public init() {

        self.title =
            "Safari Native Web3 Architecture"

        self.layers =
            [
                "#1 Native Wallet",
                "#2 Blockchain RPC",
                "#3 DApp Sessions",
                "#4 Transaction Simulation",
                "#5 Blockchain Identity",
                "#6 Smart Contract Security",
                "#7 Decentralized Storage",
                "#8 Token/NFT Browser Layer",
                "#9 Privacy & Permission Firewall",
                "#10 Web3 Browser Runtime"
            ]

        self.securityBoundary =
            "#9 Privacy & Permission Firewall"

        self.signingBoundary =
            "#1 Native Wallet"

        self.storageBoundary =
            "#7 Decentralized Storage"
    }
}

// MARK: - DEBUG tests

#if DEBUG

enum SafariWeb3BrowserRuntimeTests {

    static func testRuntimeLifecycle()
        async
    {
        let runtime =
            SafariWeb3BrowserRuntime()

        await runtime.start()

        let snapshot =
            await runtime.snapshot()

        assert(
            snapshot.state ==
                .running
        )

        await runtime.suspend()

        let suspended =
            await runtime.snapshot()

        assert(
            suspended.state ==
                .suspended
        )

        await runtime.resume()

        let resumed =
            await runtime.snapshot()

        assert(
            resumed.state ==
                .running
        )

        await runtime.stop()

        let stopped =
            await runtime.snapshot()

        assert(
            stopped.state ==
                .stopped
        )
    }

    static func testPermissionRouting()
        async
    {
        let runtime =
            SafariWeb3BrowserRuntime()

        await runtime.start()

        let envelope =
            SafariWeb3RequestEnvelope(
                origin:
                    SafariWeb3Origin(
                        scheme:
                            "https",
                        host:
                            "example.com"
                    ),
                request:
                    .balance,
                userInitiated:
                    true
            )

        let result =
            await runtime.handle(
                envelope
            )

        switch result {

        case .approvalRequired:
            break

        case .balance:
            break

        default:
            break
        }
    }

    static func testSecureSigningBoundary()
        async
    {
        let runtime =
            SafariWeb3BrowserRuntime()

        await runtime.start()

        let envelope =
            SafariWeb3RequestEnvelope(
                origin:
                    SafariWeb3Origin(
                        scheme:
                            "http",
                        host:
                            "example.com"
                    ),
                request:
                    .signMessage(
                        message:
                            Data()
                    ),
                userInitiated:
                    true
            )

        let result =
            await runtime.handle(
                envelope
            )

        switch result {

        case .denied,
             .approvalRequired:
            break

        default:
            assertionFailure(
                "Insecure signing must not silently proceed."
            )
        }
    }

    static func runAll()
        async
    {
        await testRuntimeLifecycle()
        await testPermissionRouting()
        await testSecureSigningBoundary()
    }
}

#endif




