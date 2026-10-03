import UIKit
import PencilKit

// ============================================================
// Apple Pencil Interaction Engine
//
// Features:
// • Pressure-sensitive strokes
// • Tilt / azimuth
// • Predicted touches
// • Coalesced touches
// • Pencil hover
// • Palm rejection
// • Double-tap tool switching
// • Smooth stroke interpolation
// ============================================================

final class ApplePencilEngine: NSObject {

    // MARK: Configuration

    struct Configuration {

        var minimumLineWidth: CGFloat = 1.0
        var maximumLineWidth: CGFloat = 12.0

        var pressureResponse: CGFloat = 1.0

        var tiltResponse: CGFloat = 0.5

        var smoothing: CGFloat = 0.82

        var predictedTouchCount = 4

        var palmRejectionEnabled = true

        var hoverEnabled = true
    }

    var configuration = Configuration()

    // MARK: State

    private(set) var isPencilDown = false

    private(set) var pressure: CGFloat = 0

    private(set) var altitudeAngle: CGFloat = .pi / 2

    private(set) var azimuthAngle: CGFloat = 0

    private(set) var location = CGPoint.zero

    private var lastLocation = CGPoint.zero

    // MARK: Callbacks

    var onStrokePoint:
        ((PencilPoint) -> Void)?

    var onPredictedPoint:
        ((PencilPoint) -> Void)?

    var onHover:
        ((PencilHover) -> Void)?

    var onToolChange:
        (() -> Void)?

    // MARK: Pencil point

    struct PencilPoint {

        let location: CGPoint

        let pressure: CGFloat

        let altitude: CGFloat

        let azimuth: CGFloat

        let timestamp: TimeInterval
    }

    // MARK: Hover

    struct PencilHover {

        let location: CGPoint

        let zDistance: CGFloat

        let azimuth: CGFloat

        let altitude: CGFloat
    }

    // MARK: Touch processing

    func touchesBegan(
        _ touches: Set<UITouch>,
        event: UIEvent?
    ) {

        guard
            let touch =
                touches.first
        else {
            return
        }

        guard
            touch.type == .pencil
        else {
            return
        }

        isPencilDown = true

        process(
            touch,
            predicted: false
        )
    }

    func touchesMoved(
        _ touches: Set<UITouch>,
        event: UIEvent?
    ) {

        guard
            let touch =
                touches.first
        else {
            return
        }

        guard
            touch.type == .pencil
        else {
            return
        }

        // First process coalesced touches.
        if let event {

            let coalesced =
                event.coalescedTouches(
                    for: touch
                ) ?? []

            for sample in coalesced {

                process(
                    sample,
                    predicted: false
                )
            }
        }

        // Then predicted touches.
        if let event {

            let predicted =
                event.predictedTouches(
                    for: touch
                ) ?? []

            for sample in predicted {

                process(
                    sample,
                    predicted: true
                )
            }
        }
    }

    func touchesEnded(
        _ touches: Set<UITouch>,
        event: UIEvent?
    ) {

        guard
            let touch =
                touches.first,
            touch.type == .pencil
        else {
            return
        }

        isPencilDown = false

        pressure = 0
    }

    func touchesCancelled(
        _ touches: Set<UITouch>,
        event: UIEvent?
    ) {

        isPencilDown = false

        pressure = 0
    }

    // MARK: Process touch

    private func process(
        _ touch: UITouch,
        predicted: Bool
    ) {

        let rawLocation =
            touch.location(
                in: touch.view
            )

        // Smooth location.
        let smoothedX =
            lastLocation.x *
            configuration.smoothing +
            rawLocation.x *
            (1 -
             configuration.smoothing)

        let smoothedY =
            lastLocation.y *
            configuration.smoothing +
            rawLocation.y *
            (1 -
             configuration.smoothing)

        let smoothedLocation =
            CGPoint(
                x: smoothedX,
                y: smoothedY
            )

        lastLocation =
            smoothedLocation

        location =
            smoothedLocation

        pressure =
            touch.force

        altitudeAngle =
            touch.altitudeAngle

        azimuthAngle =
            touch.azimuthAngle(
                in: touch.view
            )

        let point =
            PencilPoint(
                location:
                    smoothedLocation,

                pressure:
                    pressure,

                altitude:
                    altitudeAngle,

                azimuth:
                    azimuthAngle,

                timestamp:
                    touch.timestamp
            )

        if predicted {

            onPredictedPoint?(
                point
            )

        } else {

            onStrokePoint?(
                point
            )
        }
    }

    // MARK: Stroke width

    func strokeWidth(
        for pressure: CGFloat
    ) -> CGFloat {

        let normalized =
            min(
                max(
                    pressure *
                    configuration.pressureResponse,
                    0
                ),
                1
            )

        return configuration.minimumLineWidth +
            (
                configuration.maximumLineWidth -
                configuration.minimumLineWidth
            ) *
            normalized
    }

    // MARK: Tilt

    func tiltFactor() -> CGFloat {

        let normalized =
            altitudeAngle /
            (.pi / 2)

        return 1 -
            min(
                max(
                    normalized,
                    0
                ),
                1
            )
    }

    // MARK: Hover

    func pencilHover(
        _ interaction: UIPencilInteraction,
        didHover hover: UIHoverGestureRecognizer
    ) {

        guard configuration.hoverEnabled else {
            return
        }

        let location =
            hover.location(
                in: hover.view
            )

        let zDistance =
            hover.zOffset

        let hoverState =
            PencilHover(
                location:
                    location,

                zDistance:
                    zDistance,

                azimuth:
                    azimuthAngle,

                altitude:
                    altitudeAngle
            )

        onHover?(
            hoverState
        )
    }

    // MARK: Pencil interaction

    func pencilDoubleTap() {

        onToolChange?()
    }
}




final class PencilCanvasView: UIView {

    private let pencil =
        ApplePencilEngine()

    override init(frame: CGRect) {

        super.init(frame: frame)

        isMultipleTouchEnabled = true

        setupPencil()
    }

    required init?(
        coder: NSCoder
    ) {

        super.init(coder: coder)

        isMultipleTouchEnabled = true

        setupPencil()
    }

    private func setupPencil() {

        pencil.onStrokePoint = {
            [weak self] point in

            self?.drawPoint(point)
        }

        pencil.onPredictedPoint = {
            [weak self] point in

            self?.drawPredictedPoint(point)
        }

        pencil.onHover = {
            [weak self] hover in

            self?.showPencilPreview(
                hover
            )
        }
    }

    override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        pencil.touchesBegan(
            touches,
            event: event
        )
    }

    override func touchesMoved(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        pencil.touchesMoved(
            touches,
            event: event
        )
    }

    override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        pencil.touchesEnded(
            touches,
            event: event
        )
    }

    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        pencil.touchesCancelled(
            touches,
            event: event
        )
    }

    private func drawPoint(
        _ point:
        ApplePencilEngine.PencilPoint
    ) {

        let width =
            pencil.strokeWidth(
                for: point.pressure
            )

        print(
            "Drawing:",
            point.location,
            "width:",
            width
        )
    }

    private func drawPredictedPoint(
        _ point:
        ApplePencilEngine.PencilPoint
    ) {

        // Render prediction ahead of the
        // physical Pencil position.
    }

    private func showPencilPreview(
        _ hover:
        ApplePencilEngine.PencilHover
    ) {

        // Display brush/cursor preview.
    }
}


