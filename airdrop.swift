```swift
import SwiftUI
import MultipeerConnectivity
import UniformTypeIdentifiers

// ============================================================
// MARK: - Nearby Device
// ============================================================

public struct NearbyDevice:
    Identifiable,
    Hashable
{
    public let id: MCPeerID

    public var name: String
    public var state: MCSessionState

    public var isConnected: Bool {
        state == .connected
    }

    public init(
        id: MCPeerID,
        name: String,
        state: MCSessionState
    ) {
        self.id = id
        self.name = name
        self.state = state
    }
}


// ============================================================
// MARK: - Transfer
// ============================================================

public enum TransferDirection {
    case sending
    case receiving
}

public enum TransferState {
    case preparing
    case transferring
    case completed
    case failed
    case cancelled
}

public struct NearbyTransfer:
    Identifiable
{
    public let id = UUID()

    public let fileName: String
    public let fileSize: Int64

    public let direction:
        TransferDirection

    public var progress: Double
    public var state:
        TransferState

    public let peerName: String
}


// ============================================================
// MARK: - Nearby Share Manager
// ============================================================

@MainActor
public final class NearbyShareManager:
    NSObject,
    ObservableObject
{

    // --------------------------------------------------------
    // Service configuration
    // --------------------------------------------------------

    private let serviceType =
        "apple-share"

    private let discoveryInfo = [
        "type": "nearby-share"
    ]

    // --------------------------------------------------------
    // Multipeer objects
    // --------------------------------------------------------

    private let peerID:
        MCPeerID

    private let session:
        MCSession

    private var advertiser:
        MCNearbyServiceAdvertiser

    private var browser:
        MCNearbyServiceBrowser

    // --------------------------------------------------------
    // Published state
    // --------------------------------------------------------

    @Published
    public private(set) var devices:
        [NearbyDevice] = []

    @Published
    public private(set) var transfers:
        [NearbyTransfer] = []

    @Published
    public private(set) var isDiscovering =
        false

    @Published
    public private(set) var isAdvertising =
        false

    // --------------------------------------------------------
    // Initialisation
    // --------------------------------------------------------

    public override init() {

        peerID =
            MCPeerID(
                displayName:
                    Host.current().localizedName ??
                    "Apple Device"
            )

        session =
            MCSession(
                peer: peerID,
                securityIdentity: nil,
                encryptionPreference: .required
            )

        advertiser =
            MCNearbyServiceAdvertiser(
                peer: peerID,
                discoveryInfo: [
                    "type": "nearby-share"
                ],
                serviceType: "apple-share"
            )

        browser =
            MCNearbyServiceBrowser(
                peer: peerID,
                serviceType: "apple-share"
            )

        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    // ========================================================
    // MARK: Discovery
    // ========================================================

    public func start() {

        startAdvertising()
        startBrowsing()
    }

    public func stop() {

        stopAdvertising()
        stopBrowsing()

        session.disconnect()
    }

    public func startAdvertising() {

        advertiser.startAdvertisingPeer()

        isAdvertising = true
    }

    public func stopAdvertising() {

        advertiser.stopAdvertisingPeer()

        isAdvertising = false
    }

    public func startBrowsing() {

        browser.startBrowsingForPeers()

        isDiscovering = true
    }

    public func stopBrowsing() {

        browser.stopBrowsingForPeers()

        isDiscovering = false
    }

    // ========================================================
    // MARK: Invite
    // ========================================================

    public func connect(
        to device: NearbyDevice
    ) {

        browser.invitePeer(
            device.id,
            to: session,
            withContext: nil,
            timeout: 15
        )
    }

    public func disconnect(
        from device: NearbyDevice
    ) {

        session.disconnect()

        updateDevice(
            id: device.id
        ) {
            $0.state = .notConnected
        }
    }

    // ========================================================
    // MARK: Send Data
    // ========================================================

    public func send(
        data: Data,
        fileName: String,
        to device: NearbyDevice
    ) {

        guard
            device.isConnected
        else {
            return
        }

        let transfer =
            NearbyTransfer(

                fileName: fileName,

                fileSize:
                    Int64(data.count),

                direction: .sending,

                progress: 0,

                state: .preparing,

                peerName:
                    device.name
            )

        transfers.append(
            transfer
        )

        guard
            let index =
                transfers.lastIndex(
                    where: {
                        $0.id ==
                        transfer.id
                    }
                )
        else {
            return
        }

        transfers[index].state =
            .transferring

        do {

            try session.send(
                data,
                toPeers: [device.id],
                with: .reliable
            )

            transfers[index].progress =
                1.0

            transfers[index].state =
                .completed

        } catch {

            transfers[index].state =
                .failed
        }
    }

    // ========================================================
    // MARK: Send File
    // ========================================================

    public func sendFile(
        url: URL,
        to device: NearbyDevice
    ) {

        guard device.isConnected else {
            return
        }

        let transfer =
            NearbyTransfer(

                fileName:
                    url.lastPathComponent,

                fileSize:
                    fileSize(url),

                direction: .sending,

                progress: 0,

                state: .preparing,

                peerName:
                    device.name
            )

        transfers.append(
            transfer
        )

        session.sendResource(
            at: url,
            withName:
                url.lastPathComponent,
            toPeer:
                device.id
        ) { [weak self] error in

            Task { @MainActor in

                guard
                    let self
                else {
                    return
                }

                guard
                    let index =
                        self.transfers.lastIndex(
                            where: {
                                $0.id ==
                                transfer.id
                            }
                        )
                else {
                    return
                }

                if error == nil {

                    self.transfers[index].progress =
                        1.0

                    self.transfers[index].state =
                        .completed

                } else {

                    self.transfers[index].state =
                        .failed
                }
            }
        }
    }

    // ========================================================
    // MARK: File Size
    // ========================================================

    private func fileSize(
        _ url: URL
    ) -> Int64 {

        do {

            let attributes =
                try FileManager.default
                    .attributesOfItem(
                        atPath:
                            url.path
                    )

            return
                attributes[
                    .size
                ] as? Int64 ?? 0

        } catch {

            return 0
        }
    }

    // ========================================================
    // MARK: Device Management
    // ========================================================

    private func updateDevice(
        id: MCPeerID,
        update:
            (inout NearbyDevice) -> Void
    ) {

        guard
            let index =
                devices.firstIndex(
                    where: {
                        $0.id == id
                    }
                )
        else {
            return
        }

        update(
            &devices[index]
        )
    }

    private func addDevice(
        _ peer: MCPeerID
    ) {

        if devices.contains(
            where: {
                $0.id == peer
            }
        ) {
            return
        }

        devices.append(

            NearbyDevice(
                id: peer,
                name: peer.displayName,
                state: .notConnected
            )
        )
    }

    private func removeDevice(
        _ peer: MCPeerID
    ) {

        devices.removeAll {
            $0.id == peer
        }
    }
}


// ============================================================
// MARK: - MCSessionDelegate
// ============================================================

extension NearbyShareManager:
    MCSessionDelegate
{

    public nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {

        Task { @MainActor in

            guard
                let index =
                    self.devices.firstIndex(
                        where: {
                            $0.id == peerID
                        }
                    )
            else {
                return
            }

            self.devices[index].state =
                state
        }
    }

    public nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {

        Task { @MainActor in

            let transfer =
                NearbyTransfer(

                    fileName:
                        "Received Data",

                    fileSize:
                        Int64(data.count),

                    direction:
                        .receiving,

                    progress: 1.0,

                    state: .completed,

                    peerName:
                        peerID.displayName
                )

            self.transfers.append(
                transfer
            )

            // Process the received data here.
            //
            // Example:
            // let image = UIImage(data: data)
            //
            // Or write it to a file.
        }
    }

    public nonisolated func session(
        _ session: MCSession,
        didReceive stream:
            InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {

        // Handle streaming transfers here.
    }

    public nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName
            resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {

        Task { @MainActor in

            let transfer =
                NearbyTransfer(

                    fileName:
                        resourceName,

                    fileSize: 0,

                    direction:
                        .receiving,

                    progress: 0,

                    state:
                        .transferring,

                    peerName:
                        peerID.displayName
                )

            self.transfers.append(
                transfer
            )
        }
    }

    public nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName
            resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {

        Task { @MainActor in

            let transfer =
                NearbyTransfer(

                    fileName:
                        resourceName,

                    fileSize:
                        0,

                    direction:
                        .receiving,

                    progress:
                        error == nil
                        ? 1
                        : 0,

                    state:
                        error == nil
                        ? .completed
                        : .failed,

                    peerName:
                        peerID.displayName
                )

            self.transfers.append(
                transfer
            )

            if let localURL {

                print(
                    "Received file:",
                    localURL
                )
            }
        }
    }
}


// ============================================================
// MARK: - Advertiser Delegate
// ============================================================

extension NearbyShareManager:
    MCNearbyServiceAdvertiserDelegate
{

    public nonisolated func advertiser(
        _ advertiser:
            MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer
            peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler:
            @escaping (Bool, MCSession?) -> Void
    ) {

        Task { @MainActor in

            self.addDevice(peerID)

            // In a production sharing UI, present
            // a user confirmation sheet here.
            //
            // Do not silently accept arbitrary
            // connection requests.

            invitationHandler(
                true,
                self.session
            )
        }
    }

    public nonisolated func advertiser(
        _ advertiser:
            MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer
            error: Error
    ) {

        print(
            "Advertising error:",
            error
        )
    }
}


// ============================================================
// MARK: - Browser Delegate
// ============================================================

extension NearbyShareManager:
    MCNearbyServiceBrowserDelegate
{

    public nonisolated func browser(
        _ browser:
            MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info:
            [String : String]?
    ) {

        Task { @MainActor in

            self.addDevice(peerID)
        }
    }

    public nonisolated func browser(
        _ browser:
            MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {

        Task { @MainActor in

            self.removeDevice(peerID)
        }
    }

    public nonisolated func browser(
        _ browser:
            MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers
            error: Error
    ) {

        print(
            "Browsing error:",
            error
        )
    }
}


// ============================================================
// MARK: - AirDrop Dashboard
// ============================================================

public struct AirDropDashboard:
    View
{

    @ObservedObject
    private var manager:
        NearbyShareManager

    @Binding
    private var isPresented:
        Bool

    public init(
        manager:
            NearbyShareManager,
        isPresented:
            Binding<Bool>
    ) {

        self.manager = manager
        self._isPresented =
            isPresented
    }

    public var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            header

            Divider()

            if manager.devices.isEmpty {

                emptyState

            } else {

                deviceList
            }

            Divider()

            footer
        }
        .frame(
            width: 340
        )
        .background(
            .regularMaterial,
            in:
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
        )
        .shadow(
            radius: 24,
            y: 10
        )
    }

    // ========================================================
    // Header
    // ========================================================

    private var header:
        some View
    {

        HStack {

            Image(
                systemName:
                    "airplayaudio"
            )
            .font(.title3)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text(
                    "AirDrop"
                )
                .font(.headline)

                Text(
                    manager.isDiscovering
                    ? "Looking for nearby devices"
                    : "Nearby sharing"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()

            Button {

                if manager.isDiscovering {
                    manager.stop()
                } else {
                    manager.start()
                }

            } label: {

                Image(
                    systemName:
                        manager.isDiscovering
                        ? "stop.circle"
                        : "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // ========================================================
    // Device List
    // ========================================================

    private var deviceList:
        some View
    {

        ScrollView {

            LazyVStack(
                spacing: 4
            ) {

                ForEach(
                    manager.devices
                ) { device in

                    NearbyDeviceRow(
                        device: device
                    ) {

                        if device.isConnected {

                            manager.disconnect(
                                from: device
                            )

                        } else {

                            manager.connect(
                                to: device
                            )
                        }
                    }
                }
            }
            .padding(8)
        }
        .frame(
            maxHeight: 300
        )
    }

    // ========================================================
    // Empty State
    // ========================================================

    private var emptyState:
        some View
    {

        VStack(spacing: 12) {

            Image(
                systemName:
                    "iphone.radiowaves.left.and.right"
            )
            .font(
                .system(size: 32)
            )
            .foregroundStyle(
                .secondary
            )

            Text(
                "No nearby devices"
            )
            .font(
                .subheadline.weight(
                    .medium
                )
            )

            Text(
                "Keep the other device nearby and make sure the app is open."
            )
            .font(.caption)
            .multilineTextAlignment(
                .center
            )
            .foregroundStyle(
                .secondary
            )
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(30)
    }

    // ========================================================
    // Footer
    // ========================================================

    private var footer:
        some View
    {

        HStack {

            Image(
                systemName:
                    "person.2.wave.2"
            )

            Text(
                "\(manager.devices.count) nearby"
            )
            .font(.caption)
            .foregroundStyle(
                .secondary
            )

            Spacer()

            Button("Done") {

                isPresented = false
            }
        }
        .padding(14)
    }
}


// ============================================================
// MARK: - Device Row
// ============================================================

public struct NearbyDeviceRow:
    View
{

    let device:
        NearbyDevice

    let action:
        () -> Void

    public var body: some View {

        HStack(spacing: 12) {

            ZStack {

                Circle()
                    .fill(
                        Color.secondary.opacity(
                            0.12
                        )
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )

                Image(
                    systemName:
                        deviceIcon
                )
                .font(.title3)
            }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {

                Text(
                    device.name
                )
                .font(
                    .subheadline.weight(
                        .medium
                    )
                )
                .lineLimit(1)

                Text(
                    connectionText
                )
                .font(.caption)
                .foregroundStyle(
                    device.isConnected
                    ? .green
                    : .secondary
                )
            }

            Spacer()

            Button(
                action: action
            ) {

                Image(
                    systemName:
                        device.isConnected
                        ? "checkmark.circle.fill"
                        : "arrow.up.circle"
                )
                .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    private var connectionText:
        String
    {

        switch device.state {

        case .connected:
            return "Connected"

        case .connecting:
            return "Connecting…"

        default:
            return "Nearby"
        }
    }

    private var deviceIcon:
        String
    {

        let name =
            device.name.lowercased()

        if name.contains("iphone") {
            return "iphone"
        }

        if name.contains("ipad") {
            return "ipad"
        }

        if name.contains("mac") {
            return "laptopcomputer"
        }

        if name.contains("watch") {
            return "applewatch"
        }

        return "iphone.radiowaves.left.and.right"
    }
}


// ============================================================
// MARK: - Toolbar Button
// ============================================================

public struct AirDropToolbarButton:
    View
{

    @ObservedObject
    public var manager:
        NearbyShareManager

    @Binding
    public var showDashboard:
        Bool

    public init(
        manager:
            NearbyShareManager,
        showDashboard:
            Binding<Bool>
    ) {

        self.manager = manager
        self._showDashboard =
            showDashboard
    }

    public var body: some View {

        Button {

            withAnimation(
                .spring(
                    response: 0.28,
                    dampingFraction: 0.82
                )
            ) {

                showDashboard.toggle()

                if showDashboard {

                    manager.start()
                }
            }

        } label: {

            Image(
                systemName:
                    "airplayaudio"
            )
            .frame(
                width: 32,
                height: 32
            )
        }
        .buttonStyle(.plain)
        .popover(
            isPresented:
                $showDashboard,
            attachmentAnchor:
                .point(.bottom),
            arrowEdge: .top
        ) {

            AirDropDashboard(
                manager: manager,
                isPresented:
                    $showDashboard
            )
            .presentationCompactAdaptation(
                .popover
            )
        }
        .accessibilityLabel(
            "AirDrop"
        )
    }
}


// ============================================================
// MARK: - Example App
// ============================================================

public struct AirDropExample:
    View
{

    @StateObject
    private var manager =
        NearbyShareManager()

    @State
    private var showAirDrop =
        false

    public init() {}

    public var body: some View {

        NavigationStack {

            VStack(spacing: 20) {

                Image(
                    systemName:
                        "iphone.radiowaves.left.and.right"
                )
                .font(
                    .system(size: 60)
                )

                Text(
                    "Nearby Sharing"
                )
                .font(.largeTitle)

                Text(
                    "Open this app on another device to test nearby discovery."
                )
                .multilineTextAlignment(
                    .center
                )
                .foregroundStyle(
                    .secondary
                )
            }
            .padding()
            .navigationTitle(
                "Device"
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    AirDropToolbarButton(
                        manager:
                            manager,

                        showDashboard:
                            $showAirDrop
                    )
                }
            }
        }
    }
}
```

