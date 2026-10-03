```swift
//
//  MacBookMemoryClearingEngine.swift
//
//  Adaptive memory-pressure management for macOS.
//  Designed as a safe user-space component.
//
//  IMPORTANT:
//  - macOS owns global physical-memory management.
//  - This engine does NOT attempt to forcibly erase other processes'
//    memory or interfere with the VM subsystem.
//  - It primarily:
//      1. Monitors memory pressure.
//      2. Reclaims this application's caches.
//      3. Responds to memory-pressure notifications.
//      4. Performs controlled cleanup.
//      5. Escalates actions when pressure persists.
//      6. Produces telemetry for predictive maintenance.
//

import Foundation
import os

#if os(macOS)

public final class MacBookMemoryClearingEngine {

    // MARK: - Types

    public enum MemoryPressureLevel: String {
        case normal
        case warning
        case critical
    }

    public enum CleanupLevel: Int, Comparable {
        case none = 0
        case light = 1
        case moderate = 2
        case aggressive = 3

        public static func < (
            lhs: CleanupLevel,
            rhs: CleanupLevel
        ) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct MemorySnapshot {
        public let timestamp: Date

        public let physicalMemory: UInt64
        public let freeMemory: UInt64
        public let activeMemory: UInt64
        public let inactiveMemory: UInt64
        public let compressedMemory: UInt64
        public let wiredMemory: UInt64

        public let usedMemory: UInt64
        public let usageRatio: Double

        public let pressure: MemoryPressureLevel
    }

    public struct CleanupResult {
        public let timestamp: Date
        public let level: CleanupLevel

        public let beforeUsed: UInt64
        public let afterUsed: UInt64

        public let reclaimed: UInt64

        public let pressureBefore: MemoryPressureLevel
        public let pressureAfter: MemoryPressureLevel

        public let actions: [String]
    }

    // MARK: - Configuration

    public struct Configuration {

        /// Begin light cleanup above this fraction of physical RAM.
        public var lightThreshold: Double = 0.75

        /// Begin moderate cleanup above this fraction.
        public var moderateThreshold: Double = 0.85

        /// Enter aggressive application cleanup above this fraction.
        public var aggressiveThreshold: Double = 0.93

        /// Minimum time between automatic cleanups.
        public var minimumCleanupInterval: TimeInterval = 10

        /// Maximum number of historical snapshots.
        public var maximumHistory: Int = 300

        public init() {}
    }

    // MARK: - Properties

    private let configuration: Configuration

    private let logger = Logger(
        subsystem: "com.example.MacBookMemoryEngine",
        category: "Memory"
    )

    private var pressureSource: DispatchSourceMemoryPressure?

    private var monitoringTimer: DispatchSourceTimer?

    private let queue = DispatchQueue(
        label: "com.example.MacBookMemoryEngine",
        qos: .utility
    )

    private var lastCleanup: Date?

    private var history: [MemorySnapshot] = []

    private var cleanupHandlers: [() -> Void] = []

    // MARK: - Initialisation

    public init(
        configuration: Configuration = Configuration()
    ) {
        self.configuration = configuration
    }

    deinit {
        stop()
    }

    // MARK: - Start / Stop

    public func start() {

        startMemoryPressureMonitor()

        startTelemetryMonitor()

        logger.info("MacBook memory engine started.")
    }

    public func stop() {

        pressureSource?.cancel()
        pressureSource = nil

        monitoringTimer?.cancel()
        monitoringTimer = nil

        logger.info("MacBook memory engine stopped.")
    }

    // MARK: - Memory Pressure Monitor

    private func startMemoryPressureMonitor() {

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [
                .warning,
                .critical
            ],
            queue: queue
        )

        source.setEventHandler { [weak self] in

            guard let self else {
                return
            }

            let event = source.data

            if event.contains(.critical) {

                self.logger.warning(
                    "Critical memory pressure detected."
                )

                self.performCleanup(
                    level: .aggressive
                )

            } else if event.contains(.warning) {

                self.logger.warning(
                    "Memory pressure warning detected."
                )

                self.performCleanup(
                    level: .moderate
                )
            }
        }

        source.setCancelHandler {
            // Nothing required.
        }

        source.resume()

        pressureSource = source
    }

    // MARK: - Telemetry

    private func startTelemetryMonitor() {

        let timer = DispatchSource.makeTimerSource(
            queue: queue
        )

        timer.schedule(
            deadline: .now(),
            repeating: .seconds(5)
        )

        timer.setEventHandler { [weak self] in

            guard let self else {
                return
            }

            let snapshot = self.captureSnapshot()

            self.history.append(snapshot)

            if self.history.count >
                self.configuration.maximumHistory {

                self.history.removeFirst(
                    self.history.count -
                    self.configuration.maximumHistory
                )
            }

            self.evaluate(snapshot)
        }

        timer.resume()

        monitoringTimer = timer
    }

    // MARK: - Snapshot

    public func captureSnapshot() -> MemorySnapshot {

        let physical = ProcessInfo.processInfo.physicalMemory

        let stats = readVMStatistics()

        let active = stats.active
        let inactive = stats.inactive
        let compressed = stats.compressed
        let wired = stats.wired
        let free = stats.free

        let used =
            physical > free
            ? physical - free
            : 0

        let ratio =
            physical > 0
            ? Double(used) / Double(physical)
            : 0

        let pressure: MemoryPressureLevel

        if ratio >= configuration.aggressiveThreshold {

            pressure = .critical

        } else if ratio >= configuration.moderateThreshold {

            pressure = .warning

        } else {

            pressure = .normal
        }

        return MemorySnapshot(
            timestamp: Date(),
            physicalMemory: physical,
            freeMemory: free,
            activeMemory: active,
            inactiveMemory: inactive,
            compressedMemory: compressed,
            wiredMemory: wired,
            usedMemory: used,
            usageRatio: ratio,
            pressure: pressure
        )
    }

    // MARK: - Evaluation

    private func evaluate(
        _ snapshot: MemorySnapshot
    ) {

        let requiredLevel: CleanupLevel

        switch snapshot.pressure {

        case .normal:

            requiredLevel = .none

        case .warning:

            if snapshot.usageRatio >=
                configuration.aggressiveThreshold {

                requiredLevel = .aggressive

            } else {

                requiredLevel = .moderate
            }

        case .critical:

            requiredLevel = .aggressive
        }

        guard requiredLevel > .none else {
            return
        }

        performCleanup(
            level: requiredLevel
        )
    }

    // MARK: - Cleanup

    public func performCleanup(
        level: CleanupLevel
    ) {

        queue.async { [weak self] in

            guard let self else {
                return
            }

            if let lastCleanup = self.lastCleanup {

                let elapsed =
                    Date().timeIntervalSince(lastCleanup)

                if elapsed <
                    self.configuration.minimumCleanupInterval {

                    return
                }
            }

            self.lastCleanup = Date()

            let before = self.captureSnapshot()

            var actions: [String] = []

            switch level {

            case .none:

                break

            case .light:

                self.runLightCleanup()

                actions.append(
                    "Application-level light cleanup"
                )

            case .moderate:

                self.runLightCleanup()
                self.runRegisteredCleanupHandlers()

                actions.append(
                    "Application cache cleanup"
                )

                actions.append(
                    "Registered resource cleanup"
                )

            case .aggressive:

                self.runLightCleanup()
                self.runRegisteredCleanupHandlers()

                actions.append(
                    "Aggressive application cache cleanup"
                )

                actions.append(
                    "Registered resource cleanup"
                )
            }

            // Allow the system a short period to react.
            Thread.sleep(
                forTimeInterval: 0.25
            )

            let after = self.captureSnapshot()

            let reclaimed =
                before.usedMemory > after.usedMemory
                ? before.usedMemory - after.usedMemory
                : 0

            let result = CleanupResult(
                timestamp: Date(),
                level: level,
                beforeUsed: before.usedMemory,
                afterUsed: after.usedMemory,
                reclaimed: reclaimed,
                pressureBefore: before.pressure,
                pressureAfter: after.pressure,
                actions: actions
            )

            self.logCleanup(result)
        }
    }

    // MARK: - Light Cleanup

    private func runLightCleanup() {

        autoreleasepool {

            // Encourage destruction of temporary Foundation objects.
            //
            // The scope of autoreleasepool is intentionally local.
            //
            // Do not attempt to manipulate another process's memory.

            URLCache.shared.removeAllCachedResponses()
        }

        logger.debug(
            "Light application cleanup completed."
        )
    }

    // MARK: - Registered Cleanup

    public func registerCleanupHandler(
        _ handler: @escaping () -> Void
    ) {

        queue.async { [weak self] in

            self?.cleanupHandlers.append(handler)
        }
    }

    private func runRegisteredCleanupHandlers() {

        for handler in cleanupHandlers {

            autoreleasepool {

                handler()
            }
        }
    }

    // MARK: - VM Statistics

    private struct VMStatistics {

        let free: UInt64
        let active: UInt64
        let inactive: UInt64
        let compressed: UInt64
        let wired: UInt64
    }

    private func readVMStatistics()
        -> VMStatistics {

        var stats = vm_statistics64()

        var count =
            mach_msg_type_number_t(
                MemoryLayout<vm_statistics64_data_t>.stride /
                MemoryLayout<integer_t>.stride
            )

        let result = withUnsafeMutablePointer(
            to: &stats
        ) {

            $0.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {

                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    $0,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {

            return VMStatistics(
                free: 0,
                active: 0,
                inactive: 0,
                compressed: 0,
                wired: 0
            )
        }

        let pageSize =
            UInt64(
                vm_kernel_page_size
            )

        return VMStatistics(
            free:
                UInt64(stats.free_count) *
                pageSize,

            active:
                UInt64(stats.active_count) *
                pageSize,

            inactive:
                UInt64(stats.inactive_count) *
                pageSize,

            compressed:
                UInt64(stats.compressor_page_count) *
                pageSize,

            wired:
                UInt64(stats.wire_count) *
                pageSize
        )
    }

    // MARK: - History

    public func memoryHistory()
        -> [MemorySnapshot] {

        queue.sync {
            history
        }
    }

    // MARK: - Statistics

    public func currentUsageRatio()
        -> Double {

        captureSnapshot().usageRatio
    }

    public func currentPressure()
        -> MemoryPressureLevel {

        captureSnapshot().pressure
    }

    // MARK: - Logging

    private func logCleanup(
        _ result: CleanupResult
    ) {

        let reclaimedMB =
            Double(result.reclaimed) /
            1024.0 /
            1024.0

        logger.info(
            """
            Memory cleanup completed.
            Level: \(result.level.rawValue)
            Reclaimed: \(reclaimedMB, format: .fixed(precision: 1)) MB
            Pressure: \(result.pressureBefore.rawValue) -> \(result.pressureAfter.rawValue)
            """
        )
    }
}

// MARK: - Formatting

public extension MacBookMemoryClearingEngine.MemorySnapshot {

    var physicalMemoryGB: Double {

        Double(physicalMemory) /
        1024.0 /
        1024.0 /
        1024.0
    }

    var usedMemoryGB: Double {

        Double(usedMemory) /
        1024.0 /
        1024.0 /
        1024.0
    }

    var freeMemoryGB: Double {

        Double(freeMemory) /
        1024.0 /
        1024.0 /
        1024.0
    }

    var usagePercentage: Double {

        usageRatio * 100.0
    }
}

// MARK: - Predictive Maintenance Integration

public final class MacBookMemoryHealthMonitor {

    private let engine:
        MacBookMemoryClearingEngine

    public init(
        engine: MacBookMemoryClearingEngine
    ) {

        self.engine = engine
    }

    public struct HealthReport {

        public let usagePercentage: Double
        public let pressure:
            MacBookMemoryClearingEngine.MemoryPressureLevel

        public let averageUsage: Double
        public let peakUsage: Double

        public let sustainedPressure: Bool
    }

    public func generateReport()
        -> HealthReport {

        let snapshot =
            engine.captureSnapshot()

        let history =
            engine.memoryHistory()

        let values =
            history.map(\.usageRatio)

        let average =
            values.isEmpty
            ? snapshot.usageRatio
            : values.reduce(0, +) /
              Double(values.count)

        let peak =
            values.max()
            ?? snapshot.usageRatio

        let recent =
            values.suffix(12)

        let sustained =
            recent.count >= 6 &&
            recent.allSatisfy {
                $0 >= 0.85
            }

        return HealthReport(
            usagePercentage:
                snapshot.usagePercentage,

            pressure:
                snapshot.pressure,

            averageUsage:
                average * 100.0,

            peakUsage:
                peak * 100.0,

            sustainedPressure:
                sustained
        )
    }
}

// MARK: - Example

final class ExampleMemorySystem {

    private let engine =
        MacBookMemoryClearingEngine()

    func start() {

        engine.registerCleanupHandler {

            // Example application-owned cache.

            print(
                "Application cache cleanup requested."
            )
        }

        engine.start()
    }
}

#endif
```

