```swift
import SwiftUI
import UIKit
import QuartzCore
import Combine

// ============================================================
// TOUCHSCREEN LATENCY INTELLIGENCE
//
// Swift owns:
//   • UIKit touch capture
//   • event timestamps
//   • frame timing
//   • CADisplayLink
//   • latency measurement
//   • real-time policy
//
// Julia can consume the resulting telemetry for:
//   • long-term analysis
//   • anomaly detection
//   • device-specific optimisation
//   • predictive modelling
// ============================================================


// MARK: - Touch Phase

enum TouchLatencyPhase {
    case began
    case moved
    case ended
    case cancelled
}


// MARK: - Touch Event

struct TouchLatencyEvent: Identifiable {

    let id = UUID()

    let phase: TouchLatencyPhase

    let timestamp: CFTimeInterval
    let receivedAt: CFTimeInterval

    let x: CGFloat
    let y: CGFloat

    let force: CGFloat

    var processingLatencyMS: Double {
        max(
            0,
            (receivedAt - timestamp) * 1000
        )
    }
}


// MARK: - Frame Measurement

struct FrameMeasurement {

    let timestamp: CFTimeInterval
    let duration: CFTimeInterval

    var frameTimeMS: Double {
        duration * 1000
    }

    var estimatedFPS: Double {
        guard duration > 0 else {
            return 0
        }

        return 1.0 / duration
    }
}


// MARK: - Touch Latency Measurement

struct TouchLatencyMeasurement: Identifiable {

    let id = UUID()

    let touchTimestamp: CFTimeInterval
    let eventReceivedTimestamp: CFTimeInterval
    let frameTimestamp: CFTimeInterval

    let processingLatencyMS: Double
    let eventToFrameLatencyMS: Double
    let totalEstimatedLatencyMS: Double

    let x: CGFloat
    let y: CGFloat
}


// MARK: - Statistics

struct TouchLatencyStatistics {

    var sampleCount: Int = 0

    var averageLatencyMS: Double = 0
    var medianLatencyMS: Double = 0

    var p95LatencyMS: Double = 0
    var p99LatencyMS: Double = 0

    var jitterMS: Double = 0

    var minimumLatencyMS: Double = 0
    var maximumLatencyMS: Double = 0

    var estimatedFPS: Double = 0

    var droppedFrameCount: Int = 0
}


// MARK: - Quality

enum TouchResponsivenessQuality: String {

    case excellent
    case good
    case acceptable
    case degraded
    case poor

    var label: String {
        rawValue.capitalized
    }
}


// MARK: - Policy

struct TouchLatencyPolicy {

    var targetLatencyMS: Double = 10

    var warningLatencyMS: Double = 16.67

    var criticalLatencyMS: Double = 25

    var frameDropThresholdMS: Double = 20

    var measurementWindow: Int = 240

    var enablePrediction: Bool = true

    var reduceBackgroundWork: Bool = true

    var preferHighRefreshRate: Bool = true
}


// MARK: - Engine

@MainActor
final class TouchscreenLatencyEngine: ObservableObject {

    // --------------------------------------------------------
    // Published state
    // --------------------------------------------------------

    @Published private(set) var latestTouch:
        TouchLatencyEvent?

    @Published private(set) var latestMeasurement:
        TouchLatencyMeasurement?

    @Published private(set) var measurements:
        [TouchLatencyMeasurement] = []

    @Published private(set) var frameMeasurements:
        [FrameMeasurement] = []

    @Published private(set) var statistics =
        TouchLatencyStatistics()

    @Published private(set) var quality =
        TouchResponsivenessQuality.excellent

    @Published private(set) var isMonitoring = false

    @Published private(set) var currentRefreshRate: Double = 60

    @Published private(set) var frameDrops = 0

    // --------------------------------------------------------
    // Configuration
    // --------------------------------------------------------

    var policy =
        TouchLatencyPolicy()

    // --------------------------------------------------------
    // Display link
    // --------------------------------------------------------

    private var displayLink: CADisplayLink?

    private var lastFrameTimestamp:
        CFTimeInterval?

    // --------------------------------------------------------
    // Combine
    // --------------------------------------------------------

    private var cancellables =
        Set<AnyCancellable>()

    // --------------------------------------------------------
    // Start
    // --------------------------------------------------------

    func start() {

        guard !isMonitoring else {
            return
        }

        isMonitoring = true

        startDisplayLink()
    }

    // --------------------------------------------------------
    // Stop
    // --------------------------------------------------------

    func stop() {

        displayLink?.invalidate()
        displayLink = nil

        lastFrameTimestamp = nil

        isMonitoring = false
    }

    // --------------------------------------------------------
    // Display link
    // --------------------------------------------------------

    private func startDisplayLink() {

        let link =
            CADisplayLink(
                target: self,
                selector: #selector(displayTick)
            )

        if #available(iOS 15.0, *) {

            link.preferredFrameRateRange =
                CAFrameRateRange(
                    minimum: 60,
                    maximum: 120,
                    preferred: 120
                )
        }

        link.add(
            to: .main,
            forMode: .common
        )

        displayLink = link
    }

    // --------------------------------------------------------
    // Frame callback
    // --------------------------------------------------------

    @objc
    private func displayTick(
        _ link: CADisplayLink
    ) {

        let timestamp =
            link.timestamp

        let duration =
            link.targetTimestamp -
            link.timestamp

        let frame =
            FrameMeasurement(
                timestamp: timestamp,
                duration: duration
            )

        currentRefreshRate =
            frame.estimatedFPS

        if frame.frameTimeMS >
            policy.frameDropThresholdMS {

            frameDrops += 1
        }

        frameMeasurements.append(frame)

        if frameMeasurements.count > 500 {

            frameMeasurements.removeFirst(
                frameMeasurements.count - 500
            )
        }

        lastFrameTimestamp =
            timestamp

        updateStatistics()
    }


    // MARK: - Touch ingestion

    func recordTouch(
        phase: TouchLatencyPhase,
        timestamp: CFTimeInterval,
        x: CGFloat,
        y: CGFloat,
        force: CGFloat = 0
    ) {

        let now =
            CACurrentMediaTime()

        let event =
            TouchLatencyEvent(
                phase: phase,
                timestamp: timestamp,
                receivedAt: now,
                x: x,
                y: y,
                force: force
            )

        latestTouch =
            event

        let frameTime =
            lastFrameTimestamp ??
            now

        let processing =
            max(
                0,
                (now - timestamp) * 1000
            )

        let eventToFrame =
            max(
                0,
                (frameTime - now) * 1000
            )

        let total =
            processing +
            eventToFrame

        let measurement =
            TouchLatencyMeasurement(
                touchTimestamp: timestamp,
                eventReceivedTimestamp: now,
                frameTimestamp: frameTime,
                processingLatencyMS: processing,
                eventToFrameLatencyMS: eventToFrame,
                totalEstimatedLatencyMS: total,
                x: x,
                y: y
            )

        latestMeasurement =
            measurement

        measurements.append(
            measurement
        )

        trimMeasurements()

        updateStatistics()
        updateQuality()
    }


    // MARK: - Convenience touch methods

    func touchBegan(
        timestamp: CFTimeInterval,
        x: CGFloat,
        y: CGFloat,
        force: CGFloat = 0
    ) {

        recordTouch(
            phase: .began,
            timestamp: timestamp,
            x: x,
            y: y,
            force: force
        )
    }


    func touchMoved(
        timestamp: CFTimeInterval,
        x: CGFloat,
        y: CGFloat,
        force: CGFloat = 0
    ) {

        recordTouch(
            phase: .moved,
            timestamp: timestamp,
            x: x,
            y: y,
            force: force
        )
    }


    func touchEnded(
        timestamp: CFTimeInterval,
        x: CGFloat,
        y: CGFloat
    ) {

        recordTouch(
            phase: .ended,
            timestamp: timestamp,
            x: x,
            y: y
        )
    }


    // MARK: - Statistics

    private func updateStatistics() {

        guard !measurements.isEmpty else {
            return
        }

        let values =
            measurements.map {
                $0.totalEstimatedLatencyMS
            }

        let sorted =
            values.sorted()

        let average =
            values.reduce(
                0,
                +
            ) / Double(values.count)

        let median =
            percentile(
                sorted,
                0.50
            )

        let p95 =
            percentile(
                sorted,
                0.95
            )

        let p99 =
            percentile(
                sorted,
                0.99
            )

        let minimum =
            sorted.first ?? 0

        let maximum =
            sorted.last ?? 0

        let jitter =
            calculateJitter(
                values
            )

        let fps =
            frameMeasurements
                .last?
                .estimatedFPS ?? 0

        statistics =
            TouchLatencyStatistics(
                sampleCount: values.count,
                averageLatencyMS: average,
                medianLatencyMS: median,
                p95LatencyMS: p95,
                p99LatencyMS: p99,
                jitterMS: jitter,
                minimumLatencyMS: minimum,
                maximumLatencyMS: maximum,
                estimatedFPS: fps,
                droppedFrameCount: frameDrops
            )
    }


    private func calculateJitter(
        _ values: [Double]
    ) -> Double {

        guard values.count > 1 else {
            return 0
        }

        let mean =
            values.reduce(
                0,
                +
            ) / Double(values.count)

        let variance =
            values.reduce(0) {
                partial,
                value in

                partial +
                pow(
                    value - mean,
                    2
                )
            } / Double(values.count)

        return sqrt(variance)
    }


    private func percentile(
        _ sorted: [Double],
        _ p: Double
    ) -> Double {

        guard !sorted.isEmpty else {
            return 0
        }

        let position =
            p *
            Double(
                sorted.count - 1
            )

        let lower =
            Int(
                floor(position)
            )

        let upper =
            Int(
                ceil(position)
            )

        if lower == upper {
            return sorted[lower]
        }

        let fraction =
            position -
            Double(lower)

        return sorted[lower] +
            (
                sorted[upper] -
                sorted[lower]
            ) *
            fraction
    }


    // MARK: - Quality

    private func updateQuality() {

        let latency =
            statistics.medianLatencyMS

        if latency <= policy.targetLatencyMS {

            quality = .excellent

        } else if latency <=
                    policy.warningLatencyMS {

            quality = .good

        } else if latency <= 20 {

            quality = .acceptable

        } else if latency <=
                    policy.criticalLatencyMS {

            quality = .degraded

        } else {

            quality = .poor
        }
    }


    // MARK: - Trim

    private func trimMeasurements() {

        let maximum =
            policy.measurementWindow

        if measurements.count > maximum {

            measurements.removeFirst(
                measurements.count - maximum
            )
        }
    }


    // MARK: - Bottleneck analysis

    func bottleneck() -> String {

        guard
            let latest = latestMeasurement
        else {
            return "No data"
        }

        if latest.processingLatencyMS >
            8 {

            return "Touch event processing"
        }

        if latest.eventToFrameLatencyMS >
            12 {

            return "Frame scheduling"
        }

        if statistics.droppedFrameCount >
            0 {

            return "Frame delivery"
        }

        return "No obvious bottleneck"
    }


    // MARK: - Adaptive policy

    func recommendedPolicy()
        -> TouchLatencyPolicy
    {

        var result =
            policy

        if statistics.medianLatencyMS >
            policy.warningLatencyMS {

            result.reduceBackgroundWork =
                true

            result.preferHighRefreshRate =
                true
        }

        if statistics.p95LatencyMS >
            policy.criticalLatencyMS {

            result.enablePrediction =
                true

            result.reduceBackgroundWork =
                true
        }

        return result
    }


    // MARK: - Reset

    func reset() {

        measurements.removeAll()
        frameMeasurements.removeAll()

        statistics =
            TouchLatencyStatistics()

        quality =
            .excellent

        frameDrops = 0

        latestTouch = nil
        latestMeasurement = nil
    }
}


// ============================================================
// TOUCH CAPTURE VIEW
// ============================================================

struct TouchLatencyCaptureView:
    UIViewRepresentable {

    @ObservedObject
    var engine:
        TouchscreenLatencyEngine


    func makeUIView(
        context: Context
    ) -> TouchCaptureUIView {

        let view =
            TouchCaptureUIView()

        view.engine =
            engine

        return view
    }


    func updateUIView(
        _ uiView: TouchCaptureUIView,
        context: Context
    ) {

        uiView.engine =
            engine
    }
}


// ============================================================
// UIKIT TOUCH VIEW
// ============================================================

final class TouchCaptureUIView:
    UIView {

    weak var engine:
        TouchscreenLatencyEngine?


    override init(
        frame: CGRect
    ) {

        super.init(
            frame: frame
        )

        isMultipleTouchEnabled = true

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
            touches,
            phase: .began
        )
    }


    override func touchesMoved(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches,
            phase: .moved
        )
    }


    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches,
            phase: .ended
        )
    }


    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches,
            phase: .cancelled
        )
    }


    private func process(
        _ touches: Set<UITouch>,
        phase: TouchLatencyPhase
    ) {

        for touch in touches {

            let location =
                touch.location(
                    in: self
                )

            engine?.recordTouch(
                phase: phase,
                timestamp: touch.timestamp,
                x: location.x,
                y: location.y,
                force: touch.force
            )
        }
    }
}


// ============================================================
// SWIFTUI DASHBOARD
// ============================================================

struct TouchLatencyDashboard:
    View {

    @StateObject
    private var engine =
        TouchscreenLatencyEngine()


    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 18
        ) {

            header

            Divider()

            latencyCard

            metricsGrid

            bottleneckCard

            Divider()

            Text("Touch capture area")
                .font(.headline)

            TouchLatencyCaptureView(
                engine: engine
            )
            .frame(
                height: 180
            )
            .background(
                .thinMaterial
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )

            Spacer()
        }
        .padding(24)
        .frame(
            minWidth: 430,
            minHeight: 650
        )
        .onAppear {

            engine.start()
        }
        .onDisappear {

            engine.stop()
        }
    }


    // MARK: Header

    private var header: some View {

        HStack {

            VStack(
                alignment: .leading
            ) {

                Text("Touch Intelligence")
                    .font(
                        .system(
                            size: 26,
                            weight: .semibold,
                            design: .rounded
                        )
                    )

                Text(
                    "Real-time touchscreen latency"
                )
                .foregroundStyle(
                    .secondary
                )
            }

            Spacer()

            Circle()
                .fill(
                    qualityColor
                )
                .frame(
                    width: 12,
                    height: 12
                )
        }
    }


    // MARK: Latency card

    private var latencyCard: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            Text("Touch-to-frame latency")
                .font(.subheadline)
                .foregroundStyle(
                    .secondary
                )

            HStack(
                alignment: .firstTextBaseline
            ) {

                Text(
                    String(
                        format: "%.2f",
                        engine.statistics
                            .medianLatencyMS
                    )
                )
                .font(
                    .system(
                        size: 48,
                        weight: .medium,
                        design: .rounded
                    )
                )

                Text("ms")
                    .font(.title3)
                    .foregroundStyle(
                        .secondary
                    )
            }

            Text(
                engine.quality.label
            )
            .font(.headline)
            .foregroundStyle(
                qualityColor
            )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
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

    private var metricsGrid: some View {

        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 12
        ) {

            metric(
                title: "P95",
                value:
                    "\(format(engine.statistics.p95LatencyMS)) ms"
            )

            metric(
                title: "P99",
                value:
                    "\(format(engine.statistics.p99LatencyMS)) ms"
            )

            metric(
                title: "Jitter",
                value:
                    "\(format(engine.statistics.jitterMS)) ms"
            )

            metric(
                title: "FPS",
                value:
                    "\(format(engine.statistics.estimatedFPS))"
            )

            metric(
                title: "Samples",
                value:
                    "\(engine.statistics.sampleCount)"
            )

            metric(
                title: "Frame drops",
                value:
                    "\(engine.statistics.droppedFrameCount)"
            )
        }
    }


    private func metric(
        title: String,
        value: String
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
                cornerRadius: 15,
                style: .continuous
            )
        )
    }


    // MARK: Bottleneck

    private var bottleneckCard: some View {

        HStack {

            Image(
                systemName:
                    "waveform.path.ecg"
            )
            .font(.title2)

            VStack(
                alignment: .leading
            ) {

                Text("Current bottleneck")
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                Text(
                    engine.bottleneck()
                )
                .font(.headline)
            }

            Spacer()
        }
        .padding(16)
        .background(
            .thinMaterial
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }


    private func format(
        _ value: Double
    ) -> String {

        String(
            format: "%.2f",
            value
        )
    }


    private var qualityColor:
        Color {

        switch engine.quality {

        case .excellent:
            return .green

        case .good:
            return .mint

        case .acceptable:
            return .yellow

        case .degraded:
            return .orange

        case .poor:
            return .red
        }
    }
}


// ============================================================
// COMPACT TOOLBAR POPUP
// ============================================================

struct TouchLatencyToolbarButton:
    View {

    @State
    private var showingDashboard =
        false

    var body: some View {

        Button {

            showingDashboard.toggle()

        } label: {

            Image(
                systemName:
                    "hand.tap"
            )
        }
        .popover(
            isPresented:
                $showingDashboard
        ) {

            TouchLatencyDashboard()
        }
    }
}


// ============================================================
// SIMPLE APP EXAMPLE
// ============================================================

struct TouchLatencyExample:
    View {

    var body: some View {

        TouchLatencyDashboard()
    }
}
```

