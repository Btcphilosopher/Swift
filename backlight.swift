import Foundation
import UIKit

// ============================================================
// Magic Keyboard Backlight Controller
//
// Features:
// • Brightness control
// • Ambient-light adaptation
// • Smooth fade transitions
// • Typing-reactive illumination
// • Static / breathing / wave modes
// • Automatic idle timeout
// • Hardware abstraction for real LED implementation
// ============================================================

final class KeyboardBacklightController {

    // MARK: - Lighting modes

    enum Mode {
        case off
        case staticLight
        case breathing
        case typing
        case wave
        case automatic
    }

    // MARK: - Hardware interface

    protocol HardwareInterface: AnyObject {

        func setBrightness(_ brightness: Float)

        func setKeyBrightness(
            key: Int,
            brightness: Float
        )

        func setAllKeys(
            brightness: Float
        )
    }

    // MARK: - Configuration

    struct Configuration {

        var maximumBrightness: Float = 1.0

        var minimumBrightness: Float = 0.02

        var fadeDuration: TimeInterval = 0.25

        var idleTimeout: TimeInterval = 30.0

        var ambientAdaptation = true

        var typingBoost: Float = 0.15

        var breathingPeriod: TimeInterval = 3.5
    }

    // MARK: - State

    private(set) var mode: Mode = .automatic

    private(set) var brightness: Float = 0

    private(set) var ambientLight: Float = 0.5

    private var idleTimer: Timer?

    private var animationTimer: Timer?

    private var configuration: Configuration

    weak var hardware: HardwareInterface?

    // MARK: - Init

    init(
        configuration: Configuration = Configuration()
    ) {

        self.configuration = configuration
    }

    // MARK: - Mode

    func setMode(
        _ mode: Mode
    ) {

        self.mode = mode

        stopAnimation()

        switch mode {

        case .off:

            setBrightnessSmoothly(0)

        case .staticLight:

            setBrightnessSmoothly(
                configuration.maximumBrightness
            )

        case .breathing:

            startBreathing()

        case .typing:

            setBrightnessSmoothly(
                calculateAutomaticBrightness()
            )

        case .wave:

            startWave()

        case .automatic:

            updateAutomaticBrightness()
        }
    }

    // MARK: - Manual brightness

    func setBrightness(
        _ value: Float
    ) {

        let clamped =
            min(
                max(
                    value,
                    0
                ),
                configuration.maximumBrightness
            )

        setBrightnessSmoothly(clamped)
    }

    // MARK: - Smooth brightness transition

    private func setBrightnessSmoothly(
        _ target: Float
    ) {

        let start = brightness

        let duration =
            configuration.fadeDuration

        let steps = 30

        var step = 0

        animationTimer?.invalidate()

        animationTimer =
            Timer.scheduledTimer(
                withTimeInterval:
                    duration / Double(steps),
                repeats: true
            ) { [weak self] timer in

                guard let self else {
                    timer.invalidate()
                    return
                }

                step += 1

                let progress =
                    Float(step) / Float(steps)

                let eased =
                    progress * progress *
                    (3 - 2 * progress)

                self.brightness =
                    start +
                    (target - start) *
                    eased

                self.hardware?
                    .setBrightness(
                        self.brightness
                    )

                if step >= steps {

                    timer.invalidate()

                    self.brightness =
                        target
                }
            }
    }

    // MARK: - Ambient light

    func updateAmbientLight(
        _ level: Float
    ) {

        ambientLight =
            min(
                max(level, 0),
                1
            )

        guard configuration.ambientAdaptation else {
            return
        }

        guard mode == .automatic else {
            return
        }

        updateAutomaticBrightness()
    }

    private func calculateAutomaticBrightness()
        -> Float
    {

        // Dark room → brighter keyboard
        //
        // Bright room → dimmer keyboard

        let darkness =
            1.0 - ambientLight

        let minimum =
            configuration.minimumBrightness

        let maximum =
            configuration.maximumBrightness

        return minimum +
            (maximum - minimum) *
            darkness
    }

    private func updateAutomaticBrightness() {

        let target =
            calculateAutomaticBrightness()

        setBrightnessSmoothly(target)
    }

    // MARK: - Typing response

    func keyPressed(
        _ key: Int
    ) {

        resetIdleTimer()

        let base =
            calculateAutomaticBrightness()

        let boosted =
            min(
                base +
                configuration.typingBoost,
                configuration.maximumBrightness
            )

        hardware?
            .setKeyBrightness(
                key: key,
                brightness: boosted
            )

        // Return smoothly to ambient level.
        DispatchQueue.main.asyncAfter(
            deadline:
                .now() + 0.08
        ) { [weak self] in

            guard let self else {
                return
            }

            self.hardware?
                .setKeyBrightness(
                    key: key,
                    brightness:
                        self.calculateAutomaticBrightness()
                )
        }
    }

    // MARK: - Idle timeout

    private func resetIdleTimer() {

        idleTimer?.invalidate()

        idleTimer =
            Timer.scheduledTimer(
                withTimeInterval:
                    configuration.idleTimeout,
                repeats: false
            ) { [weak self] _ in

                self?.fadeToIdle()
            }
    }

    private func fadeToIdle() {

        setBrightnessSmoothly(
            configuration.minimumBrightness
        )
    }

    // MARK: - Breathing mode

    private func startBreathing() {

        var phase: Double = 0

        animationTimer =
            Timer.scheduledTimer(
                withTimeInterval: 1.0 / 60.0,
                repeats: true
            ) { [weak self] timer in

                guard let self else {
                    timer.invalidate()
                    return
                }

                phase +=
                    1.0 / 60.0

                let angle =
                    phase /
                    self.configuration.breathingPeriod *
                    2.0 *
                    Double.pi

                let value =
                    (sin(angle) + 1.0) / 2.0

                let brightness =
                    Float(value) *
                    self.configuration.maximumBrightness

                self.hardware?
                    .setBrightness(
                        brightness
                    )
            }
    }

    // MARK: - Wave mode

    private func startWave() {

        var position = 0

        animationTimer =
            Timer.scheduledTimer(
                withTimeInterval:
                    1.0 / 60.0,
                repeats: true
            ) { [weak self] timer in

                guard let self else {
                    timer.invalidate()
                    return
                }

                // Example 78-key layout.
                let keyCount = 78

                for key in 0..<keyCount {

                    let distance =
                        abs(
                            key - position
                        )

                    let intensity =
                        max(
                            0,
                            1.0 -
                            Float(distance) / 10.0
                        )

                    self.hardware?
                        .setKeyBrightness(
                            key: key,
                            brightness: intensity
                        )
                }

                position += 1

                if position >= keyCount {
                    position = 0
                }
            }
    }

    // MARK: - Stop animations

    private func stopAnimation() {

        animationTimer?.invalidate()

        animationTimer = nil
    }

    // MARK: - Shutdown

    func shutdown() {

        stopAnimation()

        idleTimer?.invalidate()

        hardware?
            .setAllKeys(
                brightness: 0
            )
    }
}





final class AppleKeyboardHardware:
    KeyboardBacklightController.HardwareInterface {

    func setBrightness(
        _ brightness: Float
    ) {

        // Send brightness command to
        // the keyboard accessory.
    }

    func setKeyBrightness(
        key: Int,
        brightness: Float
    ) {

        // Send individual-key command
        // if hardware supports per-key LEDs.
    }

    func setAllKeys(
        brightness: Float
    ) {

        // Hardware-level command.
    }
}



let hardware =
    AppleKeyboardHardware()

let controller =
    KeyboardBacklightController()

controller.hardware =
    hardware

controller.setMode(
    .automatic
)


