```swift
//
//  AppleNetworkDiagnostics.swift
//
//  iOS Network Connectivity Intelligence
//
//  Uses public Apple APIs:
//  - Network.framework
//  - CoreTelephony
//  - SystemConfiguration
//  - SwiftUI
//
//  Reports:
//  - Active network path
//  - Wi-Fi / Cellular / Wired / Other
//  - Interface availability
//  - IPv4 / IPv6
//  - DNS availability
//  - Expensive connection
//  - Constrained connection
//  - Local interface addresses
//  - Route changes
//  - Connectivity latency
//  - Packet-loss style reachability tests
//  - Cellular carrier information where available
//
//  IMPORTANT:
//  iOS does NOT expose unrestricted modem engineering data to
//  ordinary apps. Raw RSRP/RSRQ/SINR and similar radio metrics
//  generally require privileged/internal APIs and should not be
//  assumed available to App Store applications.
//

import SwiftUI
import Network
import CoreTelephony
import Combine

// MARK: - Network Interface

enum NetworkInterfaceType: String, CaseIterable, Identifiable {
    case wifi
    case cellular
    case wiredEthernet
    case loopback
    case other
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        case .loopback:
            return "Loopback"
        case .other:
            return "Other"
        case .none:
            return "Offline"
        }
    }

    var icon: String {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .wiredEthernet:
            return "cable.connector"
        case .loopback:
            return "arrow.triangle.2.circlepath"
        case .other:
            return "network"
        case .none:
            return "wifi.slash"
        }
    }
}

// MARK: - Connectivity State

enum ConnectivityState: String {
    case connected
    case disconnected
    case requiresConnection
    case unknown

    var title: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .requiresConnection:
            return "Requires Connection"
        case .unknown:
            return "Unknown"
        }
    }
}

// MARK: - Network Quality

enum NetworkQuality: String {
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

// MARK: - Interface Information

struct NetworkInterfaceInfo: Identifiable {
    let id = UUID()

    var name: String
    var type: NetworkInterfaceType

    var ipv4Addresses: [String] = []
    var ipv6Addresses: [String] = []

    var supportsIPv4 = false
    var supportsIPv6 = false
}

// MARK: - Cellular Information

struct CellularInformation {

    var carrierName: String?
    var mobileCountryCode: String?
    var mobileNetworkCode: String?

    var radioAccessTechnology: String?

    var hasCellularService: Bool {
        carrierName != nil ||
        radioAccessTechnology != nil
    }
}

// MARK: - Connectivity Snapshot

struct NetworkSnapshot {

    var state: ConnectivityState =
        .unknown

    var interfaceType:
        NetworkInterfaceType = .none

    var interfaces:
        [NetworkInterfaceInfo] = []

    var supportsIPv4 = false
    var supportsIPv6 = false

    var dnsAvailable = false

    var isExpensive = false
    var isConstrained = false

    var localIPAddress: String?

    var cellular:
        CellularInformation = CellularInformation()

    var latencyMilliseconds: Double?

    var packetLossPercent: Double?

    var quality:
        NetworkQuality = .unavailable

    var timestamp = Date()
}

// MARK: - Network Diagnostics

@MainActor
final class NetworkDiagnostics:
    ObservableObject {

    // MARK: Published State

    @Published private(set) var snapshot =
        NetworkSnapshot()

    @Published private(set) var isMonitoring =
        false

    @Published private(set) var latency:
        Double?

    @Published private(set) var packetLoss:
        Double?

    @Published private(set) var quality:
        NetworkQuality = .unavailable

    // MARK: Network Monitor

    private let monitor =
        NWPathMonitor()

    private let monitorQueue =
        DispatchQueue(
            label: "AppleNetworkDiagnostics"
        )

    private var path:
        NWPath?

    private var timer:
        Timer?

    // MARK: Start

    func startMonitoring() {

        guard !isMonitoring else {
            return
        }

        isMonitoring = true

        monitor.pathUpdateHandler =
            { [weak self] path in

                Task { @MainActor in

                    self?.update(
                        from: path
                    )
                }
            }

        monitor.start(
            queue: monitorQueue
        )
    }

    // MARK: Stop

    func stopMonitoring() {

        monitor.cancel()

        timer?.invalidate()
        timer = nil

        isMonitoring = false
    }

    // MARK: Path Update

    private func update(
        from path: NWPath
    ) {

        self.path = path

        var newSnapshot =
            NetworkSnapshot()

        newSnapshot.timestamp =
            Date()

        // Connectivity

        switch path.status {

        case .satisfied:
            newSnapshot.state =
                .connected

        case .unsatisfied:
            newSnapshot.state =
                .disconnected

        case .requiresConnection:
            newSnapshot.state =
                .requiresConnection

        @unknown default:
            newSnapshot.state =
                .unknown
        }

        // Interface

        if path.usesInterfaceType(
            .wifi
        ) {

            newSnapshot.interfaceType =
                .wifi

        } else if path.usesInterfaceType(
            .cellular
        ) {

            newSnapshot.interfaceType =
                .cellular

        } else if path.usesInterfaceType(
            .wiredEthernet
        ) {

            newSnapshot.interfaceType =
                .wiredEthernet

        } else if path.status ==
                    .unsatisfied {

            newSnapshot.interfaceType =
                .none

        } else {

            newSnapshot.interfaceType =
                .other
        }

        // Capabilities

        newSnapshot.isExpensive =
            path.isExpensive

        newSnapshot.isConstrained =
            path.isConstrained

        newSnapshot.supportsIPv4 =
            path.supportsIPv4

        newSnapshot.supportsIPv6 =
            path.supportsIPv6

        newSnapshot.dnsAvailable =
            path.supportsDNS

        // Interfaces

        newSnapshot.interfaces =
            interfaceInformation()

        // Cellular

        newSnapshot.cellular =
            cellularInformation()

        // IP

        newSnapshot.localIPAddress =
            firstLocalAddress(
                interfaces:
                    newSnapshot.interfaces
            )

        // Quality

        newSnapshot.quality =
            calculateQuality(
                snapshot:
                    newSnapshot
            )

        snapshot =
            newSnapshot

        quality =
            newSnapshot.quality
    }

    // MARK: Interface Discovery

    private func interfaceInformation()
        -> [NetworkInterfaceInfo] {

        var results:
            [NetworkInterfaceInfo] = []

        let interfaces =
            SCNetworkInterfaceCopyAll()
            as? [SCNetworkInterface] ?? []

        // Network.framework provides the
        // logical path information.
        //
        // Low-level address enumeration is
        // intentionally kept separate.

        if path?.usesInterfaceType(.wifi)
            == true {

            results.append(
                NetworkInterfaceInfo(
                    name: "Wi-Fi",
                    type: .wifi,
                    supportsIPv4:
                        path?.supportsIPv4 ?? false,
                    supportsIPv6:
                        path?.supportsIPv6 ?? false
                )
            )
        }

        if path?.usesInterfaceType(.cellular)
            == true {

            results.append(
                NetworkInterfaceInfo(
                    name: "Cellular",
                    type: .cellular,
                    supportsIPv4:
                        path?.supportsIPv4 ?? false,
                    supportsIPv6:
                        path?.supportsIPv6 ?? false
                )
            )
        }

        if path?.usesInterfaceType(
            .wiredEthernet
        ) == true {

            results.append(
                NetworkInterfaceInfo(
                    name: "Ethernet",
                    type: .wiredEthernet,
                    supportsIPv4:
                        path?.supportsIPv4 ?? false,
                    supportsIPv6:
                        path?.supportsIPv6 ?? false
                )
            )
        }

        return results
    }

    // MARK: Cellular

    private func cellularInformation()
        -> CellularInformation {

        let info =
            CTTelephonyNetworkInfo()

        let carrier =
            info.serviceSubscriberCellularProviders?
                .values
                .first

        let technology =
            info.serviceCurrentRadioAccessTechnology?
                .values
                .first

        return CellularInformation(
            carrierName:
                carrier?.carrierName,

            mobileCountryCode:
                carrier?.mobileCountryCode,

            mobileNetworkCode:
                carrier?.mobileNetworkCode,

            radioAccessTechnology:
                readableRadioTechnology(
                    technology
                )
        )
    }

    private func readableRadioTechnology(
        _ technology: String?
    ) -> String? {

        guard let technology else {
            return nil
        }

        switch technology {

        case CTRadioAccessTechnologyLTE:
            return "LTE"

        case CTRadioAccessTechnologyNR:
            return "5G"

        case CTRadioAccessTechnologyNRNSA:
            return "5G NSA"

        case CTRadioAccessTechnologyWCDMA:
            return "3G"

        case CTRadioAccessTechnologyGPRS:
            return "GPRS"

        case CTRadioAccessTechnologyEdge:
            return "EDGE"

        default:
            return technology
        }
    }

    // MARK: Local IP

    private func firstLocalAddress(
        interfaces:
            [NetworkInterfaceInfo]
    ) -> String? {

        for interface in interfaces {

            if let address =
                interface.ipv4Addresses.first {

                return address
            }

            if let address =
                interface.ipv6Addresses.first {

                return address
            }
        }

        return nil
    }

    // MARK: Quality

    private func calculateQuality(
        snapshot:
            NetworkSnapshot
    ) -> NetworkQuality {

        guard snapshot.state ==
                .connected else {

            return .unavailable
        }

        if let latency =
            snapshot.latencyMilliseconds {

            switch latency {

            case 0..<30:
                return .excellent

            case 30..<80:
                return .good

            case 80..<180:
                return .fair

            default:
                return .poor
            }
        }

        if snapshot.isConstrained {
            return .fair
        }

        return .good
    }

    // MARK: Latency

    func measureLatency(
        host: String = "1.1.1.1",
        port: UInt16 = 443
    ) async {

        let start =
            DispatchTime.now()

        let connection =
            NWConnection(
                host:
                    NWEndpoint.Host(host),
                port:
                    NWEndpoint.Port(
                        rawValue: port
                    )!,
                using:
                    .tcp
            )

        await withCheckedContinuation {
            continuation
                in

                connection.stateUpdateHandler =
                    { state in

                        switch state {

                        case .ready:

                            let end =
                                DispatchTime.now()

                            let elapsed =
                                Double(
                                    end.uptimeNanoseconds
                                    -
                                    start.uptimeNanoseconds
                                )
                                / 1_000_000.0

                            Task { @MainActor in

                                self.latency =
                                    elapsed

                                self.snapshot
                                    .latencyMilliseconds =
                                    elapsed

                                self.snapshot.quality =
                                    self.calculateQuality(
                                        snapshot:
                                            self.snapshot
                                    )

                                self.quality =
                                    self.snapshot.quality
                            }

                            connection.cancel()

                            continuation.resume()

                        case .failed,
                             .cancelled:

                            connection.cancel()

                            continuation.resume()

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

    // MARK: Continuous Diagnostics

    func startDiagnostics() {

        startMonitoring()

        timer?.invalidate()

        timer =
            Timer.scheduledTimer(
                withTimeInterval: 5,
                repeats: true
            ) { [weak self] _ in

                guard let self else {
                    return
                }

                Task {

                    await self.measureLatency()
                }
            }
    }

    func stopDiagnostics() {

        timer?.invalidate()
        timer = nil

        stopMonitoring()
    }

    // MARK: Refresh

    func refresh() {

        guard let path else {
            return
        }

        update(
            from: path
        )
    }
}

// MARK: - Main Dashboard

struct NetworkDiagnosticsView:
    View {

    @StateObject
    private var network =
        NetworkDiagnostics()

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    spacing: 18
                ) {

                    connectionCard

                    qualityCard

                    interfaceCard

                    radioCard

                    protocolCard

                    diagnosticsCard
                }
                .padding()
            }
            .navigationTitle(
                "Network"
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    Button {

                        network.refresh()

                    } label: {

                        Image(
                            systemName:
                                "arrow.clockwise"
                        )
                    }
                }
            }
            .task {

                network
                    .startDiagnostics()
            }
        }
    }

    // MARK: Connection

    private var connectionCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack {

                Image(
                    systemName:
                        network.snapshot
                            .interfaceType
                            .icon
                )
                .font(.system(size: 28))

                VStack(
                    alignment: .leading
                ) {

                    Text(
                        network.snapshot
                            .interfaceType
                            .title
                    )
                    .font(.title3)
                    .fontWeight(
                        .semibold
                    )

                    Text(
                        network.snapshot
                            .state
                            .title
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                Circle()
                    .fill(
                        network.snapshot
                            .state
                            == .connected
                        ? .green
                        : .red
                    )
                    .frame(
                        width: 11,
                        height: 11
                    )
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

    // MARK: Quality

    private var qualityCard:
        some View {

        VStack(
            spacing: 14
        ) {

            Image(
                systemName:
                    network.quality.icon
            )
            .font(
                .system(size: 42)
            )

            Text(
                network.quality.title
            )
            .font(.title2)
            .fontWeight(
                .semibold
            )

            if let latency =
                network.latency {

                Text(
                    String(
                        format:
                            "%.1f ms latency",
                        latency
                    )
                )
                .font(.subheadline)
                .foregroundStyle(
                    .secondary
                )
            }

            if network.snapshot
                .isConstrained {

                Label(
                    "Low Data Mode",
                    systemImage:
                        "speedometer"
                )
                .font(.caption)
            }

            if network.snapshot
                .isExpensive {

                Label(
                    "Metered Connection",
                    systemImage:
                        "dollarsign.circle"
                )
                .font(.caption)
            }
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
                cornerRadius: 20,
                style: .continuous
            )
        )
    }

    // MARK: Interface

    private var interfaceCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text("Interfaces")
                .font(.headline)

            ForEach(
                network.snapshot.interfaces
            ) { interface in

                HStack {

                    Image(
                        systemName:
                            interface
                                .type
                                .icon
                    )

                    Text(interface.name)

                    Spacer()

                    if interface
                        .supportsIPv4 {

                        Text("IPv4")
                            .font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                    }

                    if interface
                        .supportsIPv6 {

                        Text("IPv6")
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

    // MARK: Cellular

    private var radioCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text("Cellular")
                .font(.headline)

            if let carrier =
                network.snapshot
                    .cellular
                    .carrierName {

                InfoRow(
                    name: "Carrier",
                    value: carrier
                )
            }

            if let technology =
                network.snapshot
                    .cellular
                    .radioAccessTechnology {

                InfoRow(
                    name: "Radio",
                    value: technology
                )
            }

            if carrierAvailable {

                Label(
                    "Cellular service available",
                    systemImage:
                        "antenna.radiowaves.left.and.right"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
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

    private var carrierAvailable:
        Bool {

        network.snapshot
            .cellular
            .hasCellularService
    }

    // MARK: Protocols

    private var protocolCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text("Network Protocols")
                .font(.headline)

            InfoRow(
                name: "IPv4",
                value:
                    network.snapshot
                        .supportsIPv4
                    ? "Available"
                    : "Unavailable"
            )

            InfoRow(
                name: "IPv6",
                value:
                    network.snapshot
                        .supportsIPv6
                    ? "Available"
                    : "Unavailable"
            )

            InfoRow(
                name: "DNS",
                value:
                    network.snapshot
                        .dnsAvailable
                    ? "Available"
                    : "Unavailable"
            )

            if let address =
                network.snapshot
                    .localIPAddress {

                InfoRow(
                    name: "Local Address",
                    value: address
                )
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

    // MARK: Diagnostics

    private var diagnosticsCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text("Diagnostics")
                .font(.headline)

            Button {

                Task {

                    await network
                        .measureLatency()
                }

            } label: {

                Label(
                    "Run Connectivity Test",
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

// MARK: - Info Row

struct InfoRow: View {

    let name: String
    let value: String

    var body: some View {

        HStack {

            Text(name)

            Spacer()

            Text(value)
                .foregroundStyle(
                    .secondary
                )
                .monospaced()
        }
        .font(.subheadline)
    }
}

// MARK: - Toolbar Widget

struct NetworkToolbarButton:
    View {

    @State
    private var showingPopover =
        false

    @StateObject
    private var network =
        NetworkDiagnostics()

    var body: some View {

        Button {

            showingPopover.toggle()

        } label: {

            Image(
                systemName:
                    network.snapshot
                        .interfaceType
                        .icon
            )
        }
        .popover(
            isPresented:
                $showingPopover
        ) {

            CompactNetworkDashboard(
                network: network
            )
            .frame(
                width: 340
            )
        }
        .task {

            network.startMonitoring()
        }
    }
}

// MARK: - Compact Dashboard

struct CompactNetworkDashboard:
    View {

    @ObservedObject
    var network:
        NetworkDiagnostics

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 15
        ) {

            HStack {

                Label(
                    network.snapshot
                        .interfaceType
                        .title,
                    systemImage:
                        network.snapshot
                            .interfaceType
                            .icon
                )
                .font(.headline)

                Spacer()

                Circle()
                    .fill(
                        network.snapshot
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
                        network.quality.title
                    )
                    .font(.title3)
                    .fontWeight(
                        .semibold
                    )

                    if let latency =
                        network.latency {

                        Text(
                            String(
                                format:
                                    "%.1f ms",
                                latency
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }

                Spacer()

                Image(
                    systemName:
                        network.quality.icon
                )
                .font(.system(size: 30))
            }

            if let radio =
                network.snapshot
                    .cellular
                    .radioAccessTechnology {

                InfoRow(
                    name: "Cellular",
                    value: radio
                )
            }

            InfoRow(
                name: "IPv4",
                value:
                    network.snapshot
                        .supportsIPv4
                    ? "Yes"
                    : "No"
            )

            InfoRow(
                name: "IPv6",
                value:
                    network.snapshot
                        .supportsIPv6
                    ? "Yes"
                    : "No"
            )

            Button {

                Task {

                    await network
                        .measureLatency()
                }

            } label: {

                Text("Test Connection")
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

// MARK: - Preview

#Preview {

    NetworkDiagnosticsView()
}
```


