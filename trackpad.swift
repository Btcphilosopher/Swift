import UIKit
import QuartzCore

// ============================================================
// Apple Trackpad Interaction Engine
//
// Goals:
// • Low-latency pointer movement
// • Adaptive acceleration
// • Smooth scrolling
// • Inertial scrolling
// • Two-finger scrolling
// • Pinch zoom
// • Three-finger navigation
// • Edge resistance
// • Pointer smoothing
// • Click / secondary click
// • Haptic-ready architecture
// ============================================================

final class TrackpadEngine {

    // MARK: Configuration

    struct Configuration {

        var pointerSensitivity: CGFloat = 1.0

        var acceleration: CGFloat = 1.18

        var maximumPointerVelocity: CGFloat = 45.0

        var smoothing: CGFloat = 0.82

        var scrollSensitivity: CGFloat = 1.0

        var scrollDeceleration: CGFloat = 0.91

        var minimumScrollVelocity: CGFloat = 0.1

        var edgeResistance: CGFloat = 0.72

        var gestureThreshold: CGFloat = 25.0

        var clickThreshold: CGFloat = 0.15
    }

    // MARK: Pointer state

    struct PointerState {

        var position = CGPoint.zero

        var velocity = CGVector.zero

        var lastPosition = CGPoint.zero

        var lastTimestamp: CFTimeInterval = 0

        var isTracking = false
    }

    // MARK: Scroll state

    struct ScrollState {

        var velocity = CGVector.zero

        var offset = CGPoint.zero

        var isScrolling = false
    }

    // MARK: Gesture state

    enum Gesture {

        case none

        case tap

        case secondaryTap

        case twoFingerScroll

        case pinch(scale: CGFloat)

        case swipeLeft

        case swipeRight

        case swipeUp

        case swipeDown
    }

    // MARK: Properties

    var configuration = Configuration()

    private(set) var pointer = PointerState()

    private(set) var scroll = ScrollState()

    private(set) var currentGesture: Gesture = .none

    private var displayLink: CADisplayLink?

    // Application callbacks

    var onPointerMove:
        ((CGPoint) -> Void)?

    var onScroll:
        ((CGPoint) -> Void)?

    var onGesture:
        ((Gesture) -> Void)?

    var onClick:
        (() -> Void)?

    var onSecondaryClick:
        (() -> Void)?

    // MARK: Start

    func start() {

        displayLink?.invalidate()

        let link =
            CADisplayLink(
                target: self,
                selector: #selector(update)
            )

        displayLink = link

        link.add(
            to: .main,
            forMode: .common
        )
    }

    // MARK: Stop

    func stop() {

        displayLink?.invalidate()

        displayLink = nil
    }

    // MARK: Pointer input

    func pointerMoved(
        dx: CGFloat,
        dy: CGFloat,
        timestamp: CFTimeInterval
    ) {

        pointer.isTracking = true

        let dt =
            pointer.lastTimestamp == 0
            ? 1.0 / 120.0
            : max(
                timestamp -
                pointer.lastTimestamp,
                0.0001
            )

        pointer.lastTimestamp =
            timestamp

        let distance =
            hypot(dx, dy)

        let velocity =
            distance / CGFloat(dt)

        // Adaptive acceleration.
        let accelerationFactor =
            1.0 +
            min(
                velocity / 1000.0,
                1.0
            ) *
            configuration.acceleration

        var vx =
            dx *
            configuration.pointerSensitivity *
            accelerationFactor

        var vy =
            dy *
            configuration.pointerSensitivity *
            accelerationFactor

        // Limit maximum pointer velocity.
        let magnitude =
            hypot(vx, vy)

        if magnitude >
            configuration.maximumPointerVelocity {

            let scale =
                configuration.maximumPointerVelocity /
                magnitude

            vx *= scale
            vy *= scale
        }

        // Low-pass smoothing.
        pointer.velocity.dx =
            pointer.velocity.dx *
            configuration.smoothing +
            vx *
            (1 -
             configuration.smoothing)

        pointer.velocity.dy =
            pointer.velocity.dy *
            configuration.smoothing +
            vy *
            (1 -
             configuration.smoothing)
    }

    // MARK: Display update

    @objc private func update() {

        let vx =
            pointer.velocity.dx

        let vy =
            pointer.velocity.dy

        guard
            abs(vx) > 0.001 ||
            abs(vy) > 0.001
        else {
            return
        }

        pointer.position.x += vx
        pointer.position.y += vy

        pointer.lastPosition =
            pointer.position

        onPointerMove?(
            pointer.position
        )

        // Gradually remove residual motion.
        pointer.velocity.dx *= 0.88
        pointer.velocity.dy *= 0.88

        updateScroll()
    }

    // MARK: Scroll

    func scrollBy(
        dx: CGFloat,
        dy: CGFloat
    ) {

        scroll.isScrolling = true

        scroll.velocity.dx +=
            dx *
            configuration.scrollSensitivity

        scroll.velocity.dy +=
            dy *
            configuration.scrollSensitivity
    }

    private func updateScroll() {

        guard scroll.isScrolling else {
            return
        }

        let dx =
            scroll.velocity.dx

        let dy =
            scroll.velocity.dy

        guard
            abs(dx) >
                configuration.minimumScrollVelocity ||
            abs(dy) >
                configuration.minimumScrollVelocity
        else {

            scroll.isScrolling = false

            scroll.velocity = .zero

            return
        }

        scroll.offset.x += dx
        scroll.offset.y += dy

        onScroll?(
            scroll.offset
        )

        scroll.velocity.dx *=
            configuration.scrollDeceleration

        scroll.velocity.dy *=
            configuration.scrollDeceleration
    }

    // MARK: Tap

    func tap() {

        currentGesture = .tap

        onClick?()

        DispatchQueue.main.async {
            self.currentGesture = .none
        }
    }

    // MARK: Secondary click

    func secondaryTap() {

        currentGesture =
            .secondaryTap

        onSecondaryClick?()

        DispatchQueue.main.async {
            self.currentGesture = .none
        }
    }

    // MARK: Pinch

    func pinch(
        scale: CGFloat
    ) {

        currentGesture =
            .pinch(scale: scale)

        onGesture?(
            currentGesture
        )
    }

    // MARK: Swipe

    func swipe(
        dx: CGFloat,
        dy: CGFloat
    ) {

        let distance =
            hypot(dx, dy)

        guard
            distance >=
            configuration.gestureThreshold
        else {
            return
        }

        if abs(dx) > abs(dy) {

            if dx > 0 {

                currentGesture =
                    .swipeRight

            } else {

                currentGesture =
                    .swipeLeft
            }

        } else {

            if dy > 0 {

                currentGesture =
                    .swipeDown

            } else {

                currentGesture =
                    .swipeUp
            }
        }

        onGesture?(
            currentGesture
        )

        DispatchQueue.main.async {
            self.currentGesture = .none
        }
    }

    // MARK: Reset

    func reset() {

        pointer = PointerState()

        scroll = ScrollState()

        currentGesture = .none
    }

    deinit {

        stop()
    }
}




final class ApplePointerController:
    NSObject,
    UIPointerInteractionDelegate {

    func install(
        on view: UIView
    ) {

        let interaction =
            UIPointerInteraction(
                delegate: self
            )

        view.addInteraction(
            interaction
        )
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        styleFor region: UIPointerRegion
    ) -> UIPointerStyle? {

        guard
            let view =
                interaction.view
        else {
            return nil
        }

        let preview =
            UITargetedPreview(
                view: view
            )

        return UIPointerStyle(
            effect:
                .lift(preview)
        )
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        willEnter region: UIPointerRegion,
        animator: UIPointerInteractionAnimating
    ) {

        animator.addAnimations {

            interaction.view?.transform =
                CGAffineTransform(
                    scaleX: 1.025,
                    y: 1.025
                )
        }
    }

    func pointerInteraction(
        _ interaction: UIPointerInteraction,
        willExit region: UIPointerRegion,
        animator: UIPointerInteractionAnimating
    ) {

        animator.addAnimations {

            interaction.view?.transform =
                .identity
        }
    }
}




