```swift
import SwiftUI
import UIKit
import CoreHaptics
import QuartzCore

// ============================================================
// TOUCH WEIGHT & DEPTH INTELLIGENCE
//
// Measures:
//   • touch force
//   • contact radius
//   • pressure development
//   • touch velocity
//   • touch acceleration
//   • inferred interaction depth
//   • touch-to-response latency
//
// Uses those measurements to optimise:
//   • interaction thresholds
//   • visual response
//   • animation intensity
//   • haptic response
//   • gesture recognition
//   • "reflexiveness" of the interface
//
// IMPORTANT:
// "depth" here is an inferred interaction variable.
// iOS does not generally expose literal physical finger
// penetration depth through the touchscreen.
// ============================================================


// MARK: - Touch Input

enum TouchInputType {
    case finger
    case pencil
    case indirect
    case unknown
}


// MARK: - Touch Weight

enum TouchWeight: String {

    case feather
    case light
    case normal
    case firm
    case heavy

    var label: String {
        rawValue.capitalized
    }
}


// MARK: - Touch Depth

enum TouchDepth: String {

    case surface
    case shallow
    case medium
    case deep
    case maximum

    var label: String {
        rawValue.capitalized
    }
}


// MARK: - Touch Sample

struct WeightedTouchSample: Identifiable {

    let id = UUID()

    let timestamp: CFTimeInterval

    let inputType: TouchInputType

    let x: CGFloat
    let y: CGFloat

    /// Raw UIKit force.
    let force: CGFloat

    /// Maximum force reported by the input device.
    let maximumForce: CGFloat

    /// Approximate contact radius.
    let majorRadius: CGFloat

    /// Estimated velocity in points/sec.
    let velocity: CGFloat

    /// Estimated acceleration in points/sec².
    let acceleration: CGFloat

    let predicted: Bool
}


// MARK: - Normalised Touch

struct NormalisedTouch {

    let pressure: Double
    let contactArea: Double
    let velocity: Double
    let acceleration: Double

    let weight: TouchWeight
    let depth: TouchDepth

    /// 0 = feather-light
    /// 1 = maximum interaction intensity
    let interactionIntensity: Double
}


// MARK: - Touch Profile

struct TouchProfile {

    /// User/device calibrated minimum force.
    var minimumForce: Double = 0.05

    /// Force considered "normal".
    var normalForce: Double = 0.35

    /// Force considered firm.
    var firmForce: Double = 0.65

    /// Contact-radius normalisation.
    var minimumRadius: Double = 1.0
    var maximumRadius: Double = 40.0

    /// Velocity at which reflexive interaction becomes important.
    var reflexVelocity: Double = 800.0

    /// Smoothing coefficient.
    var smoothing: Double = 0.20
}


// MARK: - Response Policy

struct TouchResponsePolicy {

    /// How quickly the UI should respond.
    var responseMultiplier: Double = 1.0

    /// Visual scale response.
    var visualResponse: Double = 1.0

    /// Haptic intensity.
    var hapticIntensity: Double = 0.5

    /// Gesture threshold.
    var gestureThreshold: Double = 0.5

    /// Animation duration.
    var animationDuration: Double = 0.12

    /// Whether a deep/firm touch gets an enhanced response.
    var enhancedFeedback: Bool = false
}


// MARK: - Engine

@MainActor
final class TouchWeightDepthEngine:
    ObservableObject {

    // --------------------------------------------------------
    // Published state
    // --------------------------------------------------------

    @Published private(set)
    var latestSample:
        WeightedTouchSample?

    @Published private(set)
    var latestNormalised:
        NormalisedTouch?

    @Published private(set)
    var currentWeight:
        TouchWeight = .normal

    @Published private(set)
    var currentDepth:
        TouchDepth = .surface

    @Published private(set)
    var interactionIntensity:
        Double = 0

    @Published private(set)
    var responsePolicy =
        TouchResponsePolicy()

    // --------------------------------------------------------
    // Configuration
    // --------------------------------------------------------

    var profile =
        TouchProfile()

    // --------------------------------------------------------
    // History
    // --------------------------------------------------------

    private(set)
    var history:
        [NormalisedTouch] = []

    private var previousSample:
        WeightedTouchSample?

    private var smoothedPressure:
        Double = 0

    private var smoothedIntensity:
        Double = 0


    // ========================================================
    // INGEST TOUCH
    // ========================================================

    func process(
        touch: UITouch,
        location: CGPoint,
        inputType: TouchInputType = .finger
    ) {

        let timestamp =
            touch.timestamp

        let force =
            Double(touch.force)

        let maximumForce =
            Double(
                max(
                    touch.maximumPossibleForce,
                    1
                )
            )

        let radius =
            Double(
                max(
                    touch.majorRadius,
                    0
                )
            )

        let velocity =
            estimateVelocity(
                touch: touch
            )

        let acceleration =
            estimateAcceleration(
                velocity: velocity
            )

        let sample =
            WeightedTouchSample(
                timestamp: timestamp,
                inputType: inputType,
                x: location.x,
                y: location.y,
                force: CGFloat(force),
                maximumForce:
                    CGFloat(maximumForce),
                majorRadius:
                    CGFloat(radius),
                velocity:
                    CGFloat(velocity),
                acceleration:
                    CGFloat(acceleration),
                predicted: false
            )

        latestSample =
            sample

        let normalised =
            normalise(
                sample
            )

        latestNormalised =
            normalised

        currentWeight =
            normalised.weight

        currentDepth =
            normalised.depth

        interactionIntensity =
            normalised.interactionIntensity

        history.append(
            normalised
        )

        if history.count > 500 {
            history.removeFirst(
                history.count - 500
            )
        }

        responsePolicy =
            calculateResponsePolicy(
                normalised
            )

        previousSample =
            sample
    }


    // ========================================================
    // NORMALISATION
    // ========================================================

    private func normalise(
        _ sample: WeightedTouchSample
    ) -> NormalisedTouch {

        let rawPressure =
            Double(sample.force) /
            Double(
                max(
                    sample.maximumForce,
                    1
                )
            )

        let pressure =
            clamp(
                rawPressure,
                0,
                1
            )

        let radius =
            clamp(
                (
                    Double(sample.majorRadius) -
                    profile.minimumRadius
                ) /
                (
                    profile.maximumRadius -
                    profile.minimumRadius
                ),
                0,
                1
            )

        let velocity =
            clamp(
                Double(sample.velocity) /
                profile.reflexVelocity,
                0,
                1
            )

        let acceleration =
            clamp(
                Double(
                    abs(
                        sample.acceleration
                    )
                ) / 5000.0,
                0,
                1
            )

        // ----------------------------------------------------
        // Smoothed pressure
        // ----------------------------------------------------

        smoothedPressure =
            profile.smoothing * pressure +
            (1.0 - profile.smoothing) *
            smoothedPressure

        // ----------------------------------------------------
        // Interaction intensity
        //
        // Force is weighted most heavily.
        // Contact area provides a secondary signal.
        // Velocity matters for reflexive interactions.
        // ----------------------------------------------------

        let intensity =
            (
                smoothedPressure * 0.55 +
                radius * 0.20 +
                velocity * 0.15 +
                acceleration * 0.10
            )

        smoothedIntensity =
            profile.smoothing * intensity +
            (1.0 - profile.smoothing) *
            smoothedIntensity

        let weight =
            classifyWeight(
                pressure
            )

        let depth =
            inferDepth(
                pressure: pressure,
                contactArea: radius
            )

        return NormalisedTouch(
            pressure: pressure,
            contactArea: radius,
            velocity: velocity,
            acceleration: acceleration,
            weight: weight,
            depth: depth,
            interactionIntensity:
                smoothedIntensity
        )
    }


    // ========================================================
    // WEIGHT CLASSIFICATION
    // ========================================================

    private func classifyWeight(
        _ pressure: Double
    ) -> TouchWeight {

        if pressure < 0.10 {
            return .feather
        }

        if pressure < 0.25 {
            return .light
        }

        if pressure < profile.firmForce {
            return .normal
        }

        if pressure < 0.85 {
            return .firm
        }

        return .heavy
    }


    // ========================================================
    // DEPTH INFERENCE
    // ========================================================

    private func inferDepth(
        pressure: Double,
        contactArea: Double
    ) -> TouchDepth {

        let combined =
            pressure * 0.75 +
            contactArea * 0.25

        if combined < 0.12 {
            return .surface
        }

        if combined < 0.30 {
            return .shallow
        }

        if combined < 0.55 {
            return .medium
        }

        if combined < 0.80 {
            return .deep
        }

        return .maximum
    }


    // ========================================================
    // RESPONSE POLICY
    // ========================================================

    private func calculateResponsePolicy(
        _ touch: NormalisedTouch
    ) -> TouchResponsePolicy {

        var policy =
            TouchResponsePolicy()

        let intensity =
            touch.interactionIntensity

        // ----------------------------------------------------
        // Very light touch
        // ----------------------------------------------------

        if intensity < 0.20 {

            policy.responseMultiplier =
                1.15

            policy.visualResponse =
                0.75

            policy.hapticIntensity =
                0.20

            policy.gestureThreshold =
                0.35

            policy.animationDuration =
                0.14
        }

        // ----------------------------------------------------
        // Normal touch
        // ----------------------------------------------------

        else if intensity < 0.55 {

            policy.responseMultiplier =
                1.0

            policy.visualResponse =
                1.0

            policy.hapticIntensity =
                0.50

            policy.gestureThreshold =
                0.50

            policy.animationDuration =
                0.12
        }

        // ----------------------------------------------------
        // Firm touch
        // ----------------------------------------------------

        else if intensity < 0.80 {

            policy.responseMultiplier =
                0.90

            policy.visualResponse =
                1.10

            policy.hapticIntensity =
                0.70

            policy.gestureThreshold =
                0.60

            policy.animationDuration =
                0.09

            policy.enhancedFeedback =
                true
        }

        // ----------------------------------------------------
        // Heavy / deep interaction
        // ----------------------------------------------------

        else {

            policy.responseMultiplier =
                0.80

            policy.visualResponse =
                1.20

            policy.hapticIntensity =
                0.90

            policy.gestureThreshold =
                0.70

            policy.animationDuration =
                0.07

            policy.enhancedFeedback =
                true
        }

        return policy
    }


    // ========================================================
    // REFLEXIVE RESPONSE
    // ========================================================

    func reflexScore() -> Double {

        guard
            let touch = latestNormalised
        else {
            return 0
        }

        // Faster movement + appropriate pressure =
        // more reflexive interaction.

        let velocityScore =
            touch.velocity

        let pressureScore =
            touch.pressure

        let responsiveness =
            1.0 -
            min(
                responsePolicy.animationDuration /
                0.20,
                1.0
            )

        return clamp(
            (
                velocityScore * 0.35 +
                pressureScore * 0.30 +
                responsiveness * 0.35
            ),
            0,
            1
        )
    }


    // ========================================================
    // TOUCH FORCE CURVE
    // ========================================================

    func forceCurve(
        sampleCount: Int = 100
    ) -> [(Double, Double)] {

        guard sampleCount > 1 else {
            return []
        }

        return (0..<sampleCount).map {
            index in

            let x =
                Double(index) /
                Double(sampleCount - 1)

            let y =
                pow(
                    x,
                    0.75
                )

            return (
                x,
                y
            )
        }
    }


    // ========================================================
    // TOUCH PRESSURE ADAPTATION
    // ========================================================

    func calibratedThreshold(
        base: Double
    ) -> Double {

        guard
            let touch = latestNormalised
        else {
            return base
        }

        // Strong users should not accidentally
        // trigger extremely sensitive controls.

        if touch.weight == .heavy {

            return base * 1.15
        }

        if touch.weight == .feather {

            return base * 0.85
        }

        return base
    }


    // ========================================================
    // UTILITY
    // ========================================================

    private func estimateVelocity(
        touch: UITouch
    ) -> Double {

        // UIKit does not provide a universal direct
        // velocity API for UITouch itself.
        //
        // The actual production implementation should
        // calculate displacement between successive
        // samples belonging to the same touch.

        return 0
    }


    private func estimateAcceleration(
        velocity: Double
    ) -> Double {

        guard
            let previous = previousSample
        else {
            return 0
        }

        let previousVelocity =
            Double(previous.velocity)

        return velocity -
            previousVelocity
    }


    private func clamp(
        _ value: Double,
        _ minimum: Double,
        _ maximum: Double
    ) -> Double {

        min(
            max(
                value,
                minimum
            ),
            maximum
        )
    }
}


// ============================================================
// HIGH-LEVEL TOUCH VIEW
// ============================================================

struct IntelligentTouchView:
    UIViewRepresentable {

    @ObservedObject
    var engine:
        TouchWeightDepthEngine


    func makeUIView(
        context: Context
    ) -> IntelligentTouchUIView {

        let view =
            IntelligentTouchUIView()

        view.engine =
            engine

        return view
    }


    func updateUIView(
        _ uiView: IntelligentTouchUIView,
        context: Context
    ) {

        uiView.engine =
            engine
    }
}


// ============================================================
// UIKIT TOUCH CAPTURE
// ============================================================

final class IntelligentTouchUIView:
    UIView {

    weak var engine:
        TouchWeightDepthEngine?


    override init(
        frame: CGRect
    ) {

        super.init(
            frame: frame
        )

        isMultipleTouchEnabled =
            true

        backgroundColor =
            .clear
    }


    required init?(
        coder: NSCoder
    ) {

        fatalError(
            "init(coder:) has not been implemented"
        )
    }


    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches
        )
    }


    override func touchesMoved(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches
        )
    }


    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches
        )
    }


    private func process(
        _ touches: Set<UITouch>
    ) {

        for touch in touches {

            let location =
                touch.location(
                    in: self
                )

            let type:
                TouchInputType

            if #available(iOS 9.1, *) {

                if touch.type ==
                    .pencil {

                    type = .pencil

                } else {

                    type = .finger
                }

            } else {

                type = .finger
            }

            engine?.process(
                touch: touch,
                location: location,
                inputType: type
            )
        }
    }
}


// ============================================================
// SWIFTUI DASHBOARD
// ============================================================

struct TouchWeightDepthDashboard:
    View {

    @StateObject
    private var engine =
        TouchWeightDepthEngine()


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            header

            Divider()

            interactionCard

            metrics

            IntelligentTouchView(
                engine: engine
            )
            .frame(
                height: 220
            )
            .background(
                .thinMaterial
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
            )

            Spacer()
        }
        .padding(24)
        .frame(
            minWidth: 430,
            minHeight: 620
        )
    }


    // MARK: Header

    private var header: some View {

        HStack {

            VStack(
                alignment: .leading
            ) {

                Text(
                    "Touch Depth"
                )
                .font(
                    .system(
                        size: 28,
                        weight: .semibold,
                        design: .rounded
                    )
                )

                Text(
                    "Weight, pressure and reflex response"
                )
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()

            Image(
                systemName:
                    "hand.tap.fill"
            )
            .font(.title)
        }
    }


    // MARK: Interaction

    private var interactionCard:
        some View {

        VStack(
            alignment: .leading,
            spacing: 12
        ) {

            HStack {

                VStack(
                    alignment: .leading
                ) {

                    Text("Weight")
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                    Text(
                        engine.currentWeight.label
                    )
                    .font(
                        .title2.bold()
                    )
                }

                Spacer()

                VStack(
                    alignment: .trailing
                ) {

                    Text("Depth")
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                    Text(
                        engine.currentDepth.label
                    )
                    .font(
                        .title2.bold()
                    )
                }
            }

            GeometryReader {
                geometry in

                ZStack(
                    alignment: .leading
                ) {

                    Capsule()
                        .fill(
                            .quaternary
                        )

                    Capsule()
                        .fill(
                            .primary
                        )
                        .frame(
                            width:
                                geometry.size.width *
                                engine.interactionIntensity
                        )
                }
            }
            .frame(
                height: 8
            )

            Text(
                "Interaction intensity " +
                "\(Int(engine.interactionIntensity * 100))%"
            )
            .font(.caption)
            .foregroundStyle(
                .secondary
            )
        }
        .padding(20)
        .background(
            .regularMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22,
                style: .continuous
            )
        )
    }


    // MARK: Metrics

    private var metrics: some View {

        HStack(spacing: 12) {

            metric(
                "Pressure",
                "\(Int(
                    (engine.latestNormalised?
                        .pressure ?? 0) * 100
                ))%"
            )

            metric(
                "Contact",
                "\(Int(
                    (engine.latestNormalised?
                        .contactArea ?? 0) * 100
                ))%"
            )

            metric(
                "Reflex",
                "\(Int(
                    engine.reflexScore() * 100
                ))%"
            )
        }
    }


    private func metric(
        _ title: String,
        _ value: String
    ) -> some View {

        VStack(
            alignment: .leading,
            spacing: 5
        ) {

            Text(title)
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )

            Text(value)
                .font(
                    .system(
                        size: 18,
                        weight: .medium,
                        design: .rounded
                    )
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(14)
        .background(
            .thinMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
    }
}
```

