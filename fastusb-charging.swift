```swift
//
// FastUSBChargingEngine.swift
//
// Software intelligence layer for fast USB-C charging
// on Apple platforms.
//
// NOTE:
// Swift does not normally have direct access to USB-C PD negotiation,
// charger voltage/current registers, or the device's battery-management
// controller. Actual charging negotiation remains under Apple's hardware
// and operating-system control.
//
// This engine therefore optimises:
//   - charging policy
//   - thermal behaviour
//   - workload reduction while charging
//   - battery-aware performance
//   - charging-session telemetry
//   - estimated charging power
//   - charging efficiency
//

import Foundation
import Combine
import UIKit

// MARK: - USB-C Power State

enum USBCPowerState: String {
    case disconnected
    case connected
    case charging
    case full
    case thermalLimited
    case unknown
}

// MARK: - Charging Mode

enum FastChargeMode: String {
    case normal
    case fast
    case thermalLimited
    case batteryProtection
    case efficiency
}

// MARK: - Charger Type

enum USBChargerClass: String {
    case unknown
    case lowPower
    case standard
    case highPower
    case fastUSBPD
}

// MARK: - Thermal State

enum ChargingThermalState: String {
    case cool
    case normal
    case warm
    case hot
    case critical
}

// MARK: - USB-C Telemetry

struct USBCTelemetry {

    let timestamp: Date

    var batteryLevel: Double
    var isCharging: Bool

    var estimatedInputPowerWatts: Double
    var estimatedVoltage: Double
    var estimatedCurrent: Double

    var deviceTemperatureCelsius: Double
    var thermalState: ChargingThermalState

    var cpuLoad: Double
    var gpuLoad: Double

    var lowPowerMode: Bool

    var chargerClass: USBChargerClass
}

// MARK: - Charging Policy

struct ChargingPolicy {

    var targetBatteryLevel: Double

    var maximumThermalTemperature: Double

    var reducePerformanceWhileHot: Bool

    var enableFastCharging: Bool

    var protectBatteryAboveTarget: Bool

    var maximumEstimatedPower: Double

    static let balanced = ChargingPolicy(
        targetBatteryLevel: 0.80,
        maximumThermalTemperature: 38.0,
        reducePerformanceWhileHot: true,
        enableFastCharging: true,
        protectBatteryAboveTarget: true,
        maximumEstimatedPower: 100.0
    )

    static let performance = ChargingPolicy(
        targetBatteryLevel: 1.00,
        maximumThermalTemperature: 40.0,
        reducePerformanceWhileHot: true,
        enableFastCharging: true,
        protectBatteryAboveTarget: false,
        maximumEstimatedPower: 140.0
    )

    static let batteryProtection = ChargingPolicy(
        targetBatteryLevel: 0.80,
        maximumThermalTemperature: 35.0,
        reducePerformanceWhileHot: true,
        enableFastCharging: false,
        protectBatteryAboveTarget: true,
        maximumEstimatedPower: 65.0
    )
}

// MARK: - Charging Recommendation

struct ChargingRecommendation {

    let mode: FastChargeMode

    let targetPowerWatts: Double

    let reduceWorkload: Bool

    let estimatedChargingRatePerHour: Double

    let reason: String
}

// MARK: - Charging Session

struct ChargingSession {

    let startDate: Date

    var startingBatteryLevel: Double
    var currentBatteryLevel: Double

    var accumulatedEnergyWh: Double
    var estimatedAveragePower: Double

    var maximumTemperature: Double

    var samples: Int

    var duration: TimeInterval {
        Date().timeIntervalSince(startDate)
    }
}

// MARK: - Fast USB-C Charging Engine

@MainActor
final class FastUSBChargingEngine: ObservableObject {

    @Published private(set) var telemetry: USBCTelemetry?

    @Published private(set) var recommendation: ChargingRecommendation?

    @Published private(set) var session: ChargingSession?

    @Published private(set) var mode: FastChargeMode = .normal

    private var timer: Timer?

    private var policy: ChargingPolicy

    init(policy: ChargingPolicy = .balanced) {

        self.policy = policy

        UIDevice.current.isBatteryMonitoringEnabled = true

        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: Monitoring

    func startMonitoring() {

        timer?.invalidate()

        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in

            Task { @MainActor in
                self?.update()
            }
        }

        update()
    }

    func stopMonitoring() {

        timer?.invalidate()
        timer = nil
    }

    // MARK: Telemetry

    private func update() {

        let battery = UIDevice.current.batteryLevel

        let isCharging =
            UIDevice.current.batteryState == .charging ||
            UIDevice.current.batteryState == .full

        let thermal = ProcessInfo.processInfo.thermalState

        let thermalState = convertThermalState(thermal)

        let estimatedPower = estimateInputPower(
            batteryLevel: battery,
            isCharging: isCharging
        )

        let voltage = estimateVoltage(
            power: estimatedPower
        )

        let current = estimateCurrent(
            power: estimatedPower,
            voltage: voltage
        )

        let chargerClass = classifyCharger(
            estimatedPower: estimatedPower,
            isCharging: isCharging
        )

        let sample = USBCTelemetry(
            timestamp: Date(),
            batteryLevel: Double(max(0, battery)),
            isCharging: isCharging,
            estimatedInputPowerWatts: estimatedPower,
            estimatedVoltage: voltage,
            estimatedCurrent: current,
            deviceTemperatureCelsius: estimateTemperature(
                thermalState: thermalState
            ),
            thermalState: thermalState,
            cpuLoad: 0,
            gpuLoad: 0,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            chargerClass: chargerClass
        )

        telemetry = sample

        if isCharging {

            if session == nil {

                session = ChargingSession(
                    startDate: Date(),
                    startingBatteryLevel: Double(max(0, battery)),
                    currentBatteryLevel: Double(max(0, battery)),
                    accumulatedEnergyWh: 0,
                    estimatedAveragePower: estimatedPower,
                    maximumTemperature: sample.deviceTemperatureCelsius,
                    samples: 1
                )

            } else {

                updateSession(with: sample)
            }

        } else {

            session = nil
        }

        recommendation = calculateRecommendation(
            telemetry: sample
        )
    }

    // MARK: Recommendation Engine

    private func calculateRecommendation(
        telemetry: USBCTelemetry
    ) -> ChargingRecommendation {

        if !telemetry.isCharging {

            mode = .normal

            return ChargingRecommendation(
                mode: .normal,
                targetPowerWatts: 0,
                reduceWorkload: false,
                estimatedChargingRatePerHour: 0,
                reason: "USB-C charging is not active."
            )
        }

        if telemetry.thermalState == .critical {

            mode = .thermalLimited

            return ChargingRecommendation(
                mode: .thermalLimited,
                targetPowerWatts: 20,
                reduceWorkload: true,
                estimatedChargingRatePerHour: 10,
                reason: "Thermal conditions require charging and workload reduction."
            )
        }

        if telemetry.deviceTemperatureCelsius >
            policy.maximumThermalTemperature {

            mode = .thermalLimited

            return ChargingRecommendation(
                mode: .thermalLimited,
                targetPowerWatts: 30,
                reduceWorkload: true,
                estimatedChargingRatePerHour: 15,
                reason: "Device temperature is above the preferred fast-charge range."
            )
        }

        if policy.protectBatteryAboveTarget &&
            telemetry.batteryLevel >= policy.targetBatteryLevel {

            mode = .batteryProtection

            return ChargingRecommendation(
                mode: .batteryProtection,
                targetPowerWatts: 5,
                reduceWorkload: false,
                estimatedChargingRatePerHour: 1,
                reason: "Battery protection target has been reached."
            )
        }

        if telemetry.lowPowerMode {

            mode = .efficiency

            return ChargingRecommendation(
                mode: .efficiency,
                targetPowerWatts: min(
                    telemetry.estimatedInputPowerWatts,
                    45
                ),
                reduceWorkload: true,
                estimatedChargingRatePerHour: 20,
                reason: "Low Power Mode is active."
            )
        }

        if policy.enableFastCharging {

            mode = .fast

            return ChargingRecommendation(
                mode: .fast,
                targetPowerWatts: min(
                    telemetry.estimatedInputPowerWatts,
                    policy.maximumEstimatedPower
                ),
                reduceWorkload: false,
                estimatedChargingRatePerHour: estimateChargingRate(
                    power: telemetry.estimatedInputPowerWatts
                ),
                reason: "Conditions are suitable for fast charging."
            )
        }

        mode = .normal

        return ChargingRecommendation(
            mode: .normal,
            targetPowerWatts: 45,
            reduceWorkload: false,
            estimatedChargingRatePerHour: 20,
            reason: "Balanced charging mode."
        )
    }

    // MARK: Charger Classification

    private func classifyCharger(
        estimatedPower: Double,
        isCharging: Bool
    ) -> USBChargerClass {

        guard isCharging else {
            return .unknown
        }

        switch estimatedPower {

        case 0..<10:
            return .lowPower

        case 10..<30:
            return .standard

        case 30..<60:
            return .highPower

        default:
            return .fastUSBPD
        }
    }

    // MARK: Power Estimation

    private func estimateInputPower(
        batteryLevel: Float,
        isCharging: Bool
    ) -> Double {

        guard isCharging else {
            return 0
        }

        //
        // IMPORTANT:
        // This is an estimation model.
        //
        // A normal third-party iOS/macOS application does not receive
        // arbitrary USB-PD negotiation telemetry.
        //

        switch UIDevice.current.batteryState {

        case .charging:
            return batteryLevel < 0.80 ? 60 : 30

        case .full:
            return 5

        default:
            return 0
        }
    }

    private func estimateVoltage(
        power: Double
    ) -> Double {

        guard power > 0 else {
            return 0
        }

        if power >= 60 {
            return 15.0
        }

        if power >= 30 {
            return 9.0
        }

        return 5.0
    }

    private func estimateCurrent(
        power: Double,
        voltage: Double
    ) -> Double {

        guard voltage > 0 else {
            return 0
        }

        return power / voltage
    }

    // MARK: Thermal Intelligence

    private func convertThermalState(
        _ state: ProcessInfo.ThermalState
    ) -> ChargingThermalState {

        switch state {

        case .nominal:
            return .cool

        case .fair:
            return .normal

        case .serious:
            return .hot

        case .critical:
            return .critical

        @unknown default:
            return .normal
        }
    }

    private func estimateTemperature(
        thermalState: ChargingThermalState
    ) -> Double {

        switch thermalState {

        case .cool:
            return 25

        case .normal:
            return 30

        case .warm:
            return 35

        case .hot:
            return 40

        case .critical:
            return 45
        }
    }

    // MARK: Charging Rate

    private func estimateChargingRate(
        power: Double
    ) -> Double {

        //
        // Approximate percentage/hour.
        // Actual rate depends on battery size,
        // state of charge, temperature and charge curve.
        //

        if power >= 100 {
            return 70
        }

        if power >= 60 {
            return 50
        }

        if power >= 30 {
            return 30
        }

        return 15
    }

    // MARK: Session Tracking

    private func updateSession(
        with sample: USBCTelemetry
    ) {

        guard var current = session else {
            return
        }

        current.currentBatteryLevel =
            sample.batteryLevel

        current.accumulatedEnergyWh +=
            sample.estimatedInputPowerWatts / 3600.0

        current.estimatedAveragePower =
            (
                current.estimatedAveragePower +
                sample.estimatedInputPowerWatts
            ) / 2.0

        current.maximumTemperature =
            max(
                current.maximumTemperature,
                sample.deviceTemperatureCelsius
            )

        current.samples += 1

        session = current
    }

    // MARK: Public Configuration

    func setPolicy(
        _ newPolicy: ChargingPolicy
    ) {

        policy = newPolicy
    }

    func enableBatteryProtection() {

        policy = .batteryProtection
    }

    func enableFastChargingPolicy() {

        policy = .performance
    }

    func enableBalancedCharging() {

        policy = .balanced
    }

    // MARK: Diagnostics

    func chargingReport() -> String {

        guard let telemetry else {
            return "No USB-C charging telemetry available."
        }

        var output = ""

        output += "FAST USB-C CHARGING REPORT\n"
        output += "==========================\n"

        output += String(
            format: "Battery: %.1f%%\n",
            telemetry.batteryLevel * 100
        )

        output += "Charging: \(telemetry.isCharging)\n"

        output += String(
            format: "Estimated Power: %.1f W\n",
            telemetry.estimatedInputPowerWatts
        )

        output += String(
            format: "Estimated Voltage: %.1f V\n",
            telemetry.estimatedVoltage
        )

        output += String(
            format: "Estimated Current: %.2f A\n",
            telemetry.estimatedCurrent
        )

        output += "Charger Class: \(telemetry.chargerClass.rawValue)\n"
        output += "Thermal State: \(telemetry.thermalState.rawValue)\n"
        output += "Mode: \(mode.rawValue)\n"

        if let recommendation {

            output += "\nRECOMMENDATION\n"
            output += "--------------\n"

            output += String(
                format: "Target Power: %.1f W\n",
                recommendation.targetPowerWatts
            )

            output += String(
                format: "Estimated Rate: %.1f %%/hour\n",
                recommendation.estimatedChargingRatePerHour
            )

            output += "Reduce Workload: "
            output += "\(recommendation.reduceWorkload)\n"

            output += "Reason: \(recommendation.reason)\n"
        }

        if let session {

            output += "\nSESSION\n"
            output += "-------\n"

            output += String(
                format: "Energy: %.3f Wh\n",
                session.accumulatedEnergyWh
            )

            output += String(
                format: "Average Power: %.1f W\n",
                session.estimatedAveragePower
            )

            output += String(
                format: "Maximum Temperature: %.1f °C\n",
                session.maximumTemperature
            )
        }

        return output
    }
}

// MARK: - Example SwiftUI Integration

import SwiftUI

struct FastChargingView: View {

    @StateObject private var engine =
        FastUSBChargingEngine()

    var body: some View {

        VStack(spacing: 20) {

            Image(systemName: "bolt.fill")
                .font(.system(size: 50))

            if let telemetry = engine.telemetry {

                Text(
                    "\(Int(telemetry.batteryLevel * 100))%"
                )
                .font(.system(size: 48, weight: .bold))

                Text(
                    "\(Int(telemetry.estimatedInputPowerWatts)) W"
                )
                .font(.title2)

                Text(
                    telemetry.chargerClass.rawValue
                        .uppercased()
                )
                .font(.caption)

                Text(
                    "Thermal: \(telemetry.thermalState.rawValue)"
                )

                if let recommendation =
                    engine.recommendation {

                    Text(recommendation.reason)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
            }

            HStack {

                Button("Balanced") {
                    engine.enableBalancedCharging()
                }

                Button("Fast") {
                    engine.enableFastChargingPolicy()
                }

                Button("Protect") {
                    engine.enableBatteryProtection()
                }
            }
        }
        .padding()
    }
}
```


