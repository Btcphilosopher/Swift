```swift
import Foundation
import AVFoundation
import Accelerate

// MARK: - Volume Optimiser

/// Intelligent real-time audio optimisation for iOS.
///
/// Goals:
/// - Maintain consistent perceived loudness
/// - Prevent clipping
/// - Improve quiet sections
/// - Protect against excessive peaks
/// - Adapt to speaker/headphone output
/// - React to changing audio conditions
///
/// Important:
/// An ordinary iOS app cannot directly override the system hardware
/// volume level. This engine optimises the audio signal before output.

public final class VolumeOptimiser {

    // MARK: Configuration

    public struct Configuration {

        /// Target RMS level in dBFS.
        public var targetRMS: Float = -18.0

        /// Maximum permitted peak.
        public var peakLimit: Float = -1.0

        /// Maximum gain that can be automatically applied.
        public var maximumGainDB: Float = 12.0

        /// How quickly gain increases.
        public var attackTime: Float = 0.050

        /// How quickly gain decreases.
        public var releaseTime: Float = 0.250

        /// Compressor threshold.
        public var compressorThreshold: Float = -12.0

        /// Compressor ratio.
        public var compressorRatio: Float = 3.0

        /// Soft-knee width.
        public var kneeWidth: Float = 6.0

        /// Additional headroom.
        public var headroomDB: Float = 1.0

        /// Enable adaptive gain.
        public var adaptiveGain: Bool = true

        /// Enable peak limiting.
        public var limiterEnabled: Bool = true

        public init() {}
    }

    // MARK: Output Environment

    public enum OutputEnvironment {
        case speaker
        case headphones
        case bluetooth
        case airPlay
        case car
        case unknown
    }

    // MARK: State

    public struct State {

        public var rmsDB: Float = -60
        public var peakDB: Float = -60

        public var gainDB: Float = 0

        public var compressionDB: Float = 0

        public var limiting: Bool = false

        public var clippingRisk: Float = 0

        public var perceivedLoudness: Float = 0

        public var environment: OutputEnvironment = .unknown

        public init() {}
    }

    public var configuration: Configuration

    private(set) public var state = State()

    private var gain: Float = 1.0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    // MARK: Analysis

    /// Calculate RMS amplitude.
    public func rms(_ buffer: AVAudioPCMBuffer) -> Float {

        guard
            let channelData = buffer.floatChannelData
        else {
            return 0
        }

        let frameCount = Int(buffer.frameLength)

        guard frameCount > 0 else {
            return 0
        }

        var sum: Float = 0

        for frame in 0..<frameCount {

            let sample = channelData[0][frame]

            sum += sample * sample
        }

        return sqrt(sum / Float(frameCount))
    }

    /// Convert linear amplitude to dBFS.
    public func decibels(_ amplitude: Float) -> Float {

        guard amplitude > 0 else {
            return -120
        }

        return 20.0 * log10(amplitude)
    }

    /// Measure peak amplitude.
    public func peak(_ buffer: AVAudioPCMBuffer) -> Float {

        guard
            let channelData = buffer.floatChannelData
        else {
            return 0
        }

        let frames = Int(buffer.frameLength)

        var maximum: Float = 0

        for frame in 0..<frames {

            maximum = max(
                maximum,
                abs(channelData[0][frame])
            )
        }

        return maximum
    }

    // MARK: Gain

    private func requiredGainDB(
        currentRMSDB: Float
    ) -> Float {

        let error =
            configuration.targetRMS -
            currentRMSDB

        return min(
            max(error, -12),
            configuration.maximumGainDB
        )
    }

    // MARK: Compressor

    private func compressionGainDB(
        inputDB: Float
    ) -> Float {

        let threshold =
            configuration.compressorThreshold

        let ratio =
            configuration.compressorRatio

        guard inputDB > threshold else {
            return 0
        }

        let excess =
            inputDB - threshold

        let compressed =
            excess / ratio

        return compressed - excess
    }

    // MARK: Limiter

    private func limiterGain(
        peakDB: Float
    ) -> Float {

        guard configuration.limiterEnabled else {
            return 1.0
        }

        let limit =
            configuration.peakLimit

        guard peakDB > limit else {
            return 1.0
        }

        let reductionDB =
            limit - peakDB

        return pow(
            10,
            reductionDB / 20
        )
    }

    // MARK: Adaptive Processing

    /// Analyse a buffer and update optimiser state.
    public func analyse(
        _ buffer: AVAudioPCMBuffer
    ) -> State {

        let rmsValue = rms(buffer)
        let peakValue = peak(buffer)

        let rmsDB = decibels(rmsValue)
        let peakDB = decibels(peakValue)

        state.rmsDB = rmsDB
        state.peakDB = peakDB

        // Automatic gain.
        var requestedGainDB: Float = 0

        if configuration.adaptiveGain {

            requestedGainDB =
                requiredGainDB(
                    currentRMSDB: rmsDB
                )
        }

        // Compression.
        let compression =
            compressionGainDB(
                inputDB: peakDB
            )

        state.compressionDB = compression

        // Limiter.
        let limiter =
            limiterGain(
                peakDB: peakDB
            )

        state.limiting =
            limiter < 0.999

        // Total gain.
        let totalGainDB =
            requestedGainDB + compression

        let totalGain =
            pow(
                10,
                totalGainDB / 20
            ) * limiter

        gain = totalGain

        state.gainDB =
            20 * log10(max(gain, 0.000001))

        state.clippingRisk =
            clippingRisk(
                peakDB: peakDB
            )

        state.perceivedLoudness =
            perceivedLoudness(
                rmsDB: rmsDB
            )

        return state
    }

    // MARK: DSP Processing

    /// Process a mono buffer in-place.
    public func process(
        _ buffer: AVAudioPCMBuffer
    ) {

        guard
            let channels = buffer.floatChannelData
        else {
            return
        }

        let channelCount =
            Int(buffer.format.channelCount)

        let frames =
            Int(buffer.frameLength)

        guard frames > 0 else {
            return
        }

        _ = analyse(buffer)

        for channel in 0..<channelCount {

            let samples =
                channels[channel]

            for frame in 0..<frames {

                samples[frame] *= gain

                // Hard safety ceiling.
                samples[frame] =
                    max(
                        -1.0,
                        min(
                            1.0,
                            samples[frame]
                        )
                    )
            }
        }
    }

    // MARK: Clipping

    private func clippingRisk(
        peakDB: Float
    ) -> Float {

        if peakDB <= -12 {
            return 0
        }

        if peakDB >= 0 {
            return 1
        }

        return
            (peakDB + 12) / 12
    }

    // MARK: Perceived Loudness

    /// Approximation rather than a full LUFS implementation.
    private func perceivedLoudness(
        rmsDB: Float
    ) -> Float {

        let normalised =
            (rmsDB + 60) / 60

        return max(
            0,
            min(
                1,
                normalised
            )
        )
    }

    // MARK: Environment

    public func detectOutputEnvironment() -> OutputEnvironment {

        let route =
            AVAudioSession.sharedInstance()
                .currentRoute

        for output in route.outputs {

            switch output.portType {

            case .builtInSpeaker:
                return .speaker

            case .headphones,
                 .headsetMic:
                return .headphones

            case .bluetoothA2DP,
                 .bluetoothHFP,
                 .bluetoothLE:
                return .bluetooth

            case .airPlay:
                return .airPlay

            case .carAudio:
                return .car

            default:
                continue
            }
        }

        return .unknown
    }

    // MARK: Environment Profiles

    public func applyEnvironmentProfile() {

        let environment =
            detectOutputEnvironment()

        state.environment =
            environment

        switch environment {

        case .speaker:

            configuration.targetRMS = -17
            configuration.maximumGainDB = 10
            configuration.compressorRatio = 3.0

        case .headphones:

            configuration.targetRMS = -18
            configuration.maximumGainDB = 8
            configuration.compressorRatio = 2.5

        case .bluetooth:

            configuration.targetRMS = -16
            configuration.maximumGainDB = 8
            configuration.compressorRatio = 3.0

        case .airPlay:

            configuration.targetRMS = -18
            configuration.maximumGainDB = 6
            configuration.compressorRatio = 2.0

        case .car:

            configuration.targetRMS = -15
            configuration.maximumGainDB = 10
            configuration.compressorRatio = 3.0

        case .unknown:

            break
        }
    }
}


// MARK: - Smart Volume Controller

@MainActor
public final class SmartVolumeController {

    public let optimiser =
        VolumeOptimiser()

    private let audioEngine =
        AVAudioEngine()

    private var inputNode:
        AVAudioInputNode?

    public private(set) var running = false

    public init() {}

    public func configure() throws {

        let session =
            AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [
                .defaultToSpeaker,
                .allowBluetooth
            ]
        )

        try session.setActive(true)

        optimiser.applyEnvironmentProfile()
    }

    public func start() throws {

        guard !running else {
            return
        }

        try configure()

        let node =
            audioEngine.inputNode

        inputNode = node

        let format =
            node.outputFormat(
                forBus: 0
            )

        node.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format
        ) { [weak self] buffer, _ in

            guard let self else {
                return
            }

            self.optimiser.process(buffer)
        }

        audioEngine.prepare()

        try audioEngine.start()

        running = true
    }

    public func stop() {

        inputNode?.removeTap(
            onBus: 0
        )

        audioEngine.stop()

        running = false
    }
}


// MARK: - Volume Intelligence

public struct VolumeRecommendation {

    public let gainDB: Float
    public let clippingRisk: Float
    public let perceivedLoudness: Float
    public let limitingRequired: Bool
}


/// Higher-level recommendation engine.
///
/// This can later be driven by Julia models.
public final class VolumeIntelligence {

    public init() {}

    public func recommend(
        state: VolumeOptimiser.State
    ) -> VolumeRecommendation {

        return VolumeRecommendation(
            gainDB: state.gainDB,
            clippingRisk: state.clippingRisk,
            perceivedLoudness: state.perceivedLoudness,
            limitingRequired: state.limiting
        )
    }
}


// MARK: - Example

public func volumeOptimiserExample() {

    let controller =
        SmartVolumeController()

    do {

        try controller.start()

        print(
            "Smart Volume Optimiser running"
        )

        print(
            "Environment:",
            controller.optimiser.state.environment
        )

    } catch {

        print(
            "Audio engine error:",
            error
        )
    }
}
```


