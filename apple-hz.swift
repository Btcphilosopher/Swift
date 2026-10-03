```swift
import SwiftUI
import UIKit
import QuartzCore

// ============================================================
// Adaptive Display Refresh Engine
//
// Goals:
//   • Prefer high refresh during interaction
//   • Reduce refresh during idle periods
//   • Adapt to scrolling and animation
//   • Avoid unnecessary GPU work
//   • Respect thermal and battery conditions
//   • Work with ProMotion where available
//
// The OS ultimately controls the physical refresh rate.
// This engine supplies appropriate frame-rate preferences.
// ============================================================


// ============================================================
// MARK: - Display Mode
// ============================================================

enum DisplayPerformanceMode {

    case idle
    case reading
    case normal
    case scrolling
    case animation
    case gaming
    case video
    case thermalLimited
    case batterySaving
}


// ============================================================
// MARK: - Display Conditions
// ============================================================

struct DisplayConditions {

    var isScrolling: Bool = false
    var isAnimating: Bool = false
    var isGaming: Bool = false
    var isVideoPlaying: Bool = false

    var batteryLevel: Float = 1.0
    var isLowPowerMode: Bool = false

    var thermalState:
        ProcessInfo.ThermalState =
            .nominal

    var screenBrightness: CGFloat = 0.5

    var userInteractionRecent: Bool = false
}


// ============================================================
// MARK: - Refresh Policy
// ============================================================

struct RefreshPolicy {

    let minimumFPS: Int
    let preferredFPS: Int
    let maximumFPS: Int

    let preferredDuration:
        CAFrameRateRange

    static let normal =
        RefreshPolicy(
            minimumFPS: 30,
            preferredFPS: 60,
            maximumFPS: 120,
            preferredDuration:
                CAFrameRateRange(
                    minimum: 30,
                    maximum: 120,
                    preferred: 60
                )
        )

    static let interactive =
        RefreshPolicy(
            minimumFPS: 60,
            preferredFPS: 120,
            maximumFPS: 120,
            preferredDuration:
                CAFrameRateRange(
                    minimum: 60,
                    maximum: 120,
                    preferred: 120
                )
        )

    static let idle =
        RefreshPolicy(
            minimumFPS: 10,
            preferredFPS: 30,
            maximumFPS: 60,
            preferredDuration:
                CAFrameRateRange(
                    minimum: 10,
                    maximum: 60,
                    preferred: 30
                )
        )

    static let video =
        RefreshPolicy(
            minimumFPS: 24,
            preferredFPS: 60,
            maximumFPS: 60,
            preferredDuration:
                CAFrameRateRange(
                    minimum: 24,
                    maximum: 60,
                    preferred: 60
                )
        )

    static let battery =
        RefreshPolicy(
            minimumFPS: 30,
            preferredFPS: 60,
            maximumFPS: 60,
            preferredDuration:
                CAFrameRateRange(
                    minimum: 30,
                    maximum: 60,
                    preferred: 60
                )
        )

    static let thermal =
        RefreshPolicy(
            minimumFPS: 30,
            preferredFPS: 60,
            maximumFPS: 60,
            preferredDuration:
                CAFrameRateRange(
                    minimum: 30,
                    maximum: 60,
                    preferred: 60
                )
        )
}


// ============================================================
// MARK: - Display Capability
// ============================================================

final class DisplayCapability {

    let screen:
        UIScreen

    init(
        screen: UIScreen =
            .main
    ) {

        self.screen = screen
    }

    var maximumRefreshRate: Int {

        Int(
            screen.maximumFramesPerSecond
        )
    }

    var supportsHighRefresh: Bool {

        maximumRefreshRate >= 90
    }

    var supports120Hz: Bool {

        maximumRefreshRate >= 120
    }
}


// ============================================================
// MARK: - Policy Engine
// ============================================================

final class RefreshPolicyEngine {

    private let display:
        DisplayCapability

    init(
        display: DisplayCapability =
            DisplayCapability()
    ) {

        self.display = display
    }


    func mode(
        conditions: DisplayConditions
    ) -> DisplayPerformanceMode {

        // Thermal conditions take precedence.

        switch conditions.thermalState {

        case .serious, .critical:
            return .thermalLimited

        default:
            break
        }


        // Low Power Mode.

        if conditions.isLowPowerMode {

            return .batterySaving
        }


        // Gaming.

        if conditions.isGaming {

            return .gaming
        }


        // Active animation.

        if conditions.isAnimating {

            return .animation
        }


        // Scrolling.

        if conditions.isScrolling {

            return .scrolling
        }


        // Video.

        if conditions.isVideoPlaying {

            return .video
        }


        // Recent touch.

        if conditions.userInteractionRecent {

            return .normal
        }


        return .idle
    }


    func policy(
        conditions: DisplayConditions
    ) -> RefreshPolicy {

        let mode =
            mode(
                conditions:
                    conditions
            )

        switch mode {

        case .scrolling,
             .animation,
             .gaming:

            return display.supports120Hz
                ? .interactive
                : .normal


        case .video:

            return .video


        case .batterySaving:

            return .battery


        case .thermalLimited:

            return .thermal


        case .reading,
             .idle:

            return .idle


        case .normal:

            return .normal
        }
    }
}


// ============================================================
// MARK: - Display Controller
// ============================================================

@MainActor
final class AdaptiveDisplayController:
    ObservableObject {

    @Published
    private(set) var mode:
        DisplayPerformanceMode =
            .idle

    @Published
    private(set) var preferredFPS:
        Int = 60

    @Published
    private(set) var conditions =
        DisplayConditions()

    private let engine:
        RefreshPolicyEngine

    private weak var displayLink:
        CADisplayLink?

    init() {

        engine =
            RefreshPolicyEngine()

        startMonitoring()
    }


    // ========================================================
    // MARK: Monitoring
    // ========================================================

    private func startMonitoring() {

        let link =
            CADisplayLink(
                target: self,
                selector:
                    #selector(
                        frameTick
                    )
            )

        link.add(
            to: .main,
            forMode: .common
        )

        displayLink = link
    }


    @objc
    private func frameTick(
        _ link: CADisplayLink
    ) {

        update()
    }


    // ========================================================
    // MARK: Update
    // ========================================================

    func update() {

        mode =
            engine.mode(
                conditions:
                    conditions
            )

        let policy =
            engine.policy(
                conditions:
                    conditions
            )

        preferredFPS =
            policy.preferredFPS

        apply(
            policy:
                policy
        )
    }


    // ========================================================
    // MARK: Apply
    // ========================================================

    private func apply(
        policy: RefreshPolicy
    ) {

        guard
            let link =
                displayLink
        else {
            return
        }

        link.preferredFrameRateRange =
            policy.preferredDuration
    }


    // ========================================================
    // MARK: Interaction
    // ========================================================

    func beginScrolling() {

        conditions.isScrolling =
            true

        conditions.userInteractionRecent =
            true

        update()
    }


    func endScrolling() {

        conditions.isScrolling =
            false

        update()
    }


    func beginAnimation() {

        conditions.isAnimating =
            true

        update()
    }


    func endAnimation() {

        conditions.isAnimating =
            false

        update()
    }


    func beginGaming() {

        conditions.isGaming =
            true

        update()
    }


    func endGaming() {

        conditions.isGaming =
            false

        update()
    }


    func beginVideo() {

        conditions.isVideoPlaying =
            true

        update()
    }


    func endVideo() {

        conditions.isVideoPlaying =
            false

        update()
    }


    // ========================================================
    // MARK: Power
    // ========================================================

    func updateBattery(
        level: Float
    ) {

        conditions.batteryLevel =
            level

        update()
    }


    func updateLowPowerMode(
        enabled: Bool
    ) {

        conditions.isLowPowerMode =
            enabled

        update()
    }


    // ========================================================
    // MARK: Thermal
    // ========================================================

    func updateThermalState(
        _ state:
            ProcessInfo.ThermalState
    ) {

        conditions.thermalState =
            state

        update()
    }
}


// ============================================================
// MARK: - SwiftUI Environment
// ============================================================

struct AdaptiveDisplayModifier:
    ViewModifier {

    @StateObject
    private var display =
        AdaptiveDisplayController()


    func body(
        content: Content
    ) -> some View {

        content
            .environmentObject(
                display
            )
    }
}


extension View {

    func adaptiveDisplay() -> some View {

        modifier(
            AdaptiveDisplayModifier()
        )
    }
}


// ============================================================
// MARK: - Example Scrolling View
// ============================================================

struct OptimisedScrollView:
    View {

    @EnvironmentObject
    private var display:
        AdaptiveDisplayController

    var body: some View {

        ScrollView {

            LazyVStack(
                spacing: 0
            ) {

                ForEach(
                    0..<200,
                    id: \.self
                ) { index in

                    Text(
                        "Item \(index)"
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .padding()
                }
            }
        }

        .simultaneousGesture(
            DragGesture()
                .onChanged { _ in

                    display.beginScrolling()
                }
                .onEnded { _ in

                    display.endScrolling()
                }
        )
    }
}


// ============================================================
// MARK: - Display Diagnostics
// ============================================================

struct DisplayDiagnostics {

    let maximumFPS: Int
    let preferredFPS: Int
    let mode:
        DisplayPerformanceMode
    let lowPowerMode: Bool
    let thermalState:
        ProcessInfo.ThermalState
}


extension AdaptiveDisplayController {

    var diagnostics:
        DisplayDiagnostics {

        DisplayDiagnostics(
            maximumFPS:
                UIScreen.main
                    .maximumFramesPerSecond,

            preferredFPS:
                preferredFPS,

            mode:
                mode,

            lowPowerMode:
                conditions
                    .isLowPowerMode,

            thermalState:
                conditions
                    .thermalState
        )
    }
}
```

### The optimisation philosophy

The important thing isn't simply **120 Hz everywhere**.

You want:

| Situation             | Preferred behaviour          |
| --------------------- | ---------------------------- |
| Static screen         | Low refresh                  |
| Reading               | Low/moderate                 |
| Normal UI             | ~60 Hz                       |
| Scrolling             | Highest available            |
| Interactive animation | Highest available            |
| Gaming                | Highest appropriate          |
| 24/30 fps video       | Match content where possible |
| Low Power Mode        | Reduce                       |
| High thermal pressure | Reduce                       |
| Device idle           | Reduce                       |

That means the display engine becomes an **adaptive scheduler**:

```text
                USER ACTIVITY
                     │
       ┌─────────────┼─────────────┐
       ↓             ↓             ↓
    scrolling     animation      idle
       │             │             │
       └─────────────┼─────────────┘
                     ↓
              REFRESH POLICY
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
     battery       thermal       GPU
        │            │            │
        └────────────┼────────────┘
                     ↓
             preferredFrameRate
                     ↓
               Core Animation
                     ↓
                 ProMotion
```

And this fits particularly well with the **Apple Compute** system we've been building: Julia could eventually learn the device's workload/thermal/battery behaviour and supply an optimal refresh policy, while Swift remains responsible for communicating that preference to Core Animation and UIKit/SwiftUI.

One correction to the earlier conceptual direction, though: **`CADisplayLink.preferredFrameRateRange` controls an app's display-link cadence; it is not a direct hardware command to force the iPhone panel to a particular Hz.** Apple's display compositor ultimately decides the actual refresh rate. That distinction is important if we're aiming for a genuinely Apple-quality implementation.

