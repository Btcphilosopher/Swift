```swift
import Foundation
import Network
import AVFoundation
import SwiftUI

// ============================================================
// WIFI-FIRST CALLING
// ============================================================

enum ConnectionPreference: String, CaseIterable {
    case wifiFirst
    case cellularFirst
    case wifiOnly
    case automatic
}

enum ConnectionTransport: String {
    case wifi
    case cellular
    case ethernet
    case unavailable
}

enum ConnectionQuality: String {
    case excellent
    case good
    case fair
    case poor
    case unavailable
}

// ============================================================
// NETWORK SNAPSHOT
// ============================================================

struct CallingNetworkSnapshot {
    let transport: ConnectionTransport
    let quality: ConnectionQuality

    let isConnected: Bool
    let isExpensive: Bool
    let isConstrained: Bool

    let supportsIPv4: Bool
    let supportsIPv6: Bool

    let timestamp: Date
}

// ============================================================
// CALLING POLICY
// ============================================================

struct CallingPolicy {

    var preference: ConnectionPreference = .wifiFirst

    // Wi-Fi is considered usable above this quality.
    var minimumWiFiQuality: ConnectionQuality = .fair

    // Permit cellular fallback.
    var allowCellularFallback: Bool = true

    // If Wi-Fi becomes unstable, permit switching.
    var allowAutomaticFailover: Bool = true

    // Avoid expensive cellular traffic where possible.
    var avoidExpensiveNetworks: Bool = true
}

// ============================================================
// NETWORK ENGINE
// ============================================================

@MainActor
final class WiFiFirstCallingEngine: ObservableObject {

    @Published private(set) var snapshot =
        CallingNetworkSnapshot(
            transport: .unavailable,
            quality: .unavailable,
            isConnected: false,
            isExpensive: false,
            isConstrained: false,
            supportsIPv4: false,
            supportsIPv6: false,
            timestamp: Date()
        )

    @Published private(set) var selectedTransport:
        ConnectionTransport = .unavailable

    @Published private(set) var isWiFiPreferred = true

    @Published private(set) var isCallingAvailable = false

    @Published private(set) var statusText =
        "Checking network…"

    var policy = CallingPolicy()

    private let monitor =
        NWPathMonitor()

    private let queue =
        DispatchQueue(
            label: "wifi-first-calling-monitor"
        )

    // ========================================================
    // START
    // ========================================================

    func start() {

        monitor.pathUpdateHandler = {
            [weak self] path in

            Task { @MainActor in
                self?.process(path)
            }
        }

        monitor.start(
            queue: queue
        )
    }

    func stop() {
        monitor.cancel()
    }

    // ========================================================
    // PATH ANALYSIS
    // ========================================================

    private func process(
        _ path: NWPath
    ) {

        let transport =
            determineTransport(path)

        let quality =
            estimateQuality(path)

        snapshot =
            CallingNetworkSnapshot(
                transport: transport,
                quality: quality,
                isConnected:
                    path.status == .satisfied,
                isExpensive:
                    path.isExpensive,
                isConstrained:
                    path.isConstrained,
                supportsIPv4:
                    path.supportsIPv4,
                supportsIPv6:
                    path.supportsIPv6,
                timestamp:
                    Date()
            )

        selectedTransport =
            chooseTransport(
                snapshot
            )

        isWiFiPreferred =
            policy.preference == .wifiFirst ||
            policy.preference == .wifiOnly

        isCallingAvailable =
            selectedTransport != .unavailable

        statusText =
            makeStatusText()
    }

    // ========================================================
    // TRANSPORT DETECTION
    // ========================================================

    private func determineTransport(
        _ path: NWPath
    ) -> ConnectionTransport {

        if path.usesInterfaceType(.wifi) {
            return .wifi
        }

        if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        }

        if path.usesInterfaceType(.cellular) {
            return .cellular
        }

        return .unavailable
    }

    // ========================================================
    // QUALITY ESTIMATION
    // ========================================================

    private func estimateQuality(
        _ path: NWPath
    ) -> ConnectionQuality {

        guard path.status == .satisfied else {
            return .unavailable
        }

        if path.usesInterfaceType(.wifi) {

            // NWPath does not expose raw Wi-Fi RSSI
            // to ordinary iOS applications.
            //
            // Therefore this is a policy-level estimate.
            //
            // A production system should combine this
            // with measured latency, jitter and packet loss.

            if path.isConstrained {
                return .fair
            }

            return .good
        }

        if path.usesInterfaceType(.cellular) {
            return .good
        }

        return .fair
    }

    // ========================================================
    // TRANSPORT SELECTION
    // ========================================================

    private func chooseTransport(
        _ network: CallingNetworkSnapshot
    ) -> ConnectionTransport {

        switch policy.preference {

        case .wifiOnly:

            guard
                network.transport == .wifi,
                network.quality != .poor
            else {
                return .unavailable
            }

            return .wifi

        case .wifiFirst:

            if network.transport == .wifi &&
                wifiIsUsable(network) {

                return .wifi
            }

            if policy.allowCellularFallback &&
                network.transport == .cellular {

                return .cellular
            }

            return .unavailable

        case .cellularFirst:

            if network.transport == .cellular {
                return .cellular
            }

            if network.transport == .wifi {
                return .wifi
            }

            return .unavailable

        case .automatic:

            if network.transport == .wifi &&
                wifiIsUsable(network) {

                return .wifi
            }

            if network.transport == .cellular {
                return .cellular
            }

            return .unavailable
        }
    }

    // ========================================================
    // WIFI QUALITY POLICY
    // ========================================================

    private func wifiIsUsable(
        _ network: CallingNetworkSnapshot
    ) -> Bool {

        switch network.quality {

        case .excellent:
            return true

        case .good:
            return true

        case .fair:
            return policy.minimumWiFiQuality != .excellent &&
                   policy.minimumWiFiQuality != .good

        case .poor:
            return false

        case .unavailable:
            return false
        }
    }

    // ========================================================
    // STATUS
    // ========================================================

    private func makeStatusText()
        -> String {

        switch selectedTransport {

        case .wifi:
            return "Calling over Wi-Fi"

        case .cellular:
            return "Calling over cellular"

        case .ethernet:
            return "Calling over Ethernet"

        case .unavailable:
            return "Calling unavailable"
        }
    }
}

// ============================================================
// VOIP CALL ENGINE
// ============================================================

@MainActor
final class VoIPCallEngine: ObservableObject {

    @Published private(set) var isCalling = false

    @Published private(set) var connection:
        ConnectionTransport = .unavailable

    private let network:
        WiFiFirstCallingEngine

    private let audioSession =
        AVAudioSession.sharedInstance()

    init(
        network:
        WiFiFirstCallingEngine
    ) {

        self.network = network
    }

    // ========================================================
    // AUDIO
    // ========================================================

    func configureAudio() throws {

        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [
                .allowBluetooth,
                .allowBluetoothA2DP,
                .defaultToSpeaker
            ]
        )

        try audioSession.setActive(
            true
        )
    }

    // ========================================================
    // START CALL
    // ========================================================

    func startCall() async throws {

        guard
            network.isCallingAvailable
        else {
            throw CallingError
                .networkUnavailable
        }

        try configureAudio()

        connection =
            network.selectedTransport

        isCalling = true

        /*
         Start your actual VoIP stack here.

         Examples:

             WebRTC
             SIP
             your own RTP/UDP stack
             CallKit-backed VoIP implementation

         The important architectural point is that
         the network engine has already selected Wi-Fi
         when Wi-Fi is preferred and usable.
        */
    }

    // ========================================================
    // END CALL
    // ========================================================

    func endCall() {

        isCalling = false

        connection =
            .unavailable

        try? audioSession.setActive(
            false
        )
    }
}

// ============================================================
// ERRORS
// ============================================================

enum CallingError: Error {

    case networkUnavailable

    case wifiUnavailable

    case audioUnavailable

    case callFailed
}

// ============================================================
// SWIFTUI DASHBOARD
// ============================================================

struct WiFiFirstCallingDashboard: View {

    @StateObject
    private var network =
        WiFiFirstCallingEngine()

    @StateObject
    private var callEngine:
        VoIPCallEngine

    init() {

        let engine =
            WiFiFirstCallingEngine()

        _network =
            StateObject(
                wrappedValue: engine
            )

        _callEngine =
            StateObject(
                wrappedValue:
                    VoIPCallEngine(
                        network: engine
                    )
            )
    }

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 20
        ) {

            HStack {

                Image(
                    systemName:
                        network.selectedTransport
                        == .wifi
                        ? "wifi"
                        : "antenna.radiowaves.left.and.right"
                )
                .font(.title)

                VStack(
                    alignment: .leading
                ) {

                    Text(
                        "Internet Calling"
                    )
                    .font(.headline)

                    Text(
                        network.statusText
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                Circle()
                    .fill(
                        network.isCallingAvailable
                        ? .green
                        : .red
                    )
                    .frame(
                        width: 10,
                        height: 10
                    )
            }

            Divider()

            HStack {

                Text("Preferred network")

                Spacer()

                Text("Wi-Fi")
                    .fontWeight(.semibold)
            }

            HStack {

                Text("Current connection")

                Spacer()

                Text(
                    network
                        .selectedTransport
                        .rawValue
                        .capitalized
                )
                .fontWeight(.semibold)
            }

            HStack {

                Text("Wi-Fi quality")

                Spacer()

                Text(
                    network
                        .snapshot
                        .quality
                        .rawValue
                        .capitalized
                )
            }

            Divider()

            Button {

                Task {

                    try? await
                        callEngine
                        .startCall()
                }

            } label: {

                Label(
                    "Start Internet Call",
                    systemImage:
                        "phone.fill"
                )
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(
                .borderedProminent
            )
            .disabled(
                !network.isCallingAvailable ||
                callEngine.isCalling
            )

            if callEngine.isCalling {

                Button {

                    callEngine.endCall()

                } label: {

                    Label(
                        "End Call",
                        systemImage:
                            "phone.down.fill"
                    )
                    .frame(
                        maxWidth: .infinity
                    )
                }
                .buttonStyle(
                    .bordered
                )
            }
        }
        .padding(24)
        .frame(
            width: 380
        )
        .onAppear {

            network.start()
        }
        .onDisappear {

            network.stop()
        }
    }
}

// ============================================================
// SIMPLE PREFERENCE MODEL
// ============================================================

struct InternetCallingPreferences {

    var preferWiFi = true

    var allowCellularFallback = true

    var wifiOnly = false

    var avoidExpensiveCellular = true
}

// ============================================================
// EXAMPLE
// ============================================================

struct WiFiCallingExample: View {

    var body: some View {

        WiFiFirstCallingDashboard()
    }
}
```


