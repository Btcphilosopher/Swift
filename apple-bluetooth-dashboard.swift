```swift
import SwiftUI
import CoreBluetooth

// ============================================================
// MARK: - Bluetooth Device Model
// ============================================================

public struct BluetoothDevice: Identifiable, Hashable {

    public let id: UUID

    public var name: String
    public var rssi: Int

    public var connected: Bool
    public var connecting: Bool

    public var batteryLevel: Int?

    public var isConnectable: Bool

    public var lastSeen: Date

    public init(
        id: UUID,
        name: String,
        rssi: Int = -100,
        connected: Bool = false,
        connecting: Bool = false,
        batteryLevel: Int? = nil,
        isConnectable: Bool = true,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.connected = connected
        self.connecting = connecting
        self.batteryLevel = batteryLevel
        self.isConnectable = isConnectable
        self.lastSeen = lastSeen
    }

    public var signalStrength: Double {

        switch rssi {
        case -60...0:
            return 1.0
        case -70..<(-60):
            return 0.75
        case -85..<(-70):
            return 0.45
        default:
            return 0.2
        }
    }
}


// ============================================================
// MARK: - Bluetooth Manager
// ============================================================

@MainActor
public final class BluetoothManager:
    NSObject,
    ObservableObject,
    CBCentralManagerDelegate
{

    @Published
    public private(set) var devices:
        [BluetoothDevice] = []

    @Published
    public private(set) var bluetoothState:
        CBManagerState = .unknown

    @Published
    public private(set) var scanning = false

    @Published
    public private(set) var selectedDevice:
        BluetoothDevice?

    private var central:
        CBCentralManager!

    private var peripherals:
        [UUID: CBPeripheral] = [:]

    public override init() {

        super.init()

        central =
            CBCentralManager(
                delegate: self,
                queue: nil
            )
    }

    // --------------------------------------------------------
    // MARK: Central Manager
    // --------------------------------------------------------

    public func centralManagerDidUpdateState(
        _ central: CBCentralManager
    ) {

        bluetoothState =
            central.state

        if central.state ==
            .poweredOn
        {
            startScanning()
        }
    }

    // --------------------------------------------------------
    // MARK: Scan
    // --------------------------------------------------------

    public func startScanning() {

        guard
            central.state ==
            .poweredOn
        else {
            return
        }

        scanning = true

        central.scanForPeripherals(
            withServices: nil,
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey:
                    false
            ]
        )
    }

    public func stopScanning() {

        central.stopScan()

        scanning = false
    }

    // --------------------------------------------------------
    // MARK: Discovery
    // --------------------------------------------------------

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData:
            [String : Any],
        rssi RSSI: NSNumber
    ) {

        let deviceID =
            peripheral.identifier

        peripherals[deviceID] =
            peripheral

        let advertisedName =
            advertisementData[
                CBAdvertisementDataLocalNameKey
            ] as? String

        let name =
            advertisedName ??
            peripheral.name ??
            "Bluetooth Device"

        let existingIndex =
            devices.firstIndex {
                $0.id == deviceID
            }

        if let index = existingIndex {

            devices[index].rssi =
                RSSI.intValue

            devices[index].lastSeen =
                Date()

            devices[index].name =
                name

        } else {

            let device =
                BluetoothDevice(

                    id: deviceID,

                    name: name,

                    rssi:
                        RSSI.intValue,

                    connected:
                        peripheral.state ==
                        .connected,

                    connecting:
                        peripheral.state ==
                        .connecting
                )

            devices.append(device)
        }
    }

    // --------------------------------------------------------
    // MARK: Connect
    // --------------------------------------------------------

    public func connect(
        _ device: BluetoothDevice
    ) {

        guard
            let peripheral =
                peripherals[device.id]
        else {
            return
        }

        updateDevice(
            id: device.id
        ) {
            $0.connecting = true
        }

        central.connect(
            peripheral,
            options: nil
        )
    }

    public func disconnect(
        _ device: BluetoothDevice
    ) {

        guard
            let peripheral =
                peripherals[device.id]
        else {
            return
        }

        central.cancelPeripheralConnection(
            peripheral
        )

        updateDevice(
            id: device.id
        ) {
            $0.connected = false
            $0.connecting = false
        }
    }

    // --------------------------------------------------------
    // MARK: Connection Callbacks
    // --------------------------------------------------------

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {

        updateDevice(
            id: peripheral.identifier
        ) {

            $0.connected = true
            $0.connecting = false
        }

        peripheral.delegate = self

        peripheral.discoverServices(nil)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {

        updateDevice(
            id: peripheral.identifier
        ) {

            $0.connected = false
            $0.connecting = false
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {

        updateDevice(
            id: peripheral.identifier
        ) {

            $0.connected = false
            $0.connecting = false
        }
    }

    // --------------------------------------------------------
    // MARK: Helpers
    // --------------------------------------------------------

    private func updateDevice(
        id: UUID,
        update:
            (inout BluetoothDevice) -> Void
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

    public func select(
        _ device: BluetoothDevice
    ) {

        selectedDevice =
            device
    }

    public var connectedDevices:
        [BluetoothDevice]
    {
        devices.filter {
            $0.connected
        }
    }
}


// ============================================================
// MARK: - Bluetooth Dashboard
// ============================================================

public struct BluetoothDashboard:
    View
{

    @ObservedObject
    private var manager:
        BluetoothManager

    @Binding
    private var isPresented: Bool

    public init(
        manager: BluetoothManager,
        isPresented: Binding<Bool>
    ) {

        self.manager = manager
        self._isPresented = isPresented
    }

    public var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            header

            Divider()
                .opacity(0.5)

            if manager.devices.isEmpty {

                emptyState

            } else {

                deviceList
            }

            Divider()
                .opacity(0.5)

            footer
        }
        .frame(
            width: 330
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
            color:
                .black.opacity(0.20),
            radius: 25,
            y: 10
        )
    }

    // ========================================================
    // MARK: Header
    // ========================================================

    private var header: some View {

        HStack {

            Image(
                systemName:
                    "wave.3.right.circle.fill"
            )
            .font(.title3)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {

                Text("Bluetooth")
                    .font(
                        .headline
                    )

                Text(
                    manager.bluetoothState ==
                    .poweredOn
                    ? "Available"
                    : "Unavailable"
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()

            Button {

                if manager.scanning {
                    manager.stopScanning()
                } else {
                    manager.startScanning()
                }

            } label: {

                Image(
                    systemName:
                        manager.scanning
                        ? "stop.circle"
                        : "arrow.clockwise"
                )
                .font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    // ========================================================
    // MARK: Device List
    // ========================================================

    private var deviceList: some View {

        ScrollView {

            LazyVStack(
                spacing: 4
            ) {

                ForEach(
                    manager.devices
                ) { device in

                    BluetoothDeviceRow(
                        device: device,
                        onConnect: {

                            manager.connect(
                                device
                            )
                        },
                        onDisconnect: {

                            manager.disconnect(
                                device
                            )
                        }
                    )
                }
            }
            .padding(8)
        }
        .frame(
            maxHeight: 330
        )
    }

    // ========================================================
    // MARK: Empty State
    // ========================================================

    private var emptyState: some View {

        VStack(spacing: 10) {

            Image(
                systemName:
                    "antenna.radiowaves.left.and.right"
            )
            .font(
                .system(size: 28)
            )
            .foregroundStyle(
                .secondary
            )

            Text(
                "No Bluetooth devices nearby"
            )
            .font(.subheadline)

            Text(
                "Searching for peripherals…"
            )
            .font(.caption)
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
    // MARK: Footer
    // ========================================================

    private var footer: some View {

        HStack {

            Text(
                "\(manager.connectedDevices.count) connected"
            )
            .font(.caption)
            .foregroundStyle(
                .secondary
            )

            Spacer()

            Button("Done") {

                isPresented = false
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(14)
    }
}


// ============================================================
// MARK: - Device Row
// ============================================================

public struct BluetoothDeviceRow:
    View
{

    let device:
        BluetoothDevice

    let onConnect:
        () -> Void

    let onDisconnect:
        () -> Void

    public var body: some View {

        HStack(spacing: 12) {

            deviceIcon

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

                HStack(spacing: 7) {

                    signalView

                    if let battery =
                        device.batteryLevel
                    {

                        Label(
                            "\(battery)%",
                            systemImage:
                                "battery.75"
                        )
                        .font(
                            .caption2
                        )
                    }

                    if device.connected {

                        Text("Connected")
                            .font(
                                .caption2
                            )
                            .foregroundStyle(
                                .green
                            )
                    }
                }
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()

            if device.connecting {

                ProgressView()
                    .controlSize(.small)

            } else {

                Button {

                    if device.connected {
                        onDisconnect()
                    } else {
                        onConnect()
                    }

                } label: {

                    Image(
                        systemName:
                            device.connected
                            ? "checkmark.circle.fill"
                            : "plus.circle"
                    )
                    .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(
            .horizontal,
            10
        )
        .padding(
            .vertical,
            9
        )
        .contentShape(
            Rectangle()
        )
    }

    private var deviceIcon:
        some View
    {

        Image(
            systemName:
                device.connected
                ? "wave.3.right"
                : "wave.3.right"
        )
        .frame(
            width: 28,
            height: 28
        )
        .foregroundStyle(
            device.connected
            ? .primary
            : .secondary
        )
    }

    private var signalView:
        some View
    {

        HStack(
            spacing: 1
        ) {

            ForEach(
                0..<4,
                id: \.self
            ) { index in

                RoundedRectangle(
                    cornerRadius: 1
                )
                .frame(
                    width: 3,
                    height:
                        CGFloat(
                            4 + index * 3
                        )
                )
                .opacity(
                    Double(index) / 4 <
                    device.signalStrength
                    ? 1
                    : 0.2
                )
            }
        }
    }
}


// ============================================================
// MARK: - Toolbar Bluetooth Button
// ============================================================

public struct BluetoothToolbarButton:
    View
{

    @ObservedObject
    public var manager:
        BluetoothManager

    @Binding
    public var showDashboard:
        Bool

    public init(
        manager: BluetoothManager,
        showDashboard: Binding<Bool>
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
            }

        } label: {

            Image(
                systemName:
                    manager.connectedDevices.isEmpty
                    ? "wave.3.right"
                    : "wave.3.right.circle.fill"
            )
            .font(
                .system(
                    size: 15,
                    weight: .medium
                )
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

            BluetoothDashboard(
                manager: manager,
                isPresented:
                    $showDashboard
            )
            .presentationCompactAdaptation(
                .popover
            )
        }
        .accessibilityLabel(
            "Bluetooth"
        )
    }
}


// ============================================================
// MARK: - Example Toolbar
// ============================================================

public struct AppleToolbarExample:
    View
{

    @StateObject
    private var bluetooth =
        BluetoothManager()

    @State
    private var showBluetooth =
        false

    public init() {}

    public var body: some View {

        NavigationStack {

            VStack {

                Text(
                    "Apple Device"
                )
                .font(
                    .largeTitle
                )

                Text(
                    "Bluetooth dashboard demo"
                )
                .foregroundStyle(
                    .secondary
                )
            }
            .navigationTitle(
                "Device"
            )
            .toolbar {

                ToolbarItem(
                    placement:
                        .topBarTrailing
                ) {

                    BluetoothToolbarButton(
                        manager:
                            bluetooth,
                        showDashboard:
                            $showBluetooth
                    )
                }
            }
        }
    }
}


// ============================================================
// MARK: - Preview
// ============================================================

#Preview {

    AppleToolbarExample()
}
```


