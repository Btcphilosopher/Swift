//
// SwiftPGPApple.swift
//
// Swift 6
//
// Apple-native PGP/OpenPGP identity integration.
//
// Responsibilities:
//
//  - PGP identity model
//  - ASCII Armor encoding/decoding
//  - PGP key metadata
//  - Key fingerprints
//  - Keychain-backed PGP key storage
//  - PGP private-key protection boundary
//  - Detached-signature abstraction
//  - Cryptographic sign-on challenge
//  - Replay protection
//  - Audit events
//
// IMPORTANT:
//
// This module deliberately separates:
//
//     OpenPGP packet format
//             from
//     Apple Keychain / CryptoKit / Security
//
// It does not invent a private "PGP-like" protocol.
//
// A complete interoperable OpenPGP implementation should supply
// an OpenPGP packet/signature engine behind PGPSigningProvider.
//

import Foundation
import Security
import CryptoKit
import os

// MARK: - Logging

private let pgpLog = Logger(
    subsystem: "SwiftPGPApple",
    category: "PGP"
)

// MARK: - Errors

public enum PGPError:
    Error,
    Sendable,
    CustomStringConvertible
{
    case invalidArmor
    case invalidBase64
    case invalidPacket
    case unsupportedPacket
    case invalidFingerprint
    case keyNotFound
    case keyAlreadyExists
    case keychainFailure(OSStatus)
    case signingFailure
    case verificationFailure
    case challengeExpired
    case challengeAlreadyUsed
    case identityRevoked
    case invalidIdentity
    case malformedSignature
    case unsupportedAlgorithm
    case privateKeyUnavailable
    case publicKeyUnavailable
    case invalidChallenge
    case serializationFailure

    public var description: String {
        switch self {
        case .invalidArmor:
            return "Invalid ASCII-armored OpenPGP data."

        case .invalidBase64:
            return "Invalid Base64 data."

        case .invalidPacket:
            return "Invalid OpenPGP packet."

        case .unsupportedPacket:
            return "Unsupported OpenPGP packet."

        case .invalidFingerprint:
            return "Invalid PGP fingerprint."

        case .keyNotFound:
            return "PGP key not found."

        case .keyAlreadyExists:
            return "PGP key already exists."

        case .keychainFailure(let status):
            return "Keychain operation failed: \(status)."

        case .signingFailure:
            return "PGP signing failed."

        case .verificationFailure:
            return "PGP signature verification failed."

        case .challengeExpired:
            return "PGP authentication challenge expired."

        case .challengeAlreadyUsed:
            return "PGP authentication challenge already used."

        case .identityRevoked:
            return "PGP identity has been revoked."

        case .invalidIdentity:
            return "Invalid PGP identity."

        case .malformedSignature:
            return "Malformed PGP signature."

        case .unsupportedAlgorithm:
            return "Unsupported cryptographic algorithm."

        case .privateKeyUnavailable:
            return "PGP private key is unavailable."

        case .publicKeyUnavailable:
            return "PGP public key is unavailable."

        case .invalidChallenge:
            return "Invalid PGP challenge."

        case .serializationFailure:
            return "Serialization failure."
        }
    }
}

// MARK: - PGP Fingerprint

public struct PGPFingerprint:
    Hashable,
    Codable,
    Sendable,
    CustomStringConvertible
{
    public let bytes:
        Data

    public init(
        bytes:
            Data
    ) throws {

        guard !bytes.isEmpty else {
            throw PGPError.invalidFingerprint
        }

        self.bytes = bytes
    }

    public init(
        hex:
            String
    ) throws {

        let normalized =
            hex
                .replacingOccurrences(
                    of: " ",
                    with: ""
                )
                .replacingOccurrences(
                    of: ":",
                    with: ""
                )

        guard normalized.count % 2 == 0 else {
            throw PGPError.invalidFingerprint
        }

        var result = Data()

        var index =
            normalized.startIndex

        while index < normalized.endIndex {

            let next =
                normalized.index(
                    index,
                    offsetBy: 2
                )

            let pair =
                normalized[
                    index..<next
                ]

            guard let byte =
                UInt8(
                    pair,
                    radix: 16
                )
            else {
                throw PGPError.invalidFingerprint
            }

            result.append(
                byte
            )

            index =
                next
        }

        try self.init(
            bytes:
                result
        )
    }

    public var hex:
        String
    {
        bytes
            .map {
                String(
                    format:
                        "%02X",
                    $0
                )
            }
            .joined()
    }

    public var description:
        String
    {
        hex
    }
}

// MARK: - PGP Key Type

public enum PGPKeyType:
    String,
    Codable,
    Sendable
{
    case publicKey
    case secretKey
    case publicSubkey
    case secretSubkey
}

// MARK: - PGP Algorithm

public enum PGPAlgorithm:
    UInt8,
    Codable,
    Sendable
{
    case rsaEncryptSign = 1
    case rsaEncrypt = 2
    case rsaSign = 3
    case dsa = 17
    case elgamal = 16
    case ec = 18
    case ecdsa = 19
    case edDSA = 22
    case unknown = 255
}

// MARK: - PGP Key Metadata

public struct PGPKeyMetadata:
    Codable,
    Sendable
{
    public let fingerprint:
        PGPFingerprint

    public let keyType:
        PGPKeyType

    public let algorithm:
        PGPAlgorithm

    public let createdAt:
        Date

    public let userID:
        String?

    public let armored:
        Bool

    public init(
        fingerprint:
            PGPFingerprint,
        keyType:
            PGPKeyType,
        algorithm:
            PGPAlgorithm,
        createdAt:
            Date,
        userID:
            String? = nil,
        armored:
            Bool = true
    ) {
        self.fingerprint =
            fingerprint

        self.keyType =
            keyType

        self.algorithm =
            algorithm

        self.createdAt =
            createdAt

        self.userID =
            userID

        self.armored =
            armored
    }
}

// MARK: - PGP Key Blob

public struct PGPKeyBlob:
    Sendable
{
    public let metadata:
        PGPKeyMetadata

    public let armoredData:
        Data

    public init(
        metadata:
            PGPKeyMetadata,
        armoredData:
            Data
    ) {
        self.metadata =
            metadata

        self.armoredData =
            armoredData
    }

    public var armoredString:
        String
    {
        String(
            data:
                armoredData,
            encoding:
                .utf8
        ) ?? ""
    }
}

// MARK: - ASCII Armor

public enum PGPArmor {

    private static let alphabet =
        Array(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        )

    public static func encode(
        data:
            Data,
        type:
            String = "PGP MESSAGE"
    ) -> String {

        let base64 =
            data.base64EncodedString(
                options:
                    [
                        .lineLength64Characters,
                        .endLineWithLineFeed
                    ]
            )

        let crc =
            crc24(
                data
            )

        let crcData =
            Data([
                UInt8(
                    (crc >> 16) & 0xff
                ),
                UInt8(
                    (crc >> 8) & 0xff
                ),
                UInt8(
                    crc & 0xff
                )
            ])

        let crcBase64 =
            crcData
                .base64EncodedString()

        return """
        -----BEGIN \(type)-----
        \(base64)
        =\(crcBase64)
        -----END \(type)-----
        """
    }

    public static func decode(
        _ armored:
            String
    ) throws -> Data {

        let lines =
            armored
                .components(
                    separatedBy:
                        .newlines
                )

        guard let beginIndex =
            lines.firstIndex(
                where:
                    {
                        $0.hasPrefix(
                            "-----BEGIN "
                        )
                    }
            )
        else {
            throw PGPError.invalidArmor
        }

        guard let endIndex =
            lines.firstIndex(
                where:
                    {
                        $0.hasPrefix(
                            "-----END "
                        )
                    }
        ),
        endIndex > beginIndex
        else {
            throw PGPError.invalidArmor
        }

        let body =
            lines[
                (beginIndex + 1)..<endIndex
            ]

        var base64 =
            ""

        var crcString:
            String?

        for line in body {

            if line.hasPrefix("=") {
                crcString =
                    String(
                        line.dropFirst()
                    )
                continue
            }

            if line.contains(":") {
                // Armor header.
                continue
            }

            base64 +=
                line.trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
        }

        guard let decoded =
            Data(
                base64Encoded:
                    base64,
                options:
                    .ignoreUnknownCharacters
            )
        else {
            throw PGPError.invalidBase64
        }

        if let crcString {

            guard let expected =
                Data(
                    base64Encoded:
                        crcString
                )
            else {
                throw PGPError.invalidArmor
            }

            let actualCRC =
                crc24(
                    decoded
                )

            let actualData =
                Data([
                    UInt8(
                        (actualCRC >> 16) & 0xff
                    ),
                    UInt8(
                        (actualCRC >> 8) & 0xff
                    ),
                    UInt8(
                        actualCRC & 0xff
                    )
                ])

            guard expected ==
                    actualData
            else {
                throw PGPError.invalidArmor
            }
        }

        return decoded
    }

    private static func crc24(
        _ data:
            Data
    ) -> UInt32 {

        var crc:
            UInt32 =
                0xB704CE

        for byte in data {

            crc ^=
                UInt32(byte) << 16

            for _ in 0..<8 {

                crc &=
                    0xFFFFFF

                crc <<= 1

                if crc &
                    0x1000000 != 0
                {
                    crc ^=
                        0x1864CFB
                }
            }
        }

        return crc &
            0xFFFFFF
    }
}

// MARK: - PGP Packet Header

public struct PGPPacketHeader:
    Sendable
{
    public let tag:
        UInt8

    public let body:
        Data

    public init(
        tag:
            UInt8,
        body:
            Data
    ) {
        self.tag =
            tag

        self.body =
            body
    }
}

// MARK: - Packet Reader

public struct PGPPacketReader:
    Sendable
{
    public init() {}

    public func read(
        _ data:
            Data
    ) throws -> [PGPPacketHeader] {

        var packets:
            [PGPPacketHeader] = []

        var index =
            data.startIndex

        while index <
                data.endIndex
        {
            guard let first =
                data[
                    safe:
                    index
                ]
            else {
                throw PGPError.invalidPacket
            }

            index =
                data.index(
                    after:
                        index
                )

            guard first &
                    0x80 != 0
            else {
                throw PGPError.invalidPacket
            }

            if first &
                0x40 != 0
            {
                let tag =
                    first &
                    0x3F

                let length =
                    try readNewLength(
                        data,
                        index:
                            &index
                    )

                guard
                    let body =
                        data[
                            safeRange:
                                index,
                            length:
                                length
                        ]
                else {
                    throw PGPError.invalidPacket
                }

                index =
                    data.index(
                        index,
                        offsetBy:
                            length
                    )

                packets.append(
                    PGPPacketHeader(
                        tag:
                            tag,
                        body:
                            body
                    )
                )

            } else {

                let tag =
                    (first >> 2) &
                    0x0F

                let lengthType =
                    first &
                    0x03

                let length:
                    Int

                switch lengthType {

                case 0:
                    guard let value =
                        data[
                            safe:
                            index
                        ]
                    else {
                        throw PGPError.invalidPacket
                    }

                    index =
                        data.index(
                            after:
                                index
                        )

                    length =
                        Int(value)

                case 1:

                    guard
                        let a =
                            data[safe: index],
                        let b =
                            data[
                                safe:
                                data.index(
                                    after:
                                        index
                                )
                            ]
                    else {
                        throw PGPError.invalidPacket
                    }

                    index =
                        data.index(
                            index,
                            offsetBy:
                                2
                        )

                    length =
                        Int(
                            UInt16(a) << 8 |
                            UInt16(b)
                        )

                case 2:

                    guard
                        let remaining =
                            data.distance(
                                from:
                                    index,
                                to:
                                    data.endIndex
                            )
                    else {
                        throw PGPError.invalidPacket
                    }

                    length =
                        remaining

                case 3:

                    throw PGPError.unsupportedPacket

                default:

                    throw PGPError.invalidPacket
                }

                guard
                    let body =
                        data[
                            safeRange:
                                index,
                            length:
                                length
                        ]
                else {
                    throw PGPError.invalidPacket
                }

                index =
                    data.index(
                        index,
                        offsetBy:
                            length
                    )

                packets.append(
                    PGPPacketHeader(
                        tag:
                            tag,
                        body:
                            body
                    )
                )
            }
        }

        return packets
    }

    private func readNewLength(
        _ data:
            Data,
        index:
            inout Data.Index
    ) throws -> Int {

        guard let first =
            data[safe: index]
        else {
            throw PGPError.invalidPacket
        }

        index =
            data.index(
                after:
                    index
            )

        switch first {

        case 0...191:

            return Int(first)

        case 192...223:

            guard let second =
                data[safe: index]
            else {
                throw PGPError.invalidPacket
            }

            index =
                data.index(
                    after:
                        index
                )

            return
                ((Int(first) - 192) << 8) +
                Int(second) +
                192

        case 255:

            guard
                let a =
                    data[safe: index],
                let b =
                    data[
                        safe:
                        data.index(
                            after:
                                index
                        )
                    ],
                let c =
                    data[
                        safe:
                        data.index(
                            index,
                            offsetBy:
                                2
                        )
                    ],
                let d =
                    data[
                        safe:
                        data.index(
                            index,
                            offsetBy:
                                3
                        )
                    ]
            else {
                throw PGPError.invalidPacket
            }

            index =
                data.index(
                    index,
                    offsetBy:
                        4
                )

            return
                Int(
                    UInt32(a) << 24 |
                    UInt32(b) << 16 |
                    UInt32(c) << 8 |
                    UInt32(d)
                )

        default:

            throw PGPError.unsupportedPacket
        }
    }
}

// MARK: - Data Safe Access

private extension Data {

    subscript(
        safe index:
            Data.Index
    ) -> UInt8? {

        guard index >= startIndex &&
              index < endIndex
        else {
            return nil
        }

        return self[index]
    }

    subscript(
        safeRange start:
            Data.Index,
        length:
            Int
    ) -> Data? {

        guard length >= 0 else {
            return nil
        }

        guard let end =
            index(
                start,
                offsetBy:
                    length,
                limitedBy:
                    endIndex
            )
        else {
            return nil
        }

        return Data(
            self[start..<end]
        )
    }
}

// MARK: - PGP Key Parser

public struct PGPKeyParser:
    Sendable
{
    public init() {}

    public func parse(
        armored:
            String
    ) throws
        -> PGPKeyBlob
    {
        let binary =
            try PGPArmor.decode(
                armored
            )

        let packets =
            try PGPPacketReader()
                .read(
                    binary
                )

        guard let packet =
            packets.first
        else {
            throw PGPError.invalidPacket
        }

        let type:
            PGPKeyType

        switch packet.tag {

        case 6:
            type =
                .publicKey

        case 5:
            type =
                .secretKey

        case 14:
            type =
                .publicSubkey

        case 7:
            type =
                .secretSubkey

        default:
            throw PGPError.unsupportedPacket
        }

        guard packet.body.count >= 6
        else {
            throw PGPError.invalidPacket
        }

        let version =
            packet.body[
                packet.body.startIndex
            ]

        guard version == 4 ||
              version == 5 ||
              version == 6
        else {
            throw PGPError.unsupportedPacket
        }

        let fingerprint =
            try calculateFingerprint(
                packetBody:
                    packet.body,
                version:
                    version
            )

        let algorithmByte =
            packet.body[
                packet.body.index(
                    packet.body.startIndex,
                    offsetBy:
                        5
                )
            ]

        let algorithm =
            PGPAlgorithm(
                rawValue:
                    algorithmByte
            ) ?? .unknown

        let metadata =
            PGPKeyMetadata(
                fingerprint:
                    fingerprint,
                keyType:
                    type,
                algorithm:
                    algorithm,
                createdAt:
                    Date()
            )

        return PGPKeyBlob(
            metadata:
                metadata,
            armoredData:
                Data(
                    armored.utf8
                )
        )
    }

    private func calculateFingerprint(
        packetBody:
            Data,
        version:
            UInt8
    ) throws
        -> PGPFingerprint
    {
        // OpenPGP fingerprint calculation differs by key version.
        //
        // This implementation explicitly handles v4.
        //
        // v5/v6 should be delegated to a complete OpenPGP
        // implementation because their fingerprint construction
        // differs from the legacy v4 mechanism.

        guard version == 4 else {
            throw PGPError.unsupportedPacket
        }

        var prefix =
            Data([
                0x99
            ])

        let length =
            UInt16(
                packetBody.count
            )

        prefix.append(
            UInt8(
                length >> 8
            )
        )

        prefix.append(
            UInt8(
                length & 0xff
            )
        )

        prefix.append(
            packetBody
        )

        return try PGPFingerprint(
            bytes:
                Data(
                    Insecure.SHA1.hash(
                        data:
                            prefix
                    )
                )
        )
    }
}

// MARK: - Keychain PGP Store

public actor PGPKeychainStore {

    private let service:
        String

    public init(
        service:
            String =
                "com.swiftsecurecore.pgp"
    ) {
        self.service =
            service
    }

    // MARK: Store

    public func store(
        _ key:
            PGPKeyBlob
    ) throws {

        let account =
            key.metadata.fingerprint.hex

        let data =
            key.armoredData

        let query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrService as String:
                    service,

                kSecAttrAccount as String:
                    account,

                kSecAttrAccessible as String:
                    kSecAttrAccessibleWhenUnlocked,

                kSecUseDataProtectionKeychain as String:
                    true,

                kSecValueData as String:
                    data
            ]

        let status =
            SecItemAdd(
                query as CFDictionary,
                nil
            )

        guard status ==
                errSecSuccess
        else {

            if status ==
                errSecDuplicateItem
            {
                throw PGPError
                    .keyAlreadyExists
            }

            throw PGPError
                .keychainFailure(
                    status
                )
        }

        pgpLog.info(
            "PGP key stored in Keychain."
        )
    }

    // MARK: Load

    public func load(
        fingerprint:
            PGPFingerprint
    ) throws
        -> PGPKeyBlob
    {
        let account =
            fingerprint.hex

        let query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrService as String:
                    service,

                kSecAttrAccount as String:
                    account,

                kSecUseDataProtectionKeychain as String:
                    true,

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

        guard status ==
                errSecSuccess
        else {

            if status ==
                errSecItemNotFound
            {
                throw PGPError
                    .keyNotFound
            }

            throw PGPError
                .keychainFailure(
                    status
                )
        }

        guard let data =
            result as? Data
        else {
            throw PGPError
                .keychainFailure(
                    errSecInternalError
                )
        }

        guard let armored =
            String(
                data:
                    data,
                encoding:
                    .utf8
            )
        else {
            throw PGPError
                .invalidArmor
        }

        return try PGPKeyParser()
            .parse(
                armored:
                    armored
            )
    }

    // MARK: Delete

    public func delete(
        fingerprint:
            PGPFingerprint
    ) throws {

        let query:
            [String: Any] = [

                kSecClass as String:
                    kSecClassGenericPassword,

                kSecAttrService as String:
                    service,

                kSecAttrAccount as String:
                    fingerprint.hex,

                kSecUseDataProtectionKeychain as String:
                    true
            ]

        let status =
            SecItemDelete(
                query as CFDictionary
            )

        guard status ==
                errSecSuccess ||
              status ==
                errSecItemNotFound
        else {
            throw PGPError
                .keychainFailure(
                    status
                )
        }
    }
}

// MARK: - Signing Provider

public protocol PGPSigningProvider:
    Sendable
{
    func sign(
        data:
            Data
    ) async throws -> Data

    func verify(
        data:
            Data,
        signature:
            Data
    ) async throws -> Bool
}

// MARK: - Detached Signature

public struct PGPDetachedSignature:
    Sendable,
    Codable
{
    public let fingerprint:
        PGPFingerprint

    public let createdAt:
        Date

    public let signature:
        Data

    public init(
        fingerprint:
            PGPFingerprint,
        createdAt:
            Date = Date(),
        signature:
            Data
    ) {
        self.fingerprint =
            fingerprint

        self.createdAt =
            createdAt

        self.signature =
            signature
    }
}

// MARK: - PGP Sign-On Challenge

public struct PGPAuthenticationChallenge:
    Sendable,
    Codable
{
    public let id:
        UUID

    public let fingerprint:
        PGPFingerprint

    public let issuedAt:
        Date

    public let expiresAt:
        Date

    public let nonce:
        Data

    public init(
        id:
            UUID = UUID(),
        fingerprint:
            PGPFingerprint,
        issuedAt:
            Date = Date(),
        expiresAt:
            Date,
        nonce:
            Data
    ) {
        self.id =
            id

        self.fingerprint =
            fingerprint

        self.issuedAt =
            issuedAt

        self.expiresAt =
            expiresAt

        self.nonce =
            nonce
    }

    public var expired:
        Bool
    {
        Date() >= expiresAt
    }
}

// MARK: - PGP Sign-On Response

public struct PGPAuthenticationResponse:
    Sendable,
    Codable
{
    public let challengeID:
        UUID

    public let fingerprint:
        PGPFingerprint

    public let signature:
        Data

    public init(
        challengeID:
            UUID,
        fingerprint:
            PGPFingerprint,
        signature:
            Data
    ) {
        self.challengeID =
            challengeID

        self.fingerprint =
            fingerprint

        self.signature =
            signature
    }
}

// MARK: - Challenge Store

public actor PGPChallengeStore {

    private var challenges:
        [UUID:
            PGPAuthenticationChallenge] = [:]

    public init() {}

    public func insert(
        _ challenge:
            PGPAuthenticationChallenge
    ) {
        challenges[
            challenge.id
        ] = challenge
    }

    public func consume(
        id:
            UUID
    ) throws
        -> PGPAuthenticationChallenge
    {
        guard let challenge =
            challenges.removeValue(
                forKey:
                    id
            )
        else {
            throw PGPError
                .invalidChallenge
        }

        guard !challenge.expired
        else {
            throw PGPError
                .challengeExpired
        }

        return challenge
    }
}

// MARK: - PGP Identity

public struct PGPAppleIdentity:
    Codable,
    Sendable
{
    public let fingerprint:
        PGPFingerprint

    public let userID:
        String

    public let createdAt:
        Date

    public var revoked:
        Bool

    public init(
        fingerprint:
            PGPFingerprint,
        userID:
            String,
        createdAt:
            Date = Date(),
        revoked:
            Bool = false
    ) {
        self.fingerprint =
            fingerprint

        self.userID =
            userID

        self.createdAt =
            createdAt

        self.revoked =
            revoked
    }
}

// MARK: - Identity Registry

public actor PGPAppleIdentityRegistry {

    private var identities:
        [PGPFingerprint:
            PGPAppleIdentity] = [:]

    public init() {}

    public func register(
        _ identity:
            PGPAppleIdentity
    ) throws {

        guard identities[
            identity.fingerprint
        ] == nil
        else {
            throw PGPError
                .keyAlreadyExists
        }

        identities[
            identity.fingerprint
        ] = identity
    }

    public func get(
        _ fingerprint:
            PGPFingerprint
    ) throws
        -> PGPAppleIdentity
    {
        guard let identity =
            identities[
                fingerprint
            ]
        else {
            throw PGPError
                .keyNotFound
        }

        guard !identity.revoked
        else {
            throw PGPError
                .identityRevoked
        }

        return identity
    }

    public func revoke(
        _ fingerprint:
            PGPFingerprint
    ) throws {

        guard var identity =
            identities[
                fingerprint
            ]
        else {
            throw PGPError
                .keyNotFound
        }

        identity.revoked =
            true

        identities[
            fingerprint
        ] =
            identity
    }
}

// MARK: - PGP Sign-On Server

public actor PGPAppleSignOnServer {

    public let identities:
        PGPAppleIdentityRegistry

    public let challenges:
        PGPChallengeStore

    private let challengeLifetime:
        TimeInterval

    public init(
        challengeLifetime:
            TimeInterval = 30
    ) {
        self.identities =
            PGPAppleIdentityRegistry()

        self.challenges =
            PGPChallengeStore()

        self.challengeLifetime =
            challengeLifetime
    }

    public func register(
        fingerprint:
            PGPFingerprint,
        userID:
            String
    ) async throws
        -> PGPAppleIdentity
    {
        let identity =
            PGPAppleIdentity(
                fingerprint:
                    fingerprint,
                userID:
                    userID
            )

        try await identities.register(
            identity
        )

        return identity
    }

    public func issueChallenge(
        fingerprint:
            PGPFingerprint
    ) async throws
        -> PGPAuthenticationChallenge
    {
        _ = try await identities.get(
            fingerprint
        )

        var nonce =
            Data(
                count:
                    32
            )

        let result =
            nonce.withUnsafeMutableBytes {
                buffer in

                SecRandomCopyBytes(
                    kSecRandomDefault,
                    buffer.count,
                    buffer.baseAddress!
                )
            }

        guard result ==
                errSecSuccess
        else {
            throw PGPError
                .signingFailure
        }

        let now =
            Date()

        let challenge =
            PGPAuthenticationChallenge(
                fingerprint:
                    fingerprint,
                issuedAt:
                    now,
                expiresAt:
                    now.addingTimeInterval(
                        challengeLifetime
                    ),
                nonce:
                    nonce
            )

        await challenges.insert(
            challenge
        )

        return challenge
    }

    public func verify(
        response:
            PGPAuthenticationResponse,
        provider:
            PGPSigningProvider
    ) async throws
        -> Bool
    {
        let challenge =
            try await challenges.consume(
                id:
                    response.challengeID
            )

        guard challenge.fingerprint ==
                response.fingerprint
        else {
            throw PGPError
                .verificationFailure
        }

        let message =
            Self.challengeBytes(
                challenge
            )

        let valid =
            try await provider.verify(
                data:
                    message,
                signature:
                    response.signature
            )

        guard valid
        else {
            throw PGPError
                .verificationFailure
        }

        return true
    }

    private static func challengeBytes(
        _ challenge:
            PGPAuthenticationChallenge
    ) -> Data {

        var result =
            Data()

        result.append(
            Data(
                "SWIFTPGP-APPLE-SIGNON-V1"
                    .utf8
            )
        )

        result.append(
            Data(
                challenge.id.uuidString
                    .utf8
            )
        )

        result.append(
            Data(
                challenge.fingerprint.hex
                    .utf8
            )
        )

        result.append(
            challenge.nonce
        )

        return result
    }
}

// MARK: - PGP Client

public struct PGPAppleSignOnClient:
    Sendable
{
    public let fingerprint:
        PGPFingerprint

    private let signer:
        PGPSigningProvider

    public init(
        fingerprint:
            PGPFingerprint,
        signer:
            PGPSigningProvider
    ) {
        self.fingerprint =
            fingerprint

        self.signer =
            signer
    }

    public func respond(
        to challenge:
            PGPAuthenticationChallenge
    ) async throws
        -> PGPAuthenticationResponse
    {
        guard challenge.fingerprint ==
                fingerprint
        else {
            throw PGPError
                .invalidChallenge
        }

        guard !challenge.expired
        else {
            throw PGPError
                .challengeExpired
        }

        var message =
            Data()

        message.append(
            Data(
                "SWIFTPGP-APPLE-SIGNON-V1"
                    .utf8
            )
        )

        message.append(
            Data(
                challenge.id.uuidString
                    .utf8
            )
        )

        message.append(
            Data(
                challenge.fingerprint.hex
                    .utf8
            )
        )

        message.append(
            challenge.nonce
        )

        let signature =
            try await signer.sign(
                data:
                    message
            )

        return PGPAuthenticationResponse(
            challengeID:
                challenge.id,
            fingerprint:
                fingerprint,
            signature:
                signature
        )
    }
}

// MARK: - Development CryptoKit Provider
//
// This provider is deliberately NOT called "OpenPGP".
// It demonstrates the provider boundary.
// A real OpenPGP provider must perform OpenPGP signature
// packet construction/verification using the selected PGP
// public/private key algorithm.
//

public actor DevelopmentCryptoKitSigner:
    PGPSigningProvider
{
    private let privateKey:
        P256.Signing.PrivateKey

    public let publicKey:
        P256.Signing.PublicKey

    public init(
        privateKey:
            P256.Signing.PrivateKey =
                P256.Signing.PrivateKey()
    ) {
        self.privateKey =
            privateKey

        self.publicKey =
            privateKey.publicKey
    }

    public func sign(
        data:
            Data
    ) async throws -> Data {

        do {
            let signature =
                try privateKey.signature(
                    for:
                        data
                )

            return signature.derRepresentation

        } catch {
            throw PGPError
                .signingFailure
        }
    }

    public func verify(
        data:
            Data,
        signature:
            Data
    ) async throws -> Bool {

        do {

            let signature =
                try P256.Signing.ECDSASignature(
                    derRepresentation:
                        signature
                )

            return publicKey
                .isValidSignature(
                    signature,
                    for:
                        data
                )

        } catch {
            throw PGPError
                .verificationFailure
        }
    }
}

// MARK: - PGP Key Import Service

public actor PGPKeyImportService {

    private let parser:
        PGPKeyParser

    private let store:
        PGPKeychainStore

    public init(
        store:
            PGPKeychainStore =
                PGPKeychainStore()
    ) {
        self.parser =
            PGPKeyParser()

        self.store =
            store
    }

    public func importArmoredKey(
        _ armored:
            String
    ) async throws
        -> PGPKeyMetadata
    {
        let key =
            try parser.parse(
                armored:
                    armored
            )

        try await store.store(
            key
        )

        return key.metadata
    }

    public func load(
        fingerprint:
            PGPFingerprint
    ) async throws
        -> PGPKeyBlob
    {
        try await store.load(
            fingerprint:
                fingerprint
        )
    }

    public func delete(
        fingerprint:
            PGPFingerprint
    ) async throws {

        try await store.delete(
            fingerprint:
                fingerprint
        )
    }
}

// MARK: - Public Key Fingerprint Helper
//
// For OpenPGP v4 keys, the fingerprint is SHA-1 over:
//     0x99 || uint16(bodyLength) || publicKeyPacketBody
//
// This is an OpenPGP compatibility operation,
// not a recommendation to use SHA-1 for new general-purpose
// cryptographic hashing.
//

public enum PGPV4Fingerprint {

    public static func calculate(
        publicKeyPacketBody:
            Data
    ) throws
        -> PGPFingerprint
    {
        guard publicKeyPacketBody.count <=
                Int(UInt16.max)
        else {
            throw PGPError
                .invalidPacket
        }

        var data =
            Data()

        data.append(
            0x99
        )

        let length =
            UInt16(
                publicKeyPacketBody.count
            )

        data.append(
            UInt8(
                length >> 8
            )
        )

        data.append(
            UInt8(
                length & 0xff
            )
        )

        data.append(
            publicKeyPacketBody
        )

        return try PGPFingerprint(
            bytes:
                Data(
                    Insecure.SHA1.hash(
                        data:
                            data
                    )
                )
        )
    }
}

// MARK: - Example

public enum SwiftPGPAppleExample {

    public static func run()
        async throws
    {
        // ----------------------------------------------------
        // 1. Parse an existing ASCII-armored PGP public key.
        // ----------------------------------------------------

        let armoredPublicKey = """
        -----BEGIN PGP PUBLIC KEY BLOCK-----
        """

        // Real OpenPGP armor should be supplied here.
        //
        // The example intentionally doesn't embed a fake key.

        if armoredPublicKey !=
            "-----BEGIN PGP PUBLIC KEY BLOCK-----"
        {
            let importer =
                PGPKeyImportService()

            let metadata =
                try await importer
                    .importArmoredKey(
                        armoredPublicKey
                    )

            pgpLog.info(
                """
                Imported PGP key:
                \(metadata.fingerprint.hex)
                """
            )
        }

        // ----------------------------------------------------
        // 2. Apple cryptographic sign-on demonstration.
        // ----------------------------------------------------

        let signer =
            DevelopmentCryptoKitSigner()

        let publicKey =
            await signer.publicKey
                .x963Representation

        let fingerprint =
            try PGPFingerprint(
                bytes:
                    Data(
                        SHA256.hash(
                            data:
                                publicKey
                        )
                    )
            )

        let server =
            PGPAppleSignOnServer()

        _ = try await server.register(
            fingerprint:
                fingerprint,
            userID:
                "operator@example"
        )

        let challenge =
            try await server.issueChallenge(
                fingerprint:
                    fingerprint
            )

        let client =
            PGPAppleSignOnClient(
                fingerprint:
                    fingerprint,
                signer:
                    signer
            )

        let response =
            try await client.respond(
                to:
                    challenge
            )

        let verified =
            try await server.verify(
                response:
                    response,
                provider:
                    signer
            )

        pgpLog.notice(
            """
            Cryptographic sign-on:
            \(verified ? "SUCCESS" : "FAILED")
            """
        )
    }
}




