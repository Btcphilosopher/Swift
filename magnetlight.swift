import Foundation
import UIKit

// ============================================================
// Apple Multi-Colour Charging Light
//
// States:
//   • charging
//   • fully charged
//   • disconnected
//
// Fully charged mode:
//   • cycles through selectable colours
//   • smooth colour transitions
//   • adjustable speed
//   • brightness control
// ============================================================

final class ChargingLightController {

    enum ChargingState {
        case disconnected
        case charging
        case fullyCharged
    }

    struct LightColour {
        let name: String
        let colour: UIColor
    }

    // MARK: - Available colours

    let availableColours: [LightColour] = [

        LightColour(
            name: "White",
            colour: .white
        ),

        LightColour(
            name: "Blue",
            colour: .systemBlue
        ),

        LightColour(
            name: "Cyan",
            colour: .cyan
        ),

        LightColour(
            name: "Green",
            colour: .systemGreen
        ),

        LightColour(
            name: "Yellow",
            colour: .systemYellow
        ),

        LightColour(
            name: "Orange",
            colour: .systemOrange
        ),

        LightColour(
            name: "Pink",
            colour: .systemPink
        ),

        LightColour(
            name: "Purple",
            colour: .systemPurple
        )
    ]

    // MARK: - Configuration

    var transitionDuration: TimeInterval = 1.2

    var cycleDuration: TimeInterval = 4.0

    var brightness: CGFloat = 1.0

    var enableRainbowMode = true

    // User-selected colours
    private(set) var selectedColours: [LightColour]

    // MARK: - State

    private(set) var state:
        ChargingState = .disconnected

    private var currentIndex = 0

    private var timer: Timer?

    // Closure used to send colour to physical LED
    var outputColour: ((UIColor) -> Void)?

    // MARK: - Initialisation

    init() {

        selectedColours = availableColours

    }

    // MARK: - Charging state

    func setChargingState(
        _ newState: ChargingState
    ) {

        state = newState

        stopAnimation()

        switch newState {

        case .disconnected:

            setColour(.clear)

        case .charging:

            // Standard charging indication
            setColour(.systemBlue)

        case .fullyCharged:

            if enableRainbowMode {
                startRainbow()
            } else {
                setColour(.systemGreen)
            }
        }
    }

    // MARK: - Rainbow mode

    private func startRainbow() {

        guard !selectedColours.isEmpty else {
            return
        }

        currentIndex = 0

        setColour(
            selectedColours[0].colour
        )

        timer = Timer.scheduledTimer(
            withTimeInterval: cycleDuration,
            repeats: true
        ) { [weak self] _ in

            self?.advanceColour()
        }
    }

    private func advanceColour() {

        guard !selectedColours.isEmpty else {
            return
        }

        currentIndex += 1

        if currentIndex >= selectedColours.count {
            currentIndex = 0
        }

        let next =
            selectedColours[currentIndex]

        transitionTo(
            next.colour
        )
    }

    // MARK: - Smooth transition

    private func transitionTo(
        _ colour: UIColor
    ) {

        // Physical accessory implementations would
        // replace this with the LED hardware command.

        UIView.animate(
            withDuration: transitionDuration,
            delay: 0,
            options: [
                .curveEaseInOut,
                .allowUserInteraction
            ]
        ) {

            self.setColour(colour)

        }
    }

    // MARK: - Hardware output

    private func setColour(
        _ colour: UIColor
    ) {

        let adjusted =
            colour.withAlphaComponent(
                brightness
            )

        outputColour?(adjusted)
    }

    // MARK: - Colour selection

    func selectColours(
        names: [String]
    ) {

        selectedColours =
            availableColours.filter {
                names.contains($0.name)
            }

        if selectedColours.isEmpty {

            selectedColours =
                availableColours
        }

        if state == .fullyCharged {

            stopAnimation()

            if enableRainbowMode {
                startRainbow()
            }
        }
    }

    // MARK: - Add individual colour

    func addColour(
        named name: String
    ) {

        guard
            let colour =
                availableColours.first(
                    where: { $0.name == name }
                )
        else {
            return
        }

        if !selectedColours.contains(
            where: { $0.name == name }
        ) {

            selectedColours.append(
                colour
            )
        }
    }

    // MARK: - Remove colour

    func removeColour(
        named name: String
    ) {

        selectedColours.removeAll {
            $0.name == name
        }
    }

    // MARK: - Animation control

    func stopAnimation() {

        timer?.invalidate()

        timer = nil
    }

    // MARK: - Cleanup

    deinit {

        stopAnimation()
    }
}



let chargerLight =
    ChargingLightController()

chargerLight.transitionDuration = 1.5
chargerLight.cycleDuration = 3.0
chargerLight.brightness = 0.8

chargerLight.selectColours(
    names: [
        "Blue",
        "Cyan",
        "Purple",
        "Pink",
        "Orange",
        "Green"
    ]
)

chargerLight.enableRainbowMode = true

chargerLight.outputColour = { colour in

    // This is where the physical accessory
    // LED command would be sent.

    print("LED colour:", colour)
}

Then the charging system could simply report:

chargerLight.setChargingState(.charging)

and, when charging reaches 100%:

chargerLight.setChargingState(.fullyCharged)

