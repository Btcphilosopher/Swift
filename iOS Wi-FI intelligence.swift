```swift
//
//  WiFiConnectionIntelligence.swift
//
//  iOS Wi-Fi Connection Intelligence
//
//  Public Apple frameworks:
//  - Network
//  - NetworkExtension (optional capabilities)
//  - SwiftUI
//
//  Designed as the Wi-Fi intelligence layer of an
//  Apple-device diagnostics / connectivity system.
//
//  Measures / infers:
//  - Wi-Fi availability
//  - Active Wi-Fi path
//  - Connection transitions
//  - IPv4 / IPv6
//  - DNS availability
//  - Constrained network
//  - Expensive network
//  - TCP latency
//  - Connection stability
//  - Jitter
//  - Packet-loss-style failures
//  - Recent connection history
//  - Wi-Fi quality score
//  - Connection state
//
//  IMPORTANT:
//  iOS does not generally expose arbitrary Wi-Fi chipset
//  telemetry to ordinary apps. Do not assume access to
//  RSSI, noise floor, MCS, channel utilisation or PHY rate.
//  This implementation therefore derives connection quality
//  from observable network behaviour.
//

import SwiftUI
import Network
import Combine

// MARK: - Wi-Fi State

enum WiFiState: String {
    case disconnected
    case connecting
    case connected
    case degraded
    case unstable
    case unknown

    var title: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .degraded:
            return "Degraded"
        case .unstable:
            return "Unstable"
        case .unknown:
            return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .disconnected:
            return "wifi.slash"
        case .connecting:
            return "wifi.exclamationmark"
        case .connected:
            return "wifi"
        case .degraded:
            return "wifi.exclamationmark"
        case .unstable:
            return "wifi.exclamationmark"
        case .unknown:
            return "wifi"
        }
    }
}

// MARK: - Wi-Fi Quality

enum WiFiQuality: String {
    case excellent
    case good
    case fair
    case poor
    case unavailable

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .excellent:
            return "wifi"
        case .good:
            return "wifi"
        case .fair:
            return "wifi.exclamationmark"
        case .poor:
            return "wifi.exclamationmark"
        case .unavailable:
            return "wifi.slash"
        }
    }
}

// MARK: - Measurement

struct WiFiMeasurement: Identifiable {

    let id = UUID()

    let timestamp: Date

    let latencyMilliseconds: Double?

    let success: Bool

    let state: WiFiState
}

// MARK: - Connection Statistics

struct WiFiStatistics {

    var samples = 0

    var successfulSamples = 0

    var failedSamples = 0

    var averageLatency: Double = 0

    var minimumLatency: Double = 0

    var maximumLatency: Double = 0

    var jitter: Double = 0

    var packetLoss: Double = 0

    var stability: Double = 1.0
}

// MARK: - Wi-Fi Snapshot

struct WiFiSnapshot {

    var state: WiFiState = .unknown

    var quality: WiFiQuality =
        .unavailable

    var latencyMilliseconds:
        Double?

    var jitterMilliseconds:
        Double?

    var packetLossPercent:
        Double = 0

    var stabilityScore:
        Double = 0

    var supportsIPv4 = false

    var supportsIPv6 = false

    var supportsDNS = false

    var isExpensive = false

    var isConstrained = false

    var interfaceAvailable = false

    var timestamp = Date()
}

// MARK: - Wi-Fi Intelligence Engine

@MainActor
final class WiFiConnectionIntelligence:
    ObservableObject {

    // MARK: Published

    @Published private(set) var snapshot =
        WiFiSnapshot()

    @Published private(set) var statistics =
        WiFiStatistics()

    @Published private(set) var history:
        [WiFiMeasurement] = []

    @Published private(set) var isMonitoring =
        false

    @Published private(set) var lastTransition:
        Date?

    @Published private(set) var connectionCount =
        0

    // MARK: Network

    private let monitor =
        NWPathMonitor(
            requiredInterfaceType:
                .wifi
        )

    private let queue =
        DispatchQueue(
            label:
                "WiFiIntelligence"
        )

    private var currentPath:
        NWPath?

    private var monitorTimer:
        Timer?

    // MARK: Configuration

    var measurementInterval:
        TimeInterval = 5

    var historyLimit = 120

    var latencyHost = "1.1.1.1"

    var latencyPort: UInt16 = 443

    // MARK: Start

    func start() {

        guard !isMonitoring else {
            return
        }

        isMonitoring = true

        monitor.pathUpdateHandler =
            { [weak self] path in

                Task { @MainActor in

                    self?.handlePath(
                        path
                    )
                }
            }

        monitor.start(
            queue: queue
        )

        monitorTimer?.invalidate()

        monitorTimer =
            Timer.scheduledTimer(
                withTimeInterval:
                    measurementInterval,
                repeats: true
            ) { [weak self] _ in

                guard let self else {
                    return
                }

                Task {

                    await self
                        .measureConnection()
                }
            }
    }

    // MARK: Stop

    func stop() {

        monitor.cancel()

        monitorTimer?.invalidate()
        monitorTimer = nil

        isMonitoring = false
    }

    // MARK: Path

    private func handlePath(
        _ path: NWPath
    ) {

        let previousState =
            snapshot.state

        currentPath =
            path

        snapshot.supportsIPv4 =
            path.supportsIPv4

        snapshot.supportsIPv6 =
            path.supportsIPv6

        snapshot.supportsDNS =
            path.supportsDNS

        snapshot.isExpensive =
            path.isExpensive

        snapshot.isConstrained =
            path.isConstrained

        snapshot.interfaceAvailable =
            path.usesInterfaceType(
                .wifi
            )

        if path.status ==
            .satisfied {

            if path.usesInterfaceType(
                .wifi
            ) {

                snapshot.state =
                    .connected

            } else {

                snapshot.state =
                    .degraded
            }

        } else {

            snapshot.state =
                .disconnected
        }

        snapshot.timestamp =
            Date()

        if previousState !=
            snapshot.state {

            lastTransition =
                Date()

            if snapshot.state ==
                .connected {

                connectionCount += 1
            }
        }

        recomputeQuality()
    }

    // MARK: Active Measurement

    func measureConnection() async {

        guard
            snapshot.state ==
                .connected
        else {

            recordFailure()
            return
        }

        let start =
            DispatchTime.now()

        let connection =
            NWConnection(
                host:
                    NWEndpoint.Host(
                        latencyHost
                    ),
                port:
                    NWEndpoint.Port(
                        rawValue:
                            latencyPort
                    )!,
                using:
                    .tcp
            )

        await withCheckedContinuation {
            continuation in

            var completed = false

            connection.stateUpdateHandler =
                { [weak self] state in

                    guard !completed else {
                        return
                    }

                    switch state {

                    case .ready:

                        completed = true

                        let end =
                            DispatchTime.now()

                        let milliseconds =
                            Double(
                                end.uptimeNanoseconds
                                -
                                start.uptimeNanoseconds
                            )
                            / 1_000_000.0

                        Task { @MainActor in

                            self?.recordSuccess(
                                latency:
                                    milliseconds
                            )
                        }

                        connection.cancel()

                        continuation.resume()

                    case .failed:

                        completed = true

                        Task { @MainActor in

                            self?.recordFailure()
                        }

                        connection.cancel()

                        continuation.resume()

                    case .cancelled:

                        if !completed {

                            completed = true

                            Task { @MainActor in

                                self?.recordFailure()
                            }

                            continuation.resume()
                        }

                    default:
                        break
                    }
                }

            connection.start(
                queue:
                    DispatchQueue.global(
                        qos: .utility
                    )
            )
        }
    }

    // MARK: Success

    private func recordSuccess(
        latency: Double
    ) {

        let measurement =
            WiFiMeasurement(
                timestamp: Date(),
                latencyMilliseconds:
                    latency,
                success: true,
                state: .connected
            )

        append(
            measurement
        )

        statistics.samples += 1
        statistics.successfulSamples += 1

        snapshot.latencyMilliseconds =
            latency

        recomputeStatistics()

        recomputeQuality()
    }

    // MARK: Failure

    private func recordFailure() {

        let measurement =
            WiFiMeasurement(
                timestamp: Date(),
                latencyMilliseconds:
                    nil,
                success: false,
                state:
                    snapshot.state
            )

        append(
            measurement
        )

        statistics.samples += 1
        statistics.failedSamples += 1

        recomputeStatistics()

        recomputeQuality()
    }

    // MARK: History

    private func append(
        _ measurement:
            WiFiMeasurement
    ) {

        history.append(
            measurement
        )

        if history.count >
            historyLimit {

            history.removeFirst(
                history.count -
                historyLimit
            )
        }
    }

    // MARK: Statistics

    private func recomputeStatistics() {

        let recent =
            history.suffix(50)

        let successful =
            recent.compactMap {
                $0.latencyMilliseconds
            }

        let failures =
            recent.filter {
                !$0.success
            }.count

        guard !recent.isEmpty else {
            return
        }

        if !successful.isEmpty {

            statistics.averageLatency =
                successful.reduce(
                    0,
                    +
                )
                /
                Double(
                    successful.count
                )

            statistics.minimumLatency =
                successful.min()
                ?? 0

            statistics.maximumLatency =
                successful.max()
                ?? 0

            statistics.jitter =
                calculateJitter(
                    successful
                )
        }

        statistics.packetLoss =
            Double(failures)
            /
            Double(recent.count)
            * 100

        statistics.stability =
            max(
                0,
                min(
                    1,
                    1 -
                    statistics.packetLoss
                    / 100
                )
            )
    }

    // MARK: Jitter

    private func calculateJitter(
        _ values: [Double]
    ) -> Double {

        guard values.count > 1 else {
            return 0
        }

        var differences:
            [Double] = []

        for index in 1..<values.count {

            differences.append(
                abs(
                    values[index] -
                    values[index - 1]
                )
            )
        }

        return differences.reduce(
            0,
            +
        )
        /
        Double(
            differences.count
        )
    }

    // MARK: Quality

    private func recomputeQuality() {

        guard
            snapshot.state ==
                .connected
        else {

            snapshot.quality =
                .unavailable

            return
        }

        let latency =
            snapshot.latencyMilliseconds
            ?? statistics.averageLatency

        let loss =
            statistics.packetLoss

        let jitter =
            statistics.jitter

        // Composite quality model.
        //
        // This is an application-level estimate,
        // not Apple's official Wi-Fi signal score.

        var score = 100.0

        if latency > 30 {
            score -=
                min(
                    20,
                    (latency - 30) *
                    0.10
                )
        }

        if latency > 100 {
            score -= 20
        }

        if latency > 200 {
            score -= 20
        }

        score -=
            min(
                30,
                loss * 1.5
            )

        score -=
            min(
                15,
                jitter * 0.25
            )

        if snapshot.isConstrained {
            score -= 10
        }

        score =
            max(
                0,
                min(
                    100,
                    score
                )
            )

        switch score {

        case 85...:
            snapshot.quality =
                .excellent

        case 70..<85:
            snapshot.quality =
                .good

        case 45..<70:
            snapshot.quality =
                .fair

        default:
            snapshot.quality =
                .poor
        }

        if loss >= 20 ||
            jitter >= 100 {

            snapshot.state =
                .unstable
        } else if score < 45 {

            snapshot.state =
                .degraded
        } else {

            snapshot.state =
                .connected
        }

        snapshot.jitterMilliseconds =
            jitter

        snapshot.packetLossPercent =
            loss

        snapshot.stabilityScore =
            statistics.stability
    }

    // MARK: Reset

    func resetStatistics() {

        history.removeAll()

        statistics =
            WiFiStatistics()

        snapshot.latencyMilliseconds =
            nil

        snapshot.jitterMilliseconds =
            nil

        snapshot.packetLossPercent =
            0

        snapshot.stabilityScore =
            0
    }
}

// MARK: - Wi-Fi Dashboard

struct WiFiIntelligenceDashboard:
    View {

    @StateObject
    private var wifi =
        WiFiConnectionIntelligence()

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    spacing: 18
                ) {

                    statusCard

                    qualityCard

                    performanceCard

                    protocolCard

                    historyCard
                }
                .padding()
            }
            .navigationTitle(
                "Wi-Fi Intelligence"
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button {

                        Task {

                            await wifi
                                .measureConnection()
                        }

                    } label: {

                        Image(
                            systemName:
                                "arrow.clockwise"
                        )
                    }
                }
            }
            .task {

                wifi.start()
            }
            .onDisappear {

                wifi.stop()
            }
        }
    }

    // MARK: Status

    private var statusCard:
        some View {

        VStack(
            spacing: 14
        ) {

            Image(
                systemName:
                    wifi.snapshot
                        .quality
                        .icon
            )
            .font(
                .system(size: 45)
            )

            Text(
                wifi.snapshot
                    .state
                    .title
            )
            .font(.title2)
            .fontWeight(
                .semibold
            )

            Text(
                wifi.snapshot
                    .quality
                    .title
            )
            .font(.subheadline)
            .foregroundStyle(
                .secondary
            )

            HStack {

                Label(
                    "Wi-Fi",
                    systemImage:
                        "wifi"
                )

                Spacer()

                Circle()
                    .fill(
                        wifi.snapshot
                            .state
                            == .connected
                        ? .green
                        : .red
                    )
                    .frame(
                        width: 9,
                        height: 9
                    )
            }
            .font(.caption)
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(24)
        .background(
            .regularMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 24,
                style: .continuous
            )
        )
    }

    // MARK: Quality

    private var qualityCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 14
        ) {

            Text("Connection Quality")
                .font(.headline)

            QualityMeter(
                value:
                    qualityScore,
                label:
                    wifi.snapshot
                        .quality
                        .title
            )

            Divider()

            MetricRow(
                name: "Latency",
                value:
                    formatLatency(
                        wifi.snapshot
                            .latencyMilliseconds
                    )
            )

            MetricRow(
                name: "Jitter",
                value:
                    String(
                        format:
                            "%.1f ms",
                        wifi.statistics
                            .jitter
                    )
            )

            MetricRow(
                name: "Packet Loss",
                value:
                    String(
                        format:
                            "%.1f%%",
                        wifi.statistics
                            .packetLoss
                    )
            )

            MetricRow(
                name: "Stability",
                value:
                    "\(Int(wifi.statistics.stability * 100))%"
            )
        }
        .padding()
        .background(
            .regularMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }

    private var qualityScore:
        Double {

        switch wifi.snapshot.quality {

        case .excellent:
            return 1.0

        case .good:
            return 0.8

        case .fair:
            return 0.6

        case .poor:
            return 0.3

        case .unavailable:
            return 0
        }
    }

    // MARK: Performance

    private var performanceCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text("Connection Behaviour")
                .font(.headline)

            MetricRow(
                name: "Samples",
                value:
                    "\(wifi.statistics.samples)"
            )

            MetricRow(
                name: "Successful",
                value:
                    "\(wifi.statistics.successfulSamples)"
            )

            MetricRow(
                name: "Failed",
                value:
                    "\(wifi.statistics.failedSamples)"
            )

            MetricRow(
                name: "Average Latency",
                value:
                    String(
                        format:
                            "%.1f ms",
                        wifi.statistics
                            .averageLatency
                    )
            )

            MetricRow(
                name: "Minimum",
                value:
                    String(
                        format:
                            "%.1f ms",
                        wifi.statistics
                            .minimumLatency
                    )
            )

            MetricRow(
                name: "Maximum",
                value:
                    String(
                        format:
                            "%.1f ms",
                        wifi.statistics
                            .maximumLatency
                    )
            )

            MetricRow(
                name: "Connections",
                value:
                    "\(wifi.connectionCount)"
            )
        }
        .padding()
        .background(
            .regularMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }

    // MARK: Protocols

    private var protocolCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text("Network Path")
                .font(.headline)

            MetricRow(
                name: "IPv4",
                value:
                    wifi.snapshot
                        .supportsIPv4
                    ? "Available"
                    : "Unavailable"
            )

            MetricRow(
                name: "IPv6",
                value:
                    wifi.snapshot
                        .supportsIPv6
                    ? "Available"
                    : "Unavailable"
            )

            MetricRow(
                name: "DNS",
                value:
                    wifi.snapshot
                        .supportsDNS
                    ? "Available"
                    : "Unavailable"
            )

            MetricRow(
                name: "Low Data Mode",
                value:
                    wifi.snapshot
                        .isConstrained
                    ? "Active"
                    : "Off"
            )

            MetricRow(
                name: "Metered",
                value:
                    wifi.snapshot
                        .isExpensive
                    ? "Yes"
                    : "No"
            )
        }
        .padding()
        .background(
            .regularMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }

    // MARK: History

    private var historyCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack {

                Text("Recent Measurements")
                    .font(.headline)

                Spacer()

                Text(
                    "\(wifi.history.count)"
                )
                .foregroundStyle(
                    .secondary
                )
            }

            ForEach(
                wifi.history.suffix(8)
            ) { measurement in

                HStack {

                    Circle()
                        .fill(
                            measurement.success
                            ? .green
                            : .red
                        )
                        .frame(
                            width: 7,
                            height: 7
                        )

                    Text(
                        measurement.timestamp,
                        style: .time
                    )
                    .font(.caption)

                    Spacer()

                    if let latency =
                        measurement
                            .latencyMilliseconds {

                        Text(
                            String(
                                format:
                                    "%.1f ms",
                                latency
                            )
                        )
                        .font(
                            .caption.monospaced()
                        )
                    } else {

                        Text("Failed")
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                    }
                }
            }
        }
        .padding()
        .background(
            .regularMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
    }
}

// MARK: - Quality Meter

struct QualityMeter:
    View {

    let value: Double
    let label: String

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            HStack {

                Text(label)
                    .font(.title3)
                    .fontWeight(
                        .semibold
                    )

                Spacer()

                Text(
                    "\(Int(value * 100))"
                )
                .font(
                    .title3.monospacedDigit()
                )
            }

            GeometryReader {
                geometry in

                ZStack(
                    alignment: .leading
                ) {

                    Capsule()
                        .fill(
                            .secondary.opacity(
                                0.15
                            )
                        )

                    Capsule()
                        .fill(
                            .primary
                        )
                        .frame(
                            width:
                                geometry.size.width
                                * value
                        )
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Toolbar Control

struct WiFiToolbarButton:
    View {

    @State
    private var showing =
        false

    @StateObject
    private var wifi =
        WiFiConnectionIntelligence()

    var body: some View {

        Button {

            showing.toggle()

        } label: {

            Image(
                systemName:
                    wifi.snapshot
                        .quality
                        .icon
            )
        }
        .popover(
            isPresented:
                $showing
        ) {

            CompactWiFiDashboard(
                wifi: wifi
            )
            .frame(
                width: 340
            )
        }
        .task {

            wifi.start()
        }
    }
}

// MARK: - Compact Wi-Fi Dashboard

struct CompactWiFiDashboard:
    View {

    @ObservedObject
    var wifi:
        WiFiConnectionIntelligence

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 15
        ) {

            HStack {

                Label(
                    "Wi-Fi",
                    systemImage:
                        "wifi"
                )
                .font(.headline)

                Spacer()

                Circle()
                    .fill(
                        wifi.snapshot
                            .state
                            == .connected
                        ? .green
                        : .red
                    )
                    .frame(
                        width: 8,
                        height: 8
                    )
            }

            Divider()

            HStack {

                VStack(
                    alignment: .leading
                ) {

                    Text(
                        wifi.snapshot
                            .quality
                            .title
                    )
                    .font(.title3)
                    .fontWeight(
                        .semibold
                    )

                    Text(
                        String(
                            format:
                                "%.1f ms latency",
                            wifi.statistics
                                .averageLatency
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                Image(
                    systemName:
                        wifi.snapshot
                            .quality
                            .icon
                )
                .font(.system(size: 30))
            }

            MetricRow(
                name: "Jitter",
                value:
                    String(
                        format:
                            "%.1f ms",
                        wifi.statistics
                            .jitter
                    )
            )

            MetricRow(
                name: "Packet Loss",
                value:
                    String(
                        format:
                            "%.1f%%",
                        wifi.statistics
                            .packetLoss
                    )
            )

            MetricRow(
                name: "Stability",
                value:
                    "\(Int(wifi.statistics.stability * 100))%"
            )

            Button {

                Task {

                    await wifi
                        .measureConnection()
                }

            } label: {

                Label(
                    "Test Wi-Fi",
                    systemImage:
                        "waveform.path.ecg"
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(
                .borderedProminent
            )
        }
        .padding()
    }
}

// MARK: - Metric Row

struct MetricRow:
    View {

    let name: String
    let value: String

    var body: some View {

        HStack {

            Text(name)

            Spacer()

            Text(value)
                .font(
                    .subheadline.monospaced()
                )
                .foregroundStyle(
                    .secondary
                )
        }
    }
}

// MARK: - Formatting

private func formatLatency(
    _ value: Double?
) -> String {

    guard let value else {
        return "—"
    }

    return String(
        format:
            "%.1f ms",
        value
    )
}

// MARK: - Preview

#Preview {

    WiFiIntelligenceDashboard()
}
```


