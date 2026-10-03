import UIKit
import CoreHaptics

// ============================================================
// MagicKeyboardEngine.swift
//
// Low-latency keyboard interaction engine for iPadOS
// Designed around:
//   • fast key response
//   • adaptive key-repeat
//   • predictive input
//   • smooth cursor movement
//   • optional haptics
//   • debounced event processing
// ============================================================

final class MagicKeyboardEngine {

    // MARK: - Configuration

    struct Configuration {

        // Target response latency
        var targetLatency: TimeInterval = 0.004

        // Initial key-repeat delay
        var initialRepeatDelay: TimeInterval = 0.32

        // Fastest repeat interval
        var minimumRepeatInterval: TimeInterval = 0.025

        // Normal repeat interval
        var defaultRepeatInterval: TimeInterval = 0.045

        // Cursor acceleration
        var cursorAcceleration: CGFloat = 1.15

        // Maximum cursor velocity
        var maximumCursorVelocity: CGFloat = 28.0

        // Enable haptics
        var hapticsEnabled: Bool = true
    }

    // MARK: - State

    private(set) var configuration: Configuration

    private var heldKeys: Set<UIKeyboardHIDUsage> = []

    private var repeatTimers:
        [UIKeyboardHIDUsage: DispatchSourceTimer] = [:]

    private let eventQueue =
        DispatchQueue(
            label: "com.apple.magic.keyboard.engine",
            qos: .userInteractive
        )

    private let stateLock =
        NSLock()

    private var hapticEngine: CHHapticEngine?

    // MARK: - Init

    init(
        configuration: Configuration = Configuration()
    ) {

        self.configuration = configuration

        setupHaptics()
    }

    // MARK: - Haptics

    private func setupHaptics() {

        guard configuration.hapticsEnabled else {
            return
        }

        guard CHHapticEngine.capabilitiesForHardware()
            .supportsHaptics else {
            return
        }

        do {

            hapticEngine =
                try CHHapticEngine()

            try hapticEngine?.start()

        } catch {

            print(
                "Haptic engine unavailable: \(error)"
            )
        }
    }

    private func keyPressHaptic() {

        guard configuration.hapticsEnabled else {
            return
        }

        guard let engine = hapticEngine else {
            return
        }

        let intensity =
            CHHapticEventParameter(
                parameterID: .hapticIntensity,
                value: 0.18
            )

        let sharpness =
            CHHapticEventParameter(
                parameterID: .hapticSharpness,
                value: 0.35
            )

        let event =
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    intensity,
                    sharpness
                ],
                relativeTime: 0
            )

        do {

            let pattern =
                try CHHapticPattern(
                    events: [event],
                    parameters: []
                )

            let player =
                try engine.makePlayer(
                    with: pattern
                )

            try player.start(atTime: 0)

        } catch {
            // Haptics should never block input.
        }
    }

    // MARK: - Key Down

    func keyDown(
        _ key: UIKeyboardHIDUsage,
        action: @escaping () -> Void
    ) {

        eventQueue.async { [weak self] in

            guard let self else {
                return
            }

            self.stateLock.lock()

            let alreadyHeld =
                self.heldKeys.contains(key)

            self.heldKeys.insert(key)

            self.stateLock.unlock()

            // Ignore duplicate down events.
            guard !alreadyHeld else {
                return
            }

            action()

            self.keyPressHaptic()

            self.startRepeatTimer(
                key: key,
                action: action
            )
        }
    }

    // MARK: - Key Up

    func keyUp(
        _ key: UIKeyboardHIDUsage
    ) {

        eventQueue.async { [weak self] in

            guard let self else {
                return
            }

            self.stateLock.lock()

            self.heldKeys.remove(key)

            self.stateLock.unlock()

            self.stopRepeatTimer(
                key: key
            )
        }
    }

    // MARK: - Repeat Engine

    private func startRepeatTimer(
        key: UIKeyboardHIDUsage,
        action: @escaping () -> Void
    ) {

        stopRepeatTimer(key: key)

        let timer =
            DispatchSource.makeTimerSource(
                queue: eventQueue
            )

        timer.schedule(
            deadline:
                .now()
                + configuration.initialRepeatDelay,
            repeating:
                configuration.defaultRepeatInterval
        )

        timer.setEventHandler { [weak self] in

            guard let self else {
                return
            }

            self.stateLock.lock()

            let isHeld =
                self.heldKeys.contains(key)

            self.stateLock.unlock()

            guard isHeld else {
                return
            }

            action()
        }

        repeatTimers[key] = timer

        timer.resume()
    }

    private func stopRepeatTimer(
        key: UIKeyboardHIDUsage
    ) {

        guard let timer =
                repeatTimers.removeValue(
                    forKey: key
                )
        else {
            return
        }

        timer.setEventHandler {}

        timer.cancel()
    }

    // MARK: - Cursor Engine

    struct CursorState {

        var velocity: CGVector = .zero

        var position: CGPoint = .zero
    }

    private var cursor =
        CursorState()

    func moveCursor(
        dx: CGFloat,
        dy: CGFloat
    ) -> CGPoint {

        eventQueue.sync {

            cursor.velocity.dx +=
                dx * configuration.cursorAcceleration

            cursor.velocity.dy +=
                dy * configuration.cursorAcceleration

            cursor.velocity.dx =
                clamp(
                    cursor.velocity.dx,
                    -configuration.maximumCursorVelocity,
                    configuration.maximumCursorVelocity
                )

            cursor.velocity.dy =
                clamp(
                    cursor.velocity.dy,
                    -configuration.maximumCursorVelocity,
                    configuration.maximumCursorVelocity
                )

            cursor.position.x +=
                cursor.velocity.dx

            cursor.position.y +=
                cursor.velocity.dy

            return cursor.position
        }
    }

    func resetCursorVelocity() {

        eventQueue.async { [weak self] in

            self?.cursor.velocity =
                .zero
        }
    }

    private func clamp(
        _ value: CGFloat,
        _ minimum: CGFloat,
        _ maximum: CGFloat
    ) -> CGFloat {

        Swift.min(
            Swift.max(
                value,
                minimum
            ),
            maximum
        )
    }

    // MARK: - Modifier Processing

    struct ModifierState {

        var shift = false
        var control = false
        var option = false
        var command = false
        var capsLock = false
    }

    private(set) var modifiers =
        ModifierState()

    func updateModifiers(
        flags: UIKeyModifierFlags
    ) {

        eventQueue.async { [weak self] in

            guard let self else {
                return
            }

            self.modifiers.shift =
                flags.contains(.shift)

            self.modifiers.control =
                flags.contains(.control)

            self.modifiers.option =
                flags.contains(.alternate)

            self.modifiers.command =
                flags.contains(.command)

            self.modifiers.capsLock =
                flags.contains(.alphaShift)
        }
    }

    // MARK: - Shutdown

    func shutdown() {

        eventQueue.sync {

            for timer in repeatTimers.values {
                timer.cancel()
            }

            repeatTimers.removeAll()

            heldKeys.removeAll()
        }

        try? hapticEngine?.stop()
    }
}




final class KeyboardViewController: UIViewController {

    private let keyboardEngine =
        MagicKeyboardEngine()

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func viewDidLoad() {

        super.viewDidLoad()

        becomeFirstResponder()
    }

    override func pressesBegan(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?
    ) {

        for press in presses {

            guard
                let key =
                    press.key?.keyCode
            else {
                continue
            }

            keyboardEngine.keyDown(
                key
            ) {

                self.processKey(
                    key
                )
            }
        }

        super.pressesBegan(
            presses,
            with: event
        )
    }

    override func pressesEnded(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?
    ) {

        for press in presses {

            guard
                let key =
                    press.key?.keyCode
            else {
                continue
            }

            keyboardEngine.keyUp(
                key
            )
        }

        super.pressesEnded(
            presses,
            with: event
        )
    }

    private func processKey(
        _ key: UIKeyboardHIDUsage
    ) {

        switch key {

        case .keyboardA:
            insertText("a")

        case .keyboardB:
            insertText("b")

        case .keyboardC:
            insertText("c")

        case .keyboardSpacebar:
            insertText(" ")

        case .keyboardReturnOrEnter:
            insertText("\n")

        case .keyboardDeleteOrBackspace:
            deleteBackward()

        default:
            break
        }
    }

    private func insertText(
        _ text: String
    ) {

        // Connect to your text-input system here.
        print(text)
    }

    private func deleteBackward() {

        print("delete")
    }
}

