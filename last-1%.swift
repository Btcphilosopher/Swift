```swift
//
//  LastOnePercentEnergyEngine.swift
//
//  iOS Last-1% Energy Recovery
//
//  Concept:
//  --------
//  When the device approaches critically low battery,
//  progressively reduce software energy consumption.
//
//  The engine can control behaviour INSIDE YOUR APP:
//
//  - Reduce rendering frequency
//  - Reduce animation
//  - Reduce polling
//  - Reduce network activity
//  - Reduce background computation
//  - Reduce camera processing
//  - Reduce sensor sampling
//  - Pause non-essential tasks
//  - Prefer cached data
//  - Reduce audio processing
//  - Reduce GPU workloads
//
//  It CANNOT directly:
//  - control battery charging current
//  - control battery voltage
//  - control Apple's BMS
//  - force regenerative charging
//  - force hardware charging behaviour
//
//  Those remain under iOS / hardware control.
//

import SwiftUI
import UIKit
import Combine

// MARK: - Energy State

enum EnergyState: String, CaseIterable {

    case normal
    case efficient
    case conservation
    case critical
    case emergency

    var title: String {

        switch self {
        case .normal:
            return "Normal"

        case .efficient:
            return "Efficient"

        case .conservation:
            return "Conservation"

        case .critical:
            return "Critical"

        case .emergency:
            return "Emergency"
        }
    }

    var icon: String {

        switch self {

        case .normal:
            return "battery.100"

        case .efficient:
            return "battery.75"

        case .conservation:
            return "battery.50"

        case .critical:
            return "battery.25"

        case .emergency:
            return "battery.0"
        }
    }
}

// MARK: - Energy Policy

struct EnergyPolicy {

    var animationScale: Double = 1.0

    var renderingScale: Double = 1.0

    var networkPollingInterval:
        TimeInterval = 5

    var sensorSamplingRate: Double = 1.0

    var backgroundWorkEnabled = true

    var heavyComputationEnabled = true

    var highQualityAudioEnabled = true

    var cameraProcessingEnabled = true

    var predictiveTasksEnabled = true

    var aggressiveCaching = false

    var preferLowPowerCodePaths = false
}

// MARK: - Battery Snapshot

struct BatterySnapshot {

    var level: Double = 1.0

    var isCharging = false

    var isFullyCharged = false

    var lowPowerMode = false

    var thermalState:
        ProcessInfo.ThermalState = .nominal

    var timestamp = Date()
}

// MARK: - Energy Saving Action

struct EnergySavingAction:
    Identifiable {

    let id = UUID()

    let name: String

    let reason: String

    let estimatedSaving:
        Double

    let enabled: Bool
}

// MARK: - Energy Engine

@MainActor
final class LastOnePercentEnergyEngine:
    ObservableObject {

    // MARK: Published

    @Published private(set) var battery =
        BatterySnapshot()

    @Published private(set) var state:
        EnergyState = .normal

    @Published private(set) var policy =
        EnergyPolicy()

    @Published private(set) var actions:
        [EnergySavingAction] = []

    @Published private(set) var estimatedRuntimeMultiplier:
        Double = 1.0

    @Published private(set) var energySavingScore:
        Double = 0

    // MARK: Timer

    private var timer: Timer?

    // MARK: Init

    init() {

        UIDevice.current
            .isBatteryMonitoringEnabled = true

        updateBattery()

        NotificationCenter.default.addObserver(
            self,
            selector:
                #selector(
                    batteryChanged
                ),
            name:
                UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector:
                #selector(
                    chargingChanged
                ),
            name:
                UIDevice.batteryStateDidChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector:
                #selector(
                    thermalChanged
                ),
            name:
                ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        timer =
            Timer.scheduledTimer(
                withTimeInterval: 10,
                repeats: true
            ) { [weak self] _ in

                Task { @MainActor in
                    self?.updateBattery()
                }
            }
    }

    deinit {

        NotificationCenter.default
            .removeObserver(self)

        timer?.invalidate()
    }

    // MARK: Battery

    private func updateBattery() {

        let level =
            UIDevice.current.batteryLevel

        let batteryState =
            UIDevice.current.batteryState

        battery.level =
            level >= 0
            ? Double(level)
            : 1.0

        battery.isCharging =
            batteryState == .charging ||
            batteryState == .full

        battery.isFullyCharged =
            batteryState == .full

        battery.lowPowerMode =
            ProcessInfo.processInfo
                .isLowPowerModeEnabled

        battery.thermalState =
            ProcessInfo.processInfo
                .thermalState

        battery.timestamp =
            Date()

        updateState()

        updatePolicy()

        updateActions()

        estimateRuntimeMultiplier()
    }

    // MARK: State

    private func updateState() {

        let level =
            battery.level

        if level <= 0.01 {

            state = .emergency

        } else if level <= 0.03 {

            state = .critical

        } else if level <= 0.10 {

            state = .conservation

        } else if level <= 0.25 {

            state = .efficient

        } else {

            state = .normal
        }
    }

    // MARK: Policy

    private func updatePolicy() {

        let level =
            battery.level

        policy =
            EnergyPolicy()

        // 25%

        if level <= 0.25 {

            policy.animationScale =
                0.75

            policy.renderingScale =
                0.90

            policy.networkPollingInterval =
                10

            policy.sensorSamplingRate =
                0.75
        }

        // 10%

        if level <= 0.10 {

            policy.animationScale =
                0.50

            policy.renderingScale =
                0.75

            policy.networkPollingInterval =
                20

            policy.sensorSamplingRate =
                0.50

            policy.predictiveTasksEnabled =
                false

            policy.preferLowPowerCodePaths =
                true
        }

        // 3%

        if level <= 0.03 {

            policy.animationScale =
                0.20

            policy.renderingScale =
                0.50

            policy.networkPollingInterval =
                60

            policy.sensorSamplingRate =
                0.20

            policy.backgroundWorkEnabled =
                false

            policy.heavyComputationEnabled =
                false

            policy.highQualityAudioEnabled =
                false

            policy.cameraProcessingEnabled =
                false

            policy.predictiveTasksEnabled =
                false

            policy.aggressiveCaching =
                true

            policy.preferLowPowerCodePaths =
                true
        }

        // Final 1%

        if level <= 0.01 {

            policy.animationScale =
                0

            policy.renderingScale =
                0.35

            policy.networkPollingInterval =
                120

            policy.sensorSamplingRate =
                0.10

            policy.backgroundWorkEnabled =
                false

            policy.heavyComputationEnabled =
                false

            policy.highQualityAudioEnabled =
                false

            policy.cameraProcessingEnabled =
                false

            policy.predictiveTasksEnabled =
                false

            policy.aggressiveCaching =
                true

            policy.preferLowPowerCodePaths =
                true
        }

        // Thermal override

        if battery.thermalState ==
            .serious ||
            battery.thermalState ==
            .critical {

            policy.animationScale *=
                0.5

            policy.renderingScale *=
                0.75

            policy.heavyComputationEnabled =
                false

            policy.cameraProcessingEnabled =
                false

            policy.preferLowPowerCodePaths =
                true
        }
    }

    // MARK: Actions

    private func updateActions() {

        var newActions:
            [EnergySavingAction] = []

        let level =
            battery.level

        if level <= 0.25 {

            newActions.append(
                EnergySavingAction(
                    name:
                        "Reduce Rendering",
                    reason:
                        "Lower GPU workload",
                    estimatedSaving:
                        0.05,
                    enabled: true
                )
            )
        }

        if level <= 0.10 {

            newActions.append(
                EnergySavingAction(
                    name:
                        "Slow Network Polling",
                    reason:
                        "Reduce radio wakeups",
                    estimatedSaving:
                        0.08,
                    enabled: true
                )
            )

            newActions.append(
                EnergySavingAction(
                    name:
                        "Reduce Sensor Sampling",
                    reason:
                        "Reduce sensor subsystem activity",
                    estimatedSaving:
                        0.04,
                    enabled: true
                )
            )

            newActions.append(
                EnergySavingAction(
                    name:
                        "Disable Predictive Tasks",
                    reason:
                        "Stop non-essential CPU work",
                    estimatedSaving:
                        0.07,
                    enabled: true
                )
            )
        }

        if level <= 0.03 {

            newActions.append(
                EnergySavingAction(
                    name:
                        "Suspend Background Work",
                    reason:
                        "Prioritise essential application functions",
                    estimatedSaving:
                        0.10,
                    enabled: true
                )
            )

            newActions.append(
                EnergySavingAction(
                    name:
                        "Disable Heavy DSP",
                    reason:
                        "Reduce CPU/GPU audio processing",
                    estimatedSaving:
                        0.05,
                    enabled: true
                )
            )
        }

        if level <= 0.01 {

            newActions.append(
                EnergySavingAction(
                    name:
                        "Final 1% Mode",
                    reason:
                        "Maximum application-level energy conservation",
                    estimatedSaving:
                        0.15,
                    enabled: true
                )
            )
        }

        actions =
            newActions
    }

    // MARK: Runtime Estimate

    private func estimateRuntimeMultiplier() {

        var multiplier = 1.0

        switch state {

        case .normal:
            multiplier = 1.0

        case .efficient:
            multiplier = 1.08

        case .conservation:
            multiplier = 1.18

        case .critical:
            multiplier = 1.35

        case .emergency:
            multiplier = 1.55
        }

        if battery.thermalState ==
            .serious {

            multiplier *= 1.10
        }

        if battery.thermalState ==
            .critical {

            multiplier *= 1.20
        }

        estimatedRuntimeMultiplier =
            multiplier
    }

    // MARK: Notifications

    @objc
    private func batteryChanged() {

        updateBattery()
    }

    @objc
    private func chargingChanged() {

        updateBattery()
    }

    @objc
    private func thermalChanged() {

        updateBattery()
    }

    // MARK: Public API

    func shouldRunHeavyComputation()
        -> Bool {

        policy.heavyComputationEnabled
    }

    func shouldRunBackgroundWork()
        -> Bool {

        policy.backgroundWorkEnabled
    }

    func shouldProcessCamera()
        -> Bool {

        policy.cameraProcessingEnabled
    }

    func networkInterval()
        -> TimeInterval {

        policy.networkPollingInterval
    }

    func animationScale()
        -> Double {

        policy.animationScale
    }

    func sensorRate()
        -> Double {

        policy.sensorSamplingRate
    }

    func recordEnergySaving(
        amount: Double
    ) {

        energySavingScore =
            min(
                100,
                energySavingScore +
                amount
            )
    }
}

// MARK: - Dashboard

struct LastOnePercentDashboard:
    View {

    @StateObject
    private var engine =
        LastOnePercentEnergyEngine()

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(
                    spacing: 18
                ) {

                    batteryCard

                    policyCard

                    actionsCard

                    runtimeCard
                }
                .padding()
            }
            .navigationTitle(
                "Energy Intelligence"
            )
        }
    }

    // MARK: Battery

    private var batteryCard:
        some View {

        VStack(
            spacing: 15
        ) {

            Image(
                systemName:
                    engine.state.icon
            )
            .font(
                .system(size: 48)
            )

            Text(
                "\(Int(engine.battery.level * 100))%"
            )
            .font(
                .system(
                    size: 42,
                    weight: .bold,
                    design: .rounded
                )
            )

            Text(
                engine.state.title
            )
            .font(.headline)

            ProgressView(
                value:
                    engine.battery.level
            )

            HStack {

                Label(
                    engine.battery.isCharging
                    ? "Charging"
                    : "Discharging",
                    systemImage:
                        engine.battery.isCharging
                        ? "bolt.fill"
                        : "bolt.slash"
                )

                Spacer()

                Label(
                    engine.battery.lowPowerMode
                    ? "Low Power Mode"
                    : "Normal Power",
                    systemImage:
                        "leaf"
                )
            }
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
        }
        .padding(24)
        .frame(
            maxWidth: .infinity
        )
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

    // MARK: Policy

    private var policyCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text(
                "Current Energy Policy"
            )
            .font(.headline)

            EnergyRow(
                name:
                    "Animation",
                value:
                    "\(Int(engine.policy.animationScale * 100))%"
            )

            EnergyRow(
                name:
                    "Rendering",
                value:
                    "\(Int(engine.policy.renderingScale * 100))%"
            )

            EnergyRow(
                name:
                    "Network polling",
                value:
                    "\(Int(engine.policy.networkPollingInterval)) sec"
            )

            EnergyRow(
                name:
                    "Sensor sampling",
                value:
                    "\(Int(engine.policy.sensorSamplingRate * 100))%"
            )

            EnergyRow(
                name:
                    "Heavy computation",
                value:
                    engine.policy
                        .heavyComputationEnabled
                    ? "Active"
                    : "Suspended"
            )

            EnergyRow(
                name:
                    "Background work",
                value:
                    engine.policy
                        .backgroundWorkEnabled
                    ? "Active"
                    : "Suspended"
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

    // MARK: Actions

    private var actionsCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            Text(
                "Active Conservation"
            )
            .font(.headline)

            ForEach(
                engine.actions
            ) { action in

                HStack {

                    Image(
                        systemName:
                            "checkmark.circle.fill"
                    )
                    .foregroundStyle(
                        .green
                    )

                    VStack(
                        alignment:
                            .leading
                    ) {

                        Text(
                            action.name
                        )

                        Text(
                            action.reason
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }

                    Spacer()
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

    // MARK: Runtime

    private var runtimeCard:
        some View {

        VStack(
            spacing: 8
        ) {

            Text(
                "Estimated Software Efficiency"
            )
            .font(.headline)

            Text(
                String(
                    format:
                        "%.2fx",
                    engine
                        .estimatedRuntimeMultiplier
                )
            )
            .font(
                .system(
                    size: 34,
                    weight: .bold,
                    design: .rounded
                )
            )

            Text(
                "Relative to the application's normal workload"
            )
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
        }
        .frame(
            maxWidth: .infinity
        )
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

// MARK: - Energy Row

struct EnergyRow:
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

// MARK: - Toolbar Widget

struct EnergyToolbarButton:
    View {

    @State
    private var showing =
        false

    @StateObject
    private var engine =
        LastOnePercentEnergyEngine()

    var body: some View {

        Button {

            showing.toggle()

        } label: {

            Image(
                systemName:
                    engine.state.icon
            )
        }
        .popover(
            isPresented:
                $showing
        ) {

            CompactEnergyDashboard(
                engine: engine
            )
            .frame(
                width: 330
            )
        }
    }
}

// MARK: - Compact Dashboard

struct CompactEnergyDashboard:
    View {

    @ObservedObject
    var engine:
        LastOnePercentEnergyEngine

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 15
        ) {

            HStack {

                Label(
                    "Energy",
                    systemImage:
                        engine.state.icon
                )
                .font(.headline)

                Spacer()

                Text(
                    "\(Int(engine.battery.level * 100))%"
                )
                .font(
                    .headline.monospacedDigit()
                )
            }

            ProgressView(
                value:
                    engine.battery.level
            )

            Divider()

            EnergyRow(
                name:
                    "Mode",
                value:
                    engine.state.title
            )

            EnergyRow(
                name:
                    "Rendering",
                value:
                    "\(Int(engine.policy.renderingScale * 100))%"
            )

            EnergyRow(
                name:
                    "Background",
                value:
                    engine.policy
                        .backgroundWorkEnabled
                    ? "Active"
                    : "Suspended"
            )

            EnergyRow(
                name:
                    "Heavy compute",
                value:
                    engine.policy
                        .heavyComputationEnabled
                    ? "Active"
                    : "Suspended"
            )

            if engine.state ==
                .critical ||
                engine.state ==
                .emergency {

                Label(
                    "Maximum conservation active",
                    systemImage:
                        "leaf.fill"
                )
                .font(.caption)
                .foregroundStyle(
                    .green
                )
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {

    LastOnePercentDashboard()
}
```


