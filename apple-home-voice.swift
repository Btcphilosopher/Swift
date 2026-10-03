```swift
//
// AppleHomeVoiceKit.swift
//
// Voice-control foundation for Apple Home.
//
// Pipeline:
//
// Microphone
//     ↓
// AVAudioEngine
//     ↓
// Speech Recognition
//     ↓
// Command Parser
//     ↓
// Intent
//     ↓
// HomeKit / Home Automation
//     ↓
// Device
//

import Foundation
import AVFoundation
import Speech
import HomeKit

// ============================================================
// MARK: - Voice Intent
// ============================================================

enum HomeVoiceAction {
    case turnOn
    case turnOff
    case setBrightness
    case setTemperature
    case setScene
    case lock
    case unlock
    case open
    case close
    case unknown
}

struct HomeVoiceIntent {

    let action: HomeVoiceAction

    let accessoryName: String?

    let roomName: String?

    let value: Double?

    let rawText: String
}


// ============================================================
// MARK: - Speech Engine
// ============================================================

@MainActor
final class HomeSpeechEngine:
    NSObject,
    ObservableObject {

    @Published private(set) var transcript = ""

    @Published private(set) var isListening = false

    @Published private(set) var authorizationGranted = false

    private let audioEngine =
        AVAudioEngine()

    private let speechRecognizer =
        SFSpeechRecognizer(
            locale: Locale(
                identifier: "en-GB"
            )
        )

    private var recognitionRequest:
        SFSpeechAudioBufferRecognitionRequest?

    private var recognitionTask:
        SFSpeechRecognitionTask?


    // ========================================================
    // MARK: Authorization
    // ========================================================

    func requestAuthorization() async {

        let speechStatus =
            await withCheckedContinuation {
                continuation in

                SFSpeechRecognizer.requestAuthorization {
                    status in

                    continuation.resume(
                        returning: status
                    )
                }
            }

        let microphoneGranted =
            await AVAudioApplication.requestRecordPermission()

        authorizationGranted =
            speechStatus == .authorized &&
            microphoneGranted
    }


    // ========================================================
    // MARK: Start Listening
    // ========================================================

    func startListening() throws {

        guard authorizationGranted else {
            throw VoiceError.notAuthorized
        }

        stopListening()

        transcript = ""

        let session =
            AVAudioSession.sharedInstance()

        try session.setCategory(
            .record,
            mode: .measurement,
            options: [
                .duckOthers
            ]
        )

        try session.setActive(
            true,
            options: .notifyOthersOnDeactivation
        )

        let request =
            SFSpeechAudioBufferRecognitionRequest()

        request.shouldReportPartialResults = true

        if #available(
            iOS 13.0,
            macOS 10.15,
            *
        ) {

            request.requiresOnDeviceRecognition =
                true
        }

        recognitionRequest =
            request

        let inputNode =
            audioEngine.inputNode

        let recordingFormat =
            inputNode.outputFormat(
                forBus: 0
            )

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat
        ) {
            [weak self] buffer, _ in

            self?.recognitionRequest?
                .append(buffer)
        }

        recognitionTask =
            speechRecognizer?.recognitionTask(
                with: request
            ) {
                [weak self] result, error in

                guard let self else {
                    return
                }

                if let result {

                    Task { @MainActor in

                        self.transcript =
                            result.bestTranscription
                            .formattedString
                    }
                }

                if error != nil {

                    Task { @MainActor in
                        self.stopListening()
                    }
                }
            }

        audioEngine.prepare()

        try audioEngine.start()

        isListening = true
    }


    // ========================================================
    // MARK: Stop Listening
    // ========================================================

    func stopListening() {

        audioEngine.stop()

        audioEngine.inputNode.removeTap(
            onBus: 0
        )

        recognitionRequest?
            .endAudio()

        recognitionRequest = nil

        recognitionTask?.cancel()

        recognitionTask = nil

        isListening = false

        try? AVAudioSession.sharedInstance()
            .setActive(
                false,
                options:
                    .notifyOthersOnDeactivation
            )
    }
}


// ============================================================
// MARK: - Errors
// ============================================================

enum VoiceError: Error {

    case notAuthorized

    case speechRecognitionUnavailable

    case audioUnavailable
}


// ============================================================
// MARK: - Command Parser
// ============================================================

struct HomeCommandParser {

    func parse(
        _ text: String
    ) -> HomeVoiceIntent {

        let normalized =
            text
                .lowercased()
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )


        // ----------------------------------------------------
        // TURN ON
        // ----------------------------------------------------

        if normalized.contains("turn on") ||
           normalized.contains("switch on") {

            return HomeVoiceIntent(
                action: .turnOn,
                accessoryName:
                    extractAccessory(
                        from: normalized
                    ),
                roomName:
                    extractRoom(
                        from: normalized
                    ),
                value: nil,
                rawText: text
            )
        }


        // ----------------------------------------------------
        // TURN OFF
        // ----------------------------------------------------

        if normalized.contains("turn off") ||
           normalized.contains("switch off") {

            return HomeVoiceIntent(
                action: .turnOff,
                accessoryName:
                    extractAccessory(
                        from: normalized
                    ),
                roomName:
                    extractRoom(
                        from: normalized
                    ),
                value: nil,
                rawText: text
            )
        }


        // ----------------------------------------------------
        // BRIGHTNESS
        // ----------------------------------------------------

        if normalized.contains("brightness") {

            let value =
                extractPercentage(
                    from: normalized
                )

            return HomeVoiceIntent(
                action: .setBrightness,
                accessoryName:
                    extractAccessory(
                        from: normalized
                    ),
                roomName:
                    extractRoom(
                        from: normalized
                    ),
                value: value,
                rawText: text
            )
        }


        // ----------------------------------------------------
        // TEMPERATURE
        // ----------------------------------------------------

        if normalized.contains("temperature") ||
           normalized.contains("degrees") {

            let value =
                extractTemperature(
                    from: normalized
                )

            return HomeVoiceIntent(
                action: .setTemperature,
                accessoryName:
                    extractAccessory(
                        from: normalized
                    ),
                roomName:
                    extractRoom(
                        from: normalized
                    ),
                value: value,
                rawText: text
            )
        }


        // ----------------------------------------------------
        // LOCK
        // ----------------------------------------------------

        if normalized.contains("lock") {

            return HomeVoiceIntent(
                action: .lock,
                accessoryName:
                    extractAccessory(
                        from: normalized
                    ),
                roomName:
                    extractRoom(
                        from: normalized
                    ),
                value: nil,
                rawText: text
            )
        }


        // ----------------------------------------------------
        // UNLOCK
        // ----------------------------------------------------

        if normalized.contains("unlock") {

            return HomeVoiceIntent(
                action: .unlock,
                accessoryName:
                    extractAccessory(
                        from: normalized
                    ),
                roomName:
                    extractRoom(
                        from: normalized
                    ),
                value: nil,
                rawText: text
            )
        }


        return HomeVoiceIntent(
            action: .unknown,
            accessoryName: nil,
            roomName: nil,
            value: nil,
            rawText: text
        )
    }


    private func extractAccessory(
        from text: String
    ) -> String? {

        let keywords = [
            "light",
            "lights",
            "lamp",
            "heating",
            "thermostat",
            "door",
            "lock",
            "fan",
            "television",
            "tv"
        ]

        return keywords.first {
            text.contains($0)
        }
    }


    private func extractRoom(
        from text: String
    ) -> String? {

        let rooms = [
            "kitchen",
            "bedroom",
            "living room",
            "office",
            "bathroom",
            "hallway",
            "dining room",
            "garage",
            "garden"
        ]

        return rooms.first {
            text.contains($0)
        }
    }


    private func extractPercentage(
        from text: String
    ) -> Double? {

        let pattern =
            #"(\d{1,3})\s*(%|percent)"#

        guard
            let regex =
                try? NSRegularExpression(
                    pattern: pattern
                )
        else {
            return nil
        }

        let range =
            NSRange(
                text.startIndex...,
                in: text
            )

        guard
            let match =
                regex.firstMatch(
                    in: text,
                    range: range
                )
        else {
            return nil
        }

        guard
            let valueRange =
                Range(
                    match.range(at: 1),
                    in: text
                )
        else {
            return nil
        }

        return Double(
            text[valueRange]
        )
    }


    private func extractTemperature(
        from text: String
    ) -> Double? {

        let pattern =
            #"(-?\d+(?:\.\d+)?)\s*(degrees|°)?"#

        guard
            let regex =
                try? NSRegularExpression(
                    pattern: pattern
                )
        else {
            return nil
        }

        let range =
            NSRange(
                text.startIndex...,
                in: text
            )

        guard
            let match =
                regex.firstMatch(
                    in: text,
                    range: range
                )
        else {
            return nil
        }

        guard
            let valueRange =
                Range(
                    match.range(at: 1),
                    in: text
                )
        else {
            return nil
        }

        return Double(
            text[valueRange]
        )
    }
}


// ============================================================
// MARK: - HomeKit Controller
// ============================================================

@MainActor
final class AppleHomeController:
    NSObject,
    ObservableObject {

    private let homeManager =
        HMHomeManager()

    private var home:
        HMHome?

    override init() {

        super.init()

        homeManager.delegate = self
    }


    // ========================================================
    // MARK: Find Accessory
    // ========================================================

    func findAccessory(
        named name: String
    ) -> HMAccessory? {

        guard let home else {
            return nil
        }

        for accessory in home.accessories {

            if accessory.name
                .localizedCaseInsensitiveCompare(
                    name
                ) == .orderedSame {

                return accessory
            }
        }

        return nil
    }


    // ========================================================
    // MARK: Turn On
    // ========================================================

    func turnOn(
        accessory: HMAccessory
    ) async throws {

        for service in accessory.services {

            for characteristic
                in service.characteristics {

                if characteristic.characteristicType ==
                    HMCharacteristicTypePowerState {

                    try await characteristic
                        .writeValue(true)
                }
            }
        }
    }


    // ========================================================
    // MARK: Turn Off
    // ========================================================

    func turnOff(
        accessory: HMAccessory
    ) async throws {

        for service in accessory.services {

            for characteristic
                in service.characteristics {

                if characteristic.characteristicType ==
                    HMCharacteristicTypePowerState {

                    try await characteristic
                        .writeValue(false)
                }
            }
        }
    }


    // ========================================================
    // MARK: Brightness
    // ========================================================

    func setBrightness(
        accessory: HMAccessory,
        percentage: Double
    ) async throws {

        let value =
            Int(
                max(
                    0,
                    min(
                        percentage,
                        100
                    )
                )
            )

        for service in accessory.services {

            for characteristic
                in service.characteristics {

                if characteristic.characteristicType ==
                    HMCharacteristicTypeBrightness {

                    try await characteristic
                        .writeValue(value)
                }
            }
        }
    }
}


// ============================================================
// MARK: - HomeKit Delegate
// ============================================================

extension AppleHomeController:
    HMHomeManagerDelegate {

    func homeManagerDidUpdateHomes(
        _ manager: HMHomeManager
    ) {

        home =
            manager.primaryHome
    }
}


// ============================================================
// MARK: - Voice → Home Pipeline
// ============================================================

@MainActor
final class AppleHomeVoiceSystem:
    ObservableObject {

    let speech =
        HomeSpeechEngine()

    let home =
        AppleHomeController()

    private let parser =
        HomeCommandParser()


    @Published
    private(set) var lastIntent:
        HomeVoiceIntent?


    func process(
        transcript: String
    ) async {

        let intent =
            parser.parse(
                transcript
            )

        lastIntent =
            intent

        await execute(
            intent
        )
    }


    private func execute(
        _ intent: HomeVoiceIntent
    ) async {

        guard
            let accessoryName =
                intent.accessoryName
        else {
            return
        }

        guard
            let accessory =
                home.findAccessory(
                    named: accessoryName
                )
        else {
            return
        }


        do {

            switch intent.action {

            case .turnOn:

                try await home.turnOn(
                    accessory: accessory
                )


            case .turnOff:

                try await home.turnOff(
                    accessory: accessory
                )


            case .setBrightness:

                guard
                    let value =
                        intent.value
                else {
                    return
                }

                try await home
                    .setBrightness(
                        accessory: accessory,
                        percentage: value
                    )


            default:

                break
            }

        } catch {

            print(
                "Home command failed:",
                error.localizedDescription
            )
        }
    }
}
```

### Then the user experience becomes

```text
"Hey Siri / Home"

        ↓

Microphone

        ↓

Speech Recognition

        ↓

"Turn the kitchen lights
 to 40 percent"

        ↓

Command Parser

        ↓

Intent:
    action = setBrightness
    room   = kitchen
    value  = 40

        ↓

HomeKit

        ↓

Kitchen Lights
```

For a serious **Apple Home voice system**, I'd add three important layers on top of this foundation:

1. **Semantic intent engine** — understands variations such as “make the kitchen a little brighter” rather than requiring exact phrases.
2. **Context engine** — knows the current room, time, active scene, who's speaking, and what devices are already operating.
3. **Swift + Julia intelligence layer** — Swift handles speech/audio/HomeKit in real time, while Julia can optimize multi-device decisions, energy usage, schedules, and complex household automation.

For example, the eventual command could be:

> “It's getting cold in here.”

Rather than merely matching the word *temperature*, the system could infer the relevant room, inspect the thermostat, occupancy and current heating state, then construct an appropriate HomeKit action—while requiring confirmation for higher-impact actions such as unlocking doors.

