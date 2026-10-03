```swift
//
//  AppleFirewall.swift
//
//  Policy-based firewall engine for Apple platforms.
//
//  Architecture:
//
//      Network Extension
//             │
//             ▼
//      AppleFirewallEngine
//             │
//       ┌─────┼─────┐
//       ▼     ▼     ▼
//     Rules  Rate   Audit
//           Limit   Log
//       │     │     │
//       └─────┼─────┘
//             ▼
//       Allow / Deny / Inspect
//
//  IMPORTANT:
//  This policy engine does not itself install a kernel firewall.
//  On Apple platforms, actual system-level filtering should be
//  connected to Apple's Network Extension framework and the
//  appropriate Apple entitlements/user approval.
//

import Foundation
import Network
import os


// ================================================================
// MARK: - Firewall Decision
// ================================================================

public enum FirewallDecision: String, Codable {

    case allow
    case deny
    case monitor
    case rateLimited
}


// ================================================================
// MARK: - Direction
// ================================================================

public enum NetworkDirection: String, Codable {

    case inbound
    case outbound
}


// ================================================================
// MARK: - Transport
// ================================================================

public enum TransportProtocol: String, Codable {

    case tcp
    case udp
    case icmp
    case other
}


// ================================================================
// MARK: - Network Endpoint
// ================================================================

public struct FirewallEndpoint: Codable, Hashable {

    public let address: String
    public let port: UInt16?

    public init(
        address: String,
        port: UInt16? = nil
    ) {
        self.address = address
        self.port = port
    }
}


// ================================================================
// MARK: - Network Flow
// ================================================================

public struct FirewallFlow: Codable {

    public let timestamp: Date

    public let processName: String?
    public let processIdentifier: Int32?

    public let direction: NetworkDirection

    public let source: FirewallEndpoint
    public let destination: FirewallEndpoint

    public let transport: TransportProtocol

    public let domain: String?

    public let bytes: UInt64

    public init(
        timestamp: Date = Date(),
        processName: String? = nil,
        processIdentifier: Int32? = nil,
        direction: NetworkDirection,
        source: FirewallEndpoint,
        destination: FirewallEndpoint,
        transport: TransportProtocol,
        domain: String? = nil,
        bytes: UInt64 = 0
    ) {
        self.timestamp = timestamp
        self.processName = processName
        self.processIdentifier = processIdentifier
        self.direction = direction
        self.source = source
        self.destination = destination
        self.transport = transport
        self.domain = domain
        self.bytes = bytes
    }
}


// ================================================================
// MARK: - Firewall Rule
// ================================================================

public struct FirewallRule: Codable, Identifiable {

    public let id: UUID

    public var name: String

    public var enabled: Bool

    public var decision: FirewallDecision

    public var direction: NetworkDirection?

    public var processName: String?

    public var processIdentifier: Int32?

    public var sourceAddress: String?

    public var destinationAddress: String?

    public var destinationDomain: String?

    public var port: UInt16?

    public var transport: TransportProtocol?

    public var priority: Int

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        decision: FirewallDecision,
        direction: NetworkDirection? = nil,
        processName: String? = nil,
        processIdentifier: Int32? = nil,
        sourceAddress: String? = nil,
        destinationAddress: String? = nil,
        destinationDomain: String? = nil,
        port: UInt16? = nil,
        transport: TransportProtocol? = nil,
        priority: Int = 100
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.decision = decision
        self.direction = direction
        self.processName = processName
        self.processIdentifier = processIdentifier
        self.sourceAddress = sourceAddress
        self.destinationAddress = destinationAddress
        self.destinationDomain = destinationDomain
        self.port = port
        self.transport = transport
        self.priority = priority
    }
}


// ================================================================
// MARK: - Audit Event
// ================================================================

public struct FirewallAuditEvent: Codable {

    public let timestamp: Date

    public let decision: FirewallDecision

    public let ruleID: UUID?

    public let ruleName: String?

    public let flow: FirewallFlow

    public let reason: String
}


// ================================================================
// MARK: - Rate Limiting
// ================================================================

private struct RateLimitBucket {

    var windowStart: Date

    var count: Int
}


// ================================================================
// MARK: - Firewall Statistics
// ================================================================

public struct FirewallStatistics {

    public var inspected: UInt64 = 0
    public var allowed: UInt64 = 0
    public var denied: UInt64 = 0
    public var monitored: UInt64 = 0
    public var rateLimited: UInt64 = 0

    public var bytesObserved: UInt64 = 0
}


// ================================================================
// MARK: - Firewall Configuration
// ================================================================

public struct FirewallConfiguration {

    public var defaultOutbound:
        FirewallDecision = .allow

    public var defaultInbound:
        FirewallDecision = .deny

    public var enableLogging:
        Bool = true

    public var enableRateLimiting:
        Bool = true

    public var maximumEvents:
        Int = 10_000

    public var defaultRateLimit:
        Int = 100

    public var rateWindow:
        TimeInterval = 60

    public init() {}
}


// ================================================================
// MARK: - Firewall Engine
// ================================================================

public actor AppleFirewallEngine {

    // ------------------------------------------------------------
    // Properties
    // ------------------------------------------------------------

    private var rules:
        [FirewallRule] = []

    private var auditLog:
        [FirewallAuditEvent] = []

    private var rateLimits:
        [String: RateLimitBucket] = [:]

    private var statistics =
        FirewallStatistics()

    private var configuration:
        FirewallConfiguration

    private let logger =
        Logger(
            subsystem: "com.example.AppleFirewall",
            category: "Firewall"
        )


    // ------------------------------------------------------------
    // Initialisation
    // ------------------------------------------------------------

    public init(
        configuration:
            FirewallConfiguration =
                FirewallConfiguration()
    ) {
        self.configuration =
            configuration
    }


    // ============================================================
    // MARK: - Rule Management
    // ============================================================

    public func addRule(
        _ rule: FirewallRule
    ) {

        rules.append(rule)

        rules.sort {
            $0.priority < $1.priority
        }
    }


    public func removeRule(
        id: UUID
    ) {

        rules.removeAll {
            $0.id == id
        }
    }


    public func replaceRules(
        _ newRules: [FirewallRule]
    ) {

        rules =
            newRules.sorted {
                $0.priority < $1.priority
            }
    }


    public func allRules()
        -> [FirewallRule] {

        rules
    }


    // ============================================================
    // MARK: - Evaluation
    // ============================================================

    public func evaluate(
        _ flow: FirewallFlow
    ) -> FirewallDecision {

        statistics.inspected += 1
        statistics.bytesObserved += flow.bytes


        // --------------------------------------------------------
        // Rate limiting
        // --------------------------------------------------------

        if configuration.enableRateLimiting {

            if isRateLimited(flow) {

                statistics.rateLimited += 1

                let decision =
                    FirewallDecision.rateLimited

                record(
                    decision: decision,
                    rule: nil,
                    flow: flow,
                    reason:
                        "Connection exceeded rate limit."
                )

                return decision
            }
        }


        // --------------------------------------------------------
        // Rule matching
        // --------------------------------------------------------

        for rule in rules {

            guard rule.enabled else {
                continue
            }

            guard matches(
                rule: rule,
                flow: flow
            ) else {
                continue
            }

            let decision =
                rule.decision

            updateStatistics(
                decision
            )

            record(
                decision: decision,
                rule: rule,
                flow: flow,
                reason:
                    "Matched firewall rule: \(rule.name)"
            )

            return decision
        }


        // --------------------------------------------------------
        // Default policy
        // --------------------------------------------------------

        let decision:

            FirewallDecision

        switch flow.direction {

        case .inbound:
            decision =
                configuration.defaultInbound

        case .outbound:
            decision =
                configuration.defaultOutbound
        }


        updateStatistics(
            decision
        )

        record(
            decision: decision,
            rule: nil,
            flow: flow,
            reason:
                "No explicit rule matched."
        )

        return decision
    }


    // ============================================================
    // MARK: - Rule Matching
    // ============================================================

    private func matches(
        rule: FirewallRule,
        flow: FirewallFlow
    ) -> Bool {

        if let direction =
            rule.direction,
            direction != flow.direction {

            return false
        }


        if let processName =
            rule.processName {

            guard flow.processName?
                .localizedCaseInsensitiveCompare(
                    processName
                ) == .orderedSame
            else {
                return false
            }
        }


        if let pid =
            rule.processIdentifier {

            guard flow.processIdentifier == pid else {
                return false
            }
        }


        if let source =
            rule.sourceAddress {

            guard flow.source.address == source else {
                return false
            }
        }


        if let destination =
            rule.destinationAddress {

            guard flow.destination.address ==
                destination
            else {
                return false
            }
        }


        if let domain =
            rule.destinationDomain {

            guard domainMatches(
                actual: flow.domain,
                rule: domain
            ) else {
                return false
            }
        }


        if let port =
            rule.port {

            guard flow.destination.port == port else {
                return false
            }
        }


        if let transport =
            rule.transport {

            guard flow.transport == transport else {
                return false
            }
        }


        return true
    }


    // ============================================================
    // MARK: - Domain Matching
    // ============================================================

    private func domainMatches(
        actual: String?,
        rule: String
    ) -> Bool {

        guard let actual else {
            return false
        }

        let normalizedActual =
            actual.lowercased()

        let normalizedRule =
            rule.lowercased()

        if normalizedActual ==
            normalizedRule {

            return true
        }

        // Supports:
        // *.example.com

        if normalizedRule.hasPrefix("*.") {

            let suffix =
                String(
                    normalizedRule.dropFirst(1)
                )

            return normalizedActual.hasSuffix(
                suffix
            )
        }

        return false
    }


    // ============================================================
    // MARK: - Rate Limiting
    // ============================================================

    private func rateKey(
        _ flow: FirewallFlow
    ) -> String {

        [
            flow.processName ?? "unknown",
            flow.destination.address,
            String(
                flow.destination.port ?? 0
            )
        ]
        .joined(
            separator: "|"
        )
    }


    private func isRateLimited(
        _ flow: FirewallFlow
    ) -> Bool {

        let key =
            rateKey(flow)

        let now =
            Date()

        guard var bucket =
            rateLimits[key]
        else {

            rateLimits[key] =
                RateLimitBucket(
                    windowStart: now,
                    count: 1
                )

            return false
        }


        if now.timeIntervalSince(
            bucket.windowStart
        ) >= configuration.rateWindow {

            bucket =
                RateLimitBucket(
                    windowStart: now,
                    count: 1
                )

            rateLimits[key] = bucket

            return false
        }


        bucket.count += 1

        rateLimits[key] = bucket

        return bucket.count >
            configuration.defaultRateLimit
    }


    // ============================================================
    // MARK: - Statistics
    // ============================================================

    private func updateStatistics(
        _ decision: FirewallDecision
    ) {

        switch decision {

        case .allow:
            statistics.allowed += 1

        case .deny:
            statistics.denied += 1

        case .monitor:
            statistics.monitored += 1

        case .rateLimited:
            statistics.rateLimited += 1
        }
    }


    public func getStatistics()
        -> FirewallStatistics {

        statistics
    }


    // ============================================================
    // MARK: - Audit
    // ============================================================

    private func record(
        decision: FirewallDecision,
        rule: FirewallRule?,
        flow: FirewallFlow,
        reason: String
    ) {

        guard configuration.enableLogging else {
            return
        }

        let event =
            FirewallAuditEvent(
                timestamp: Date(),
                decision: decision,
                ruleID: rule?.id,
                ruleName: rule?.name,
                flow: flow,
                reason: reason
            )

        auditLog.append(event)

        if auditLog.count >
            configuration.maximumEvents {

            auditLog.removeFirst(
                auditLog.count -
                configuration.maximumEvents
            )
        }


        switch decision {

        case .deny:

            logger.warning(
                """
                BLOCKED:
                \(flow.destination.address):
                \(flow.destination.port ?? 0)
                """
            )

        case .rateLimited:

            logger.warning(
                "RATE LIMITED network flow."
            )

        default:

            logger.debug(
                "Firewall flow processed."
            )
        }
    }


    public func auditEvents()
        -> [FirewallAuditEvent] {

        auditLog
    }


    public func clearAuditLog() {

        auditLog.removeAll()
    }
}


// ================================================================
// MARK: - Preset Rules
// ================================================================

public enum FirewallPresets {

    public static func blockTelnet()
        -> FirewallRule {

        FirewallRule(
            name: "Block Telnet",
            decision: .deny,
            direction: .outbound,
            port: 23,
            transport: .tcp,
            priority: 10
        )
    }


    public static func blockFTP()
        -> FirewallRule {

        FirewallRule(
            name: "Block FTP",
            decision: .deny,
            direction: .outbound,
            port: 21,
            transport: .tcp,
            priority: 10
        )
    }


    public static func monitorHTTPS()
        -> FirewallRule {

        FirewallRule(
            name: "Monitor HTTPS",
            decision: .monitor,
            direction: .outbound,
            port: 443,
            transport: .tcp,
            priority: 100
        )
    }


    public static func blockDomain(
        _ domain: String
    ) -> FirewallRule {

        FirewallRule(
            name: "Block \(domain)",
            decision: .deny,
            direction: .outbound,
            destinationDomain: domain,
            priority: 5
        )
    }
}


// ================================================================
// MARK: - Example
// ================================================================

public enum FirewallExample {

    public static func create()
        async {

        let firewall =
            AppleFirewallEngine(
                configuration:
                    FirewallConfiguration(
                        defaultOutbound: .allow,
                        defaultInbound: .deny,
                        enableLogging: true,
                        enableRateLimiting: true,
                        maximumEvents: 10_000,
                        defaultRateLimit: 100,
                        rateWindow: 60
                    )
            )


        await firewall.addRule(
            FirewallPresets.blockTelnet()
        )


        await firewall.addRule(
            FirewallPresets.blockFTP()
        )


        await firewall.addRule(
            FirewallPresets.blockDomain(
                "malicious.example"
            )
        )


        let flow =
            FirewallFlow(
                processName: "ExampleApp",
                processIdentifier: 1234,
                direction: .outbound,
                source:
                    FirewallEndpoint(
                        address: "192.168.1.20",
                        port: 50000
                    ),
                destination:
                    FirewallEndpoint(
                        address: "203.0.113.10",
                        port: 23
                    ),
                transport: .tcp,
                domain: nil,
                bytes: 512
            )


        let decision =
            await firewall.evaluate(
                flow
            )


        print(
            "Firewall decision:",
            decision.rawValue
        )


        let statistics =
            await firewall.getStatistics()

        print(
            "Inspected:",
            statistics.inspected
        )

        print(
            "Allowed:",
            statistics.allowed
        )

        print(
            "Denied:",
            statistics.denied
        )
    }
}
```

