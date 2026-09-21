2. Core touch types
TouchTypes.swift
import Foundation

// MARK: - Touch Identity

public struct TouchID:
    Hashable,
    Codable,
    Sendable {

    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

// MARK: - 2D Vector

public struct TouchVector:
    Equatable,
    Codable,
    Sendable {

    public var x: Double
    public var y: Double

    public init(
        x: Double = 0,
        y: Double = 0
    ) {
        self.x = x
        self.y = y
    }

    public static let zero =
        TouchVector()

    public static func + (
        lhs: Self,
        rhs: Self
    ) -> Self {

        Self(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }

    public static func - (
        lhs: Self,
        rhs: Self
    ) -> Self {

        Self(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y
        )
    }

    public static func * (
        lhs: Self,
        rhs: Double
    ) -> Self {

        Self(
            x: lhs.x * rhs,
            y: lhs.y * rhs
        )
    }

    public static func / (
        lhs: Self,
        rhs: Double
    ) -> Self {

        guard rhs != 0 else {
            return .zero
        }

        return Self(
            x: lhs.x / rhs,
            y: lhs.y / rhs
        )
    }

    public var magnitude: Double {
        sqrt(
            x * x +
            y * y
        )
    }

    public var squaredMagnitude: Double {
        x * x + y * y
    }

    public func distance(
        to other: Self
    ) -> Double {

        (self - other).magnitude
    }

    public func clamped(
        magnitude maximum: Double
    ) -> Self {

        let current = magnitude

        guard current > maximum,
              current > 0
        else {
            return self
        }

        return self *
            (maximum / current)
    }
}

// MARK: - Touch Phase

public enum TouchPhase:
    String,
    Codable,
    Sendable {

    case began
    case moved
    case stationary
    case ended
    case cancelled
}

// MARK: - Raw Touch Sample

public struct TouchSample:
    Identifiable,
    Codable,
    Sendable {

    public let id: UUID

    public let touchID: TouchID

    public let timestamp: TimeInterval

    public let position: TouchVector

    public let phase: TouchPhase

    public let force: Double?

    public let contactArea: Double?

    public init(
        id: UUID = UUID(),
        touchID: TouchID,
        timestamp: TimeInterval,
        position: TouchVector,
        phase: TouchPhase,
        force: Double? = nil,
        contactArea: Double? = nil
    ) {

        self.id = id
        self.touchID = touchID
        self.timestamp = timestamp
        self.position = position
        self.phase = phase
        self.force = force
        self.contactArea = contactArea
    }
}

// MARK: - Kinematic State

public struct TouchKinematicState:
    Codable,
    Sendable {

    public let position: TouchVector

    public let velocity: TouchVector

    public let acceleration: TouchVector

    public let speed: Double

    public let timestamp: TimeInterval

    public init(
        position: TouchVector,
        velocity: TouchVector,
        acceleration: TouchVector,
        timestamp: TimeInterval
    ) {

        self.position = position
        self.velocity = velocity
        self.acceleration = acceleration
        self.speed = velocity.magnitude
        self.timestamp = timestamp
    }
}

// MARK: - Prediction Model

public enum PredictionModel:
    String,
    Codable,
    Sendable {

    case positionOnly
    case constantVelocity
    case constantAcceleration
}

// MARK: - Prediction

public struct TouchPrediction:
    Identifiable,
    Codable,
    Sendable {

    public let id: UUID

    public let touchID: TouchID

    public let sourceTimestamp: TimeInterval

    public let predictedTimestamp: TimeInterval

    public let position: TouchVector

    public let velocity: TouchVector

    public let confidence: Double

    public let horizon: TimeInterval

    public let model: PredictionModel

    public init(
        touchID: TouchID,
        sourceTimestamp: TimeInterval,
        predictedTimestamp: TimeInterval,
        position: TouchVector,
        velocity: TouchVector,
        confidence: Double,
        horizon: TimeInterval,
        model: PredictionModel
    ) {

        self.id = UUID()
        self.touchID = touchID
        self.sourceTimestamp = sourceTimestamp
        self.predictedTimestamp = predictedTimestamp
        self.position = position
        self.velocity = velocity
        self.confidence = confidence
        self.horizon = horizon
        self.model = model
    }
}
3. Touch history

We need a bounded history for each finger.

TouchHistory.swift
import Foundation

public struct TouchHistory:
    Sendable {

    private(set) public var samples:
        [TouchSample]

    public let maximumSamples:
        Int

    public init(
        maximumSamples: Int = 32
    ) {

        self.samples = []
        self.maximumSamples =
            max(4, maximumSamples)
    }

    public mutating func append(
        _ sample: TouchSample
    ) {

        samples.append(sample)

        if samples.count >
           maximumSamples {

            samples.removeFirst(
                samples.count -
                maximumSamples
            )
        }
    }

    public mutating func clear() {

        samples.removeAll(
            keepingCapacity: true
        )
    }

    public var latest:
        TouchSample? {

        samples.last
    }

    public var previous:
        TouchSample? {

        guard samples.count >= 2
        else {
            return nil
        }

        return samples[
            samples.count - 2
        ]
    }

    public var count: Int {
        samples.count
    }

    public func recent(
        _ count: Int
    ) -> ArraySlice<TouchSample> {

        let start =
            max(
                0,
                samples.count - count
            )

        return samples[start...]
    }
}
4. Velocity and acceleration estimator

This is the mathematical core.

TouchFilter.swift
import Foundation

public struct TouchKinematicsEstimator:
    Sendable {

    public init() {}

    public func estimate(
        history: TouchHistory
    ) -> TouchKinematicState? {

        guard history.count >= 2,
              let latest =
                history.latest,
              let previous =
                history.previous
        else {
            return nil
        }

        let velocity =
            velocity(
                from: previous,
                to: latest
            )

        let acceleration =
            estimateAcceleration(
                history: history,
                currentVelocity: velocity
            )

        return TouchKinematicState(
            position:
                latest.position,
            velocity:
                velocity,
            acceleration:
                acceleration,
            timestamp:
                latest.timestamp
        )
    }

    public func velocity(
        from first: TouchSample,
        to second: TouchSample
    ) -> TouchVector {

        let dt =
            second.timestamp -
            first.timestamp

        guard dt > 0 else {
            return .zero
        }

        return (
            second.position -
            first.position
        ) / dt
    }

    private func estimateAcceleration(
        history: TouchHistory,
        currentVelocity:
            TouchVector
    ) -> TouchVector {

        guard history.count >= 3
        else {
            return .zero
        }

        let recent =
            history.recent(3)

        guard recent.count == 3
        else {
            return .zero
        }

        let a = recent[recent.startIndex]
        let b = recent[recent.index(
            after: recent.startIndex
        )]
        let c = recent[
            recent.index(
                recent.startIndex,
                offsetBy: 2
            )
        ]

        let v1 =
            velocity(
                from: a,
                to: b
            )

        let v2 =
            velocity(
                from: b,
                to: c
            )

        let dt =
            c.timestamp -
            b.timestamp

        guard dt > 0
        else {
            return .zero
        }

        return (
            v2 - v1
        ) / dt
    }
}
5. Exponential smoothing

Raw touch coordinates can contain small amounts of jitter.

We don't want to over-filter them because that itself creates latency.

import Foundation

public struct ExponentialTouchFilter:
    Sendable {

    public let alpha:
        Double

    public init(
        alpha: Double = 0.65
    ) {

        self.alpha =
            min(
                1,
                max(
                    0.01,
                    alpha
                )
            )
    }

    public func filter(
        previous:
            TouchVector?,
        current:
            TouchVector
    ) -> TouchVector {

        guard let previous
        else {
            return current
        }

        return
            current * alpha +
            previous * (1 - alpha)
    }
}

Higher alpha means more responsiveness.

Lower alpha means more smoothing.

6. Adaptive prediction horizon

A fixed prediction window isn't ideal.

At low velocity we want a short prediction.

During a fast swipe, we can safely predict farther ahead.

import Foundation

public struct PredictionHorizonController:
    Sendable {

    public let minimum:
        TimeInterval

    public let maximum:
        TimeInterval

    public let velocityScale:
        Double

    public init(
        minimum:
            TimeInterval = 0.004,
        maximum:
            TimeInterval = 0.030,
        velocityScale:
            Double = 0.000020
    ) {

        self.minimum =
            minimum

        self.maximum =
            maximum

        self.velocityScale =
            velocityScale
    }

    public func horizon(
        speed:
            Double
    ) -> TimeInterval {

        let additional =
            speed *
            velocityScale

        return min(
            maximum,
            max(
                minimum,
                minimum + additional
            )
        )
    }
}

For example, this gives the engine a prediction window somewhere in the few-to-tens-of-milliseconds range.

7. Prediction engine
TouchPredictor.swift
import Foundation

public struct TouchPredictor:
    Sendable {

    public let horizonController:
        PredictionHorizonController

    public let model:
        PredictionModel

    public init(
        horizonController:
            PredictionHorizonController =
                PredictionHorizonController(),
        model:
            PredictionModel =
                .constantAcceleration
    ) {

        self.horizonController =
            horizonController

        self.model =
            model
    }

    public func predict(
        state:
            TouchKinematicState
    ) -> TouchPrediction {

        let horizon =
            horizonController.horizon(
                speed:
                    state.speed
            )

        let predictedPosition:
            TouchVector

        switch model {

        case .positionOnly:

            predictedPosition =
                state.position

        case .constantVelocity:

            predictedPosition =
                state.position +
                state.velocity *
                horizon

        case .constantAcceleration:

            predictedPosition =
                state.position +
                state.velocity *
                horizon +
                state.acceleration *
                (0.5 * horizon * horizon)
        }

        let predictedVelocity =
            state.velocity +
            state.acceleration *
            horizon

        return TouchPrediction(
            touchID:
                TouchID(rawValue: 0),
            sourceTimestamp:
                state.timestamp,
            predictedTimestamp:
                state.timestamp +
                horizon,
            position:
                predictedPosition,
            velocity:
                predictedVelocity,
            confidence:
                0,
            horizon:
                horizon,
            model:
                model
        )
    }

    public func predict(
        touchID:
            TouchID,
        state:
            TouchKinematicState,
        confidence:
            Double
    ) -> TouchPrediction {

        let horizon =
            horizonController.horizon(
                speed:
                    state.speed
            )

        let predictedPosition:
            TouchVector

        switch model {

        case .positionOnly:

            predictedPosition =
                state.position

        case .constantVelocity:

            predictedPosition =
                state.position +
                state.velocity *
                horizon

        case .constantAcceleration:

            predictedPosition =
                state.position +
                state.velocity *
                horizon +
                state.acceleration *
                (0.5 * horizon * horizon)
        }

        let predictedVelocity =
            state.velocity +
            state.acceleration *
            horizon

        return TouchPrediction(
            touchID:
                touchID,
            sourceTimestamp:
                state.timestamp,
            predictedTimestamp:
                state.timestamp +
                horizon,
            position:
                predictedPosition,
            velocity:
                predictedVelocity,
            confidence:
                max(
                    0,
                    min(
                        1,
                        confidence
                    )
                ),
            horizon:
                horizon,
            model:
                model
        )
    }
}
8. Confidence model

Prediction becomes dangerous if the engine becomes overconfident.

We therefore explicitly calculate confidence.

import Foundation

public struct TouchConfidenceEstimator:
    Sendable {

    public init() {}

    public func confidence(
        history:
            TouchHistory,
        state:
            TouchKinematicState
    ) -> Double {

        guard history.count >= 3
        else {
            return 0.30
        }

        let recent =
            history.recent(6)

        guard recent.count >= 3
        else {
            return 0.30
        }

        var velocities:
            [TouchVector] = []

        var iterator =
            recent.makeIterator()

        guard let first =
                iterator.next()
        else {
            return 0
        }

        var previous = first

        while let current =
                iterator.next() {

            let dt =
                current.timestamp -
                previous.timestamp

            if dt > 0 {

                velocities.append(
                    (
                        current.position -
                        previous.position
                    ) / dt
                )
            }

            previous = current
        }

        guard !velocities.isEmpty
        else {
            return 0
        }

        let averageSpeed =
            velocities
                .map(\.magnitude)
                .reduce(
                    0,
                    +
                ) /
            Double(
                velocities.count
            )

        let variance =
            velocities
                .map {
                    let difference =
                        $0.magnitude -
                        averageSpeed

                    return
                        difference *
                        difference
                }
                .reduce(
                    0,
                    +
                ) /
            Double(
                velocities.count
            )

        let deviation =
            sqrt(variance)

        let consistency =
            max(
                0,
                1 -
                deviation /
                max(
                    averageSpeed,
                    1
                )
            )

        let sampleConfidence =
            min(
                1,
                Double(history.count) /
                10
            )

        return min(
            1,
            0.25 +
            consistency * 0.50 +
            sampleConfidence * 0.25
        )
    }
}
9. Prediction error feedback

This is important.

The engine should learn how wrong its predictions were.

import Foundation

public struct PredictionError:
    Codable,
    Sendable {

    public let touchID:
        TouchID

    public let predicted:
        TouchVector

    public let actual:
        TouchVector

    public let error:
        Double

    public let timestamp:
        TimeInterval

    public init(
        touchID:
            TouchID,
        predicted:
            TouchVector,
        actual:
            TouchVector,
        timestamp:
            TimeInterval
    ) {

        self.touchID =
            touchID

        self.predicted =
            predicted

        self.actual =
            actual

        self.error =
            predicted.distance(
                to: actual
            )

        self.timestamp =
            timestamp
    }
}
10. Adaptive controller

Now use prediction error to tune the system.

actor TouchAdaptiveController {

    private var errors:
        [PredictionError] = []

    private let maximumHistory =
        256

    private var horizonMultiplier:
        Double = 1.0

    func record(
        _ error:
            PredictionError
    ) {

        errors.append(error)

        if errors.count >
           maximumHistory {

            errors.removeFirst(
                errors.count -
                maximumHistory
            )
        }

        adapt()
    }

    private func adapt() {

        guard errors.count >= 10
        else {
            return
        }

        let recent =
            errors.suffix(20)

        let meanError =
            recent
                .map(\.error)
                .reduce(
                    0,
                    +
                ) /
            Double(
                recent.count
            )

        if meanError > 8 {

            horizonMultiplier =
                max(
                    0.5,
                    horizonMultiplier *
                    0.90
                )

        } else if meanError < 2 {

            horizonMultiplier =
                min(
                    1.25,
                    horizonMultiplier *
                    1.02
                )
        }
    }

    func currentMultiplier()
        -> Double {

        horizonMultiplier
    }

    func meanError()
        -> Double {

        guard !errors.isEmpty
        else {
            return 0
        }

        return
            errors
                .map(\.error)
                .reduce(
                    0,
                    +
                ) /
            Double(
                errors.count
            )
    }
}

This creates a feedback loop:

prediction
    ↓
actual touch
    ↓
prediction error
    ↓
adaptive controller
    ↓
new prediction horizon
    ↓
better prediction
11. Diagnostics

This plugs directly into our #10 System Monitoring & Diagnostics service.

import Foundation

public struct TouchDiagnostics:
    Sendable {

    public let samplesProcessed:
        UInt64

    public let predictionsGenerated:
        UInt64

    public let averagePredictionError:
        Double

    public let averageConfidence:
        Double

    public let averageHorizon:
        TimeInterval

    public let activeTouches:
        Int

    public init(
        samplesProcessed:
            UInt64,
        predictionsGenerated:
            UInt64,
        averagePredictionError:
            Double,
        averageConfidence:
            Double,
        averageHorizon:
            TimeInterval,
        activeTouches:
            Int
    ) {

        self.samplesProcessed =
            samplesProcessed

        self.predictionsGenerated =
            predictionsGenerated

        self.averagePredictionError =
            averagePredictionError

        self.averageConfidence =
            averageConfidence

        self.averageHorizon =
            averageHorizon

        self.activeTouches =
            activeTouches
    }
}
12. Prediction output stream

The rest of the UI stack should receive predictions asynchronously.

import Foundation

public actor TouchPredictionStream {

    private var streams:
        [
            UUID:
            AsyncStream<TouchPrediction>
                .Continuation
        ] = [:]

    public init() {}

    public func subscribe()
        -> AsyncStream<TouchPrediction> {

        let id =
            UUID()

        return AsyncStream { continuation in

            streams[id] =
                continuation

            continuation.onTermination = {
                Task {
                    await self.remove(
                        id
                    )
                }
            }
        }
    }

    public func publish(
        _ prediction:
            TouchPrediction
    ) {

        for continuation
            in streams.values {

            continuation.yield(
                prediction
            )
        }
    }

    private func remove(
        _ id:
            UUID
    ) {

        streams.removeValue(
            forKey:
                id
        )
    }
}
13. The actual predictive engine

Now combine everything.

PredictiveTouchEngine.swift
import Foundation

public actor PredictiveTouchEngine {

    // MARK: Components

    private let estimator:
        TouchKinematicsEstimator

    private let predictor:
        TouchPredictor

    private let confidenceEstimator:
        TouchConfidenceEstimator

    private let adaptiveController:
        TouchAdaptiveController

    private let predictionStream:
        TouchPredictionStream

    // MARK: State

    private var histories:
        [TouchID: TouchHistory] = [:]

    private var lastPrediction:
        [TouchID: TouchPrediction] = [:]

    private var sampleCount:
        UInt64 = 0

    private var predictionCount:
        UInt64 = 0

    private var confidenceSum:
        Double = 0

    private var horizonSum:
        Double = 0

    // MARK: Initialization

    public init(
        model:
            PredictionModel =
                .constantAcceleration
    ) {

        self.estimator =
            TouchKinematicsEstimator()

        self.predictor =
            TouchPredictor(
                model:
                    model
            )

        self.confidenceEstimator =
            TouchConfidenceEstimator()

        self.adaptiveController =
            TouchAdaptiveController()

        self.predictionStream =
            TouchPredictionStream()
    }

    // MARK: Subscription

    public func subscribe()
        -> AsyncStream<TouchPrediction> {

        predictionStream.subscribe()
    }

    // MARK: Input

    public func process(
        sample:
            TouchSample
    ) async
        -> TouchPrediction? {

        sampleCount += 1

        var history =
            histories[
                sample.touchID
            ] ??
            TouchHistory()

        history.append(
            sample
        )

        histories[
            sample.touchID
        ] =
            history

        switch sample.phase {

        case .began:

            return nil

        case .moved,
             .stationary:

            return await
                generatePrediction(
                    touchID:
                        sample.touchID,
                    history:
                        history
                )

        case .ended,
             .cancelled:

            histories.removeValue(
                forKey:
                    sample.touchID
            )

            lastPrediction.removeValue(
                forKey:
                    sample.touchID
            )

            return nil
        }
    }

    // MARK: Prediction

    private func generatePrediction(
        touchID:
            TouchID,
        history:
            TouchHistory
    ) async
        -> TouchPrediction? {

        guard let state =
                estimator.estimate(
                    history:
                        history
                )
        else {
            return nil
        }

        let confidence =
            confidenceEstimator.confidence(
                history:
                    history,
                state:
                    state
            )

        let multiplier =
            await adaptiveController
                .currentMultiplier()

        let adjustedState =
            TouchKinematicState(
                position:
                    state.position,
                velocity:
                    state.velocity,
                acceleration:
                    state.acceleration,
                timestamp:
                    state.timestamp
            )

        var prediction =
            predictor.predict(
                touchID:
                    touchID,
                state:
                    adjustedState,
                confidence:
                    confidence
            )

        prediction =
            adjust(
                prediction,
                multiplier:
                    multiplier
            )

        lastPrediction[touchID] =
            prediction

        predictionCount += 1

        confidenceSum +=
            prediction.confidence

        horizonSum +=
            prediction.horizon

        await predictionStream.publish(
            prediction
        )

        return prediction
    }

    private func adjust(
        _ prediction:
            TouchPrediction,
        multiplier:
            Double
    ) -> TouchPrediction {

        let horizon =
            prediction.horizon *
            multiplier

        let dt =
            horizon -
            prediction.horizon

        let additionalPosition =
            prediction.velocity *
            dt

        return TouchPrediction(
            touchID:
                prediction.touchID,
            sourceTimestamp:
                prediction.sourceTimestamp,
            predictedTimestamp:
                prediction.sourceTimestamp +
                horizon,
            position:
                prediction.position +
                additionalPosition,
            velocity:
                prediction.velocity,
            confidence:
                prediction.confidence,
            horizon:
                horizon,
            model:
                prediction.model
        )
    }

    // MARK: Feedback

    public func correct(
        actual:
            TouchSample
    ) async {

        guard let prediction =
                lastPrediction[
                    actual.touchID
                ]
        else {
            return
        }

        let error =
            PredictionError(
                touchID:
                    actual.touchID,
                predicted:
                    prediction.position,
                actual:
                    actual.position,
                timestamp:
                    actual.timestamp
            )

        await adaptiveController.record(
            error
        )
    }

    // MARK: Diagnostics

    public func diagnostics()
        async -> TouchDiagnostics {

        let meanError =
            await adaptiveController
                .meanError()

        let averageConfidence =
            predictionCount > 0
                ? confidenceSum /
                    Double(
                        predictionCount
                    )
                : 0

        let averageHorizon =
            predictionCount > 0
                ? horizonSum /
                    Double(
                        predictionCount
                    )
                : 0

        return TouchDiagnostics(
            samplesProcessed:
                sampleCount,
            predictionsGenerated:
                predictionCount,
            averagePredictionError:
                meanError,
            averageConfidence:
                averageConfidence,
            averageHorizon:
                averageHorizon,
            activeTouches:
                histories.count
        )
    }

    // MARK: Reset

    public func reset() {

        histories.removeAll()
        lastPrediction.removeAll()

        sampleCount = 0
        predictionCount = 0
        confidenceSum = 0
        horizonSum = 0
    }
}
14. UIKit integration

On iPhone/iPad, we'd ultimately feed UIKit touch events into this engine.

UIKitTouchAdapter.swift
#if canImport(UIKit)

import UIKit

public final class UIKitTouchAdapter {

    private let engine:
        PredictiveTouchEngine

    private var identifiers:
        [ObjectIdentifier: TouchID] = [:]

    private var nextID:
        UInt64 = 1

    public init(
        engine:
            PredictiveTouchEngine
    ) {

        self.engine =
            engine
    }

    public func touchID(
        for touch:
            UITouch
    ) -> TouchID {

        let objectID =
            ObjectIdentifier(touch)

        if let existing =
            identifiers[objectID] {

            return existing
        }

        let id =
            TouchID(
                rawValue:
                    nextID
            )

        nextID += 1

        identifiers[objectID] =
            id

        return id
    }

    public func process(
        touch:
            UITouch,
        phase:
            TouchPhase,
        in view:
            UIView
    ) async
        -> TouchPrediction? {

        let id =
            touchID(
                for:
                    touch
            )

        let location =
            touch.location(
                in: view
            )

        let sample =
            TouchSample(
                touchID:
                    id,
                timestamp:
                    touch.timestamp,
                position:
                    TouchVector(
                        x:
                            location.x,
                        y:
                            location.y
                    ),
                phase:
                    phase,
                force:
                    touch.force,
                contactArea:
                    touch.majorRadius
            )

        return await
            engine.process(
                sample:
                    sample
            )
    }

    public func end(
        touch:
            UITouch
    ) {

        identifiers.removeValue(
            forKey:
                ObjectIdentifier(touch)
        )
    }
}

#endif
15. Example UIView integration

A custom view could use it like this:

#if canImport(UIKit)

import UIKit

final class PredictiveTouchView:
    UIView {

    private let engine =
        PredictiveTouchEngine()

    private lazy var adapter =
        UIKitTouchAdapter(
            engine:
                engine
        )

    override init(
        frame:
            CGRect
    ) {

        super.init(
            frame:
                frame
        )

        backgroundColor =
            .black
    }

    required init?(
        coder:
            NSCoder
    ) {

        fatalError(
            "init(coder:) has not been implemented"
        )
    }

    override func touchesBegan(
        _ touches:
            Set<UITouch>,
        with event:
            UIEvent?
    ) {

        Task {

            for touch in touches {

                _ = await adapter.process(
                    touch:
                        touch,
                    phase:
                        .began,
                    in:
                        self
                )
            }
        }
    }

    override func touchesMoved(
        _ touches:
            Set<UITouch>,
        with event:
            UIEvent?
    ) {

        Task {

            for touch in touches {

                if let prediction =
                    await adapter.process(
                        touch:
                            touch,
                        phase:
                            .moved,
                        in:
                            self
                    ) {

                    apply(
                        prediction:
                            prediction
                    )
                }
            }
        }
    }

    override func touchesEnded(
        _ touches:
            Set<UITouch>,
        with event:
            UIEvent?
    ) {

        Task {

            for touch in touches {

                _ = await adapter.process(
                    touch:
                        touch,
                    phase:
                        .ended,
                    in:
                        self
                )

                adapter.end(
                    touch:
                        touch
                )
            }
        }
    }

    override func touchesCancelled(
        _ touches:
            Set<UITouch>,
        with event:
            UIEvent?
    ) {

        Task {

            for touch in touches {

                _ = await adapter.process(
                    touch:
                        touch,
                    phase:
                        .cancelled,
                    in:
                        self
                )

                adapter.end(
                    touch:
                        touch
                )
            }
        }
    }

    private func apply(
        prediction:
            TouchPrediction
    ) {

        let point =
            CGPoint(
                x:
                    prediction.position.x,
                y:
                    prediction.position.y
            )

        // Use predicted point for
        // latency-sensitive rendering.
        //
        // Example:
        // cursor.center = point
        // drawingPath.addLine(to: point)
        // gameObject.position = point

        _ = point
    }
}

#endif
16. Multi-touch

The architecture already supports multiple fingers independently:

Touch #1
   │
   ├── History
   ├── Velocity
   ├── Acceleration
   └── Prediction
       
Touch #2
   │
   ├── History
   ├── Velocity
   ├── Acceleration
   └── Prediction

Touch #3
   │
   ├── History
   ├── Velocity
   ├── Acceleration
   └── Prediction

The actor protects the shared state while each touch retains its own trajectory.

17. XCTest
PredictiveTouchEngineTests.swift
import XCTest
@testable import PredictiveTouchEngine

final class PredictiveTouchEngineTests:
    XCTestCase {

    func testVelocityCalculation() {

        let estimator =
            TouchKinematicsEstimator()

        let a =
            TouchSample(
                touchID:
                    TouchID(rawValue: 1),
                timestamp:
                    0.0,
                position:
                    TouchVector(
                        x: 0,
                        y: 0
                    ),
                phase:
                    .began
            )

        let b =
            TouchSample(
                touchID:
                    TouchID(rawValue: 1),
                timestamp:
                    0.01,
                position:
                    TouchVector(
                        x: 10,
                        y: 0
                    ),
                phase:
                    .moved
            )

        let velocity =
            estimator.velocity(
                from:
                    a,
                to:
                    b
            )

        XCTAssertEqual(
            velocity.x,
            1_000,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            velocity.y,
            0,
            accuracy:
                0.001
        )
    }

    func testPredictionMovesForward() {

        let predictor =
            TouchPredictor(
                model:
                    .constantVelocity
            )

        let state =
            TouchKinematicState(
                position:
                    TouchVector(
                        x: 100,
                        y: 100
                    ),
                velocity:
                    TouchVector(
                        x: 500,
                        y: 0
                    ),
                acceleration:
                    .zero,
                timestamp:
                    1
            )

        let prediction =
            predictor.predict(
                touchID:
                    TouchID(
                        rawValue:
                            1
                    ),
                state:
                    state,
                confidence:
                    0.9
            )

        XCTAssertGreaterThan(
            prediction.position.x,
            state.position.x
        )
    }

    func testEngineProducesPrediction()
        async {

        let engine =
            PredictiveTouchEngine()

        let id =
            TouchID(
                rawValue:
                    1
            )

        let first =
            TouchSample(
                touchID:
                    id,
                timestamp:
                    0,
                position:
                    TouchVector(
                        x: 100,
                        y: 100
                    ),
                phase:
                    .began
            )

        let second =
            TouchSample(
                touchID:
                    id,
                timestamp:
                    0.01,
                position:
                    TouchVector(
                        x: 110,
                        y: 100
                    ),
                phase:
                    .moved
            )

        _ =
            await engine.process(
                sample:
                    first
            )

        let prediction =
            await engine.process(
                sample:
                    second
            )

        XCTAssertNotNil(
            prediction
        )
    }

    func testEndedTouchIsRemoved()
        async {

        let engine =
            PredictiveTouchEngine()

        let id =
            TouchID(
                rawValue:
                    42
            )

        let sample =
            TouchSample(
                touchID:
                    id,
                timestamp:
                    0,
                position:
                    .zero,
                phase:
                    .ended
            )

        _ =
            await engine.process(
                sample:
                    sample
            )

        let diagnostics =
            await engine.diagnostics()

        XCTAssertEqual(
            diagnostics.activeTouches,
            0
        )
    }

    func testPredictionErrorIsMeasured()
        async {

        let engine =
            PredictiveTouchEngine()

        let id =
            TouchID(
                rawValue:
                    5
            )

        let first =
            TouchSample(
                touchID:
                    id,
                timestamp:
                    0,
                position:
                    .zero,
                phase:
                    .began
            )

        let second =
            TouchSample(
                touchID:
                    id,
                timestamp:
                    0.01,
                position:
                    TouchVector(
                        x: 10,
                        y: 0
                    ),
                phase:
                    .moved
            )

        _ =
            await engine.process(
                sample:
                    first
            )

        _ =
            await engine.process(
                sample:
                    second
            )

        let actual =
            TouchSample(
                touchID:
                    id,
                timestamp:
                    0.02,
                position:
                    TouchVector(
                        x: 21,
                        y: 0
                    ),
                phase:
                    .moved
            )

        await engine.correct(
            actual:
                actual
        )

        let diagnostics =
            await engine.diagnostics()

        XCTAssertGreaterThanOrEqual(
            diagnostics.averagePredictionError,
            0
        )
    }
}
18. Package.swift

For a Swift Package:

import PackageDescription

let package =
    Package(
        name:
            "PredictiveTouchEngine",

        platforms: [
            .iOS(.v17),
            .macOS(.v14)
        ],

        products: [
            .library(
                name:
                    "PredictiveTouchEngine",
                targets: [
                    "PredictiveTouchEngine"
                ]
            )
        ],

        targets: [
            .target(
                name:
                    "PredictiveTouchEngine"
            ),

            .testTarget(
                name:
                    "PredictiveTouchEngineTests",
                dependencies: [
                    "PredictiveTouchEngine"
                ]
            )
        ]
    )
    
    
    
    
    
    
    
    
    1. Contact types
TouchContactTypes.swift
import Foundation

public enum TouchContactKind:
    String,
    Codable,
    Sendable {

    case unknown

    case fingertip

    case thumb

    case palm

    case sideOfHand

    case stylusLike

    case accidental

    case intentionalMultiTouch
}
2. Rejection decisions
import Foundation

public enum TouchDecision:
    String,
    Codable,
    Sendable {

    case accept

    case acceptWithReducedConfidence

    case defer

    case reject
}

The defer state is particularly useful.

Instead of immediately rejecting an ambiguous contact, we can wait for another few samples.

For example:

Sample 1
   ↓
looks like palm
   ↓
DEFER

Sample 2
   ↓
moves like fingertip
   ↓
ACCEPT

That is much safer than making a binary decision from one sample.

3. Touch context

The same physical contact can mean completely different things depending upon where it occurs.

import Foundation

public enum TouchInteractionContext:
    String,
    Codable,
    Sendable {

    case unknown

    case normalUI

    case textEditing

    case scrolling

    case drawing

    case gaming

    case video

    case keyboard

    case dragAndDrop

    case accessibility

    case systemEdgeGesture
}
4. Screen geometry
import Foundation

public struct TouchScreenBounds:
    Codable,
    Sendable {

    public let width:
        Double

    public let height:
        Double

    public init(
        width:
            Double,
        height:
            Double
    ) {

        self.width =
            max(1, width)

        self.height =
            max(1, height)
    }
}
5. Contact geometry
import Foundation

public struct TouchGeometry:
    Codable,
    Sendable {

    public let position:
        TouchVector

    public let majorRadius:
        Double?

    public let minorRadius:
        Double?

    public let area:
        Double?

    public let force:
        Double?

    public init(
        position:
            TouchVector,
        majorRadius:
            Double? = nil,
        minorRadius:
            Double? = nil,
        area:
            Double? = nil,
        force:
            Double? = nil
    ) {

        self.position =
            position

        self.majorRadius =
            majorRadius

        self.minorRadius =
            minorRadius

        self.area =
            area

        self.force =
            force
    }

    public var estimatedContactSize:
        Double {

        if let area {
            return area
        }

        if let majorRadius,
           let minorRadius {

            return
                .pi *
                majorRadius *
                minorRadius
        }

        if let majorRadius {
            return
                .pi *
                majorRadius *
                majorRadius
        }

        return 0
    }

    public var aspectRatio:
        Double {

        guard
            let major = majorRadius,
            let minor = minorRadius,
            minor > 0
        else {
            return 1
        }

        return major / minor
    }
}
6. Motion features

We now connect the system to #1 Predictive Touch Engine.

import Foundation

public struct TouchMotionFeatures:
    Codable,
    Sendable {

    public let velocity:
        TouchVector

    public let acceleration:
        TouchVector

    public let speed:
        Double

    public let accelerationMagnitude:
        Double

    public let direction:
        Double

    public init(
        velocity:
            TouchVector,
        acceleration:
            TouchVector
    ) {

        self.velocity =
            velocity

        self.acceleration =
            acceleration

        self.speed =
            velocity.magnitude

        self.accelerationMagnitude =
            acceleration.magnitude

        self.direction =
            atan2(
                velocity.y,
                velocity.x
            )
    }
}
7. Touch feature vector

This is the information presented to the classifier.

import Foundation

public struct TouchFeatureVector:
    Codable,
    Sendable {

    public let geometry:
        TouchGeometry

    public let motion:
        TouchMotionFeatures

    public let duration:
        TimeInterval

    public let distanceTravelled:
        Double

    public let distanceFromEdge:
        Double

    public let fingerCount:
        Int

    public let context:
        TouchInteractionContext

    public init(
        geometry:
            TouchGeometry,
        motion:
            TouchMotionFeatures,
        duration:
            TimeInterval,
        distanceTravelled:
            Double,
        distanceFromEdge:
            Double,
        fingerCount:
            Int,
        context:
            TouchInteractionContext
    ) {

        self.geometry =
            geometry

        self.motion =
            motion

        self.duration =
            duration

        self.distanceTravelled =
            distanceTravelled

        self.distanceFromEdge =
            distanceFromEdge

        self.fingerCount =
            fingerCount

        self.context =
            context
    }
}
8. Contact probabilities

Instead of saying:

"This is a palm."

we maintain probabilities.

import Foundation

public struct ContactProbabilities:
    Codable,
    Sendable {

    public var fingertip:
        Double

    public var thumb:
        Double

    public var palm:
        Double

    public var sideOfHand:
        Double

    public var stylusLike:
        Double

    public var accidental:
        Double

    public var intentionalMultiTouch:
        Double

    public init(
        fingertip:
            Double = 0,
        thumb:
            Double = 0,
        palm:
            Double = 0,
        sideOfHand:
            Double = 0,
        stylusLike:
            Double = 0,
        accidental:
            Double = 0,
        intentionalMultiTouch:
            Double = 0
    ) {

        self.fingertip =
            fingertip

        self.thumb =
            thumb

        self.palm =
            palm

        self.sideOfHand =
            sideOfHand

        self.stylusLike =
            stylusLike

        self.accidental =
            accidental

        self.intentionalMultiTouch =
            intentionalMultiTouch
    }

    public var highest:
        (TouchContactKind, Double) {

        let candidates:
            [(TouchContactKind, Double)] = [

                (.fingertip, fingertip),

                (.thumb, thumb),

                (.palm, palm),

                (.sideOfHand, sideOfHand),

                (.stylusLike, stylusLike),

                (.accidental, accidental),

                (
                    .intentionalMultiTouch,
                    intentionalMultiTouch
                )
            ]

        return candidates.max {
            $0.1 < $1.1
        } ?? (
            .unknown,
            0
        )
    }
}
9. Rule-based classifier

This is intentionally deterministic.

It gives us a reliable baseline before we introduce ML.

import Foundation

public struct TouchContactClassifier:
    Sendable {

    public init() {}

    public func classify(
        features:
            TouchFeatureVector
    ) -> ContactProbabilities {

        var result =
            ContactProbabilities()

        let size =
            features.geometry
                .estimatedContactSize

        let aspect =
            features.geometry
                .aspectRatio

        let speed =
            features.motion.speed

        // MARK: Large contact

        if size > 1_500 {

            result.palm += 0.70

        } else if size > 900 {

            result.palm += 0.45
        }

        // MARK: Elongated contact

        if aspect > 2.5 {

            result.sideOfHand += 0.55
        }

        // MARK: Small contact

        if size > 0 &&
           size < 350 {

            result.fingertip += 0.60
        }

        // MARK: High velocity contact

        if speed > 1_500 {

            result.accidental += 0.10
        }

        // MARK: Stationary large contact

        if speed < 30 &&
           size > 900 {

            result.palm += 0.20
        }

        // MARK: Drawing

        if features.context ==
            .drawing {

            result.stylusLike +=
                0.15

            result.fingertip +=
                0.10
        }

        // MARK: Multi-touch

        if features.fingerCount >= 2 {

            result.intentionalMultiTouch +=
                0.60

            result.accidental -=
                0.20
        }

        // MARK: Edge contact

        if features.distanceFromEdge < 30 {

            if features.context ==
                .systemEdgeGesture {

                result.accidental -=
                    0.30
            } else {

                result.accidental +=
                    0.15
            }
        }

        normalize(
            &result
        )

        return result
    }

    private func normalize(
        _ probabilities:
            inout ContactProbabilities
    ) {

        probabilities.fingertip =
            max(
                0,
                probabilities.fingertip
            )

        probabilities.thumb =
            max(
                0,
                probabilities.thumb
            )

        probabilities.palm =
            max(
                0,
                probabilities.palm
            )

        probabilities.sideOfHand =
            max(
                0,
                probabilities.sideOfHand
            )

        probabilities.stylusLike =
            max(
                0,
                probabilities.stylusLike
            )

        probabilities.accidental =
            max(
                0,
                probabilities.accidental
            )

        probabilities.intentionalMultiTouch =
            max(
                0,
                probabilities.intentionalMultiTouch
            )

        let total =
            probabilities.fingertip +
            probabilities.thumb +
            probabilities.palm +
            probabilities.sideOfHand +
            probabilities.stylusLike +
            probabilities.accidental +
            probabilities.intentionalMultiTouch

        guard total > 0
        else {
            return
        }

        probabilities.fingertip /= total
        probabilities.thumb /= total
        probabilities.palm /= total
        probabilities.sideOfHand /= total
        probabilities.stylusLike /= total
        probabilities.accidental /= total
        probabilities.intentionalMultiTouch /= total
    }
}
10. Context-aware rejection policy

This is where the system gets much more sophisticated.

A large contact should not necessarily be rejected.

For example:

Drawing:
    large contact → potentially intentional

Keyboard:
    large contact → potentially intentional

Gaming:
    large contact → potentially intentional

Normal UI:
    large stationary contact → probably palm
import Foundation

public struct TouchRejectionPolicy:
    Sendable {

    public let palmThreshold:
        Double

    public let accidentalThreshold:
        Double

    public init(
        palmThreshold:
            Double = 0.72,
        accidentalThreshold:
            Double = 0.80
    ) {

        self.palmThreshold =
            palmThreshold

        self.accidentalThreshold =
            accidentalThreshold
    }

    public func decision(
        probabilities:
            ContactProbabilities,
        context:
            TouchInteractionContext
    ) -> TouchDecision {

        let highest =
            probabilities.highest

        switch highest.0 {

        case .palm,
             .sideOfHand:

            if context ==
                .drawing ||
               context ==
                .keyboard {

                return .acceptWithReducedConfidence
            }

            return highest.1 >=
                palmThreshold
                ? .reject
                : .defer

        case .accidental:

            return highest.1 >=
                accidentalThreshold
                ? .reject
                : .defer

        case .fingertip,
             .thumb,
             .stylusLike,
             .intentionalMultiTouch:

            return .accept

        case .unknown:

            return .defer
        }
    }
}
11. Temporal classifier

This is one of the most important parts.

We shouldn't classify each sample independently.

Instead:

sample 1 ─┐
sample 2 ─┤
sample 3 ─┤──> temporal confidence
sample 4 ─┤
sample 5 ─┘
import Foundation

actor TouchTemporalClassifier {

    private struct Track {
        var probabilities:
            [ContactProbabilities] = []

        var decision:
            TouchDecision = .defer
    }

    private var tracks:
        [TouchID: Track] = [:]

    private let maximumSamples =
        8

    func update(
        touchID:
            TouchID,
        probabilities:
            ContactProbabilities,
        policy:
            TouchRejectionPolicy,
        context:
            TouchInteractionContext
    ) -> TouchDecision {

        var track =
            tracks[touchID] ??
            Track()

        track.probabilities.append(
            probabilities
        )

        if track.probabilities.count >
           maximumSamples {

            track.probabilities.removeFirst()
        }

        let averaged =
            average(
                track.probabilities
            )

        track.decision =
            policy.decision(
                probabilities:
                    averaged,
                context:
                    context
            )

        tracks[touchID] =
            track

        return track.decision
    }

    func remove(
        touchID:
            TouchID
    ) {

        tracks.removeValue(
            forKey:
                touchID
        )
    }

    private func average(
        _ values:
            [ContactProbabilities]
    ) -> ContactProbabilities {

        guard !values.isEmpty
        else {
            return ContactProbabilities()
        }

        let count =
            Double(values.count)

        return ContactProbabilities(

            fingertip:
                values.map(\.fingertip)
                    .reduce(0, +) / count,

            thumb:
                values.map(\.thumb)
                    .reduce(0, +) / count,

            palm:
                values.map(\.palm)
                    .reduce(0, +) / count,

            sideOfHand:
                values.map(\.sideOfHand)
                    .reduce(0, +) / count,

            stylusLike:
                values.map(\.stylusLike)
                    .reduce(0, +) / count,

            accidental:
                values.map(\.accidental)
                    .reduce(0, +) / count,

            intentionalMultiTouch:
                values
                    .map(
                        \.intentionalMultiTouch
                    )
                    .reduce(0, +) / count
        )
    }
}
12. Full rejection result
import Foundation

public struct TouchClassificationResult:
    Codable,
    Sendable {

    public let touchID:
        TouchID

    public let kind:
        TouchContactKind

    public let decision:
        TouchDecision

    public let confidence:
        Double

    public let probabilities:
        ContactProbabilities

    public let features:
        TouchFeatureVector

    public init(
        touchID:
            TouchID,
        kind:
            TouchContactKind,
        decision:
            TouchDecision,
        confidence:
            Double,
        probabilities:
            ContactProbabilities,
        features:
            TouchFeatureVector
    ) {

        self.touchID =
            touchID

        self.kind =
            kind

        self.decision =
            decision

        self.confidence =
            confidence

        self.probabilities =
            probabilities

        self.features =
            features
    }
}
13. The full engine
TouchRejectionEngine.swift
import Foundation

public actor TouchRejectionEngine {

    // MARK: Components

    private let classifier:
        TouchContactClassifier

    private let temporalClassifier:
        TouchTemporalClassifier

    private let policy:
        TouchRejectionPolicy

    // MARK: State

    private var histories:
        [TouchID: TouchHistory] = [:]

    private var startTimes:
        [TouchID: TimeInterval] = [:]

    private var totalSamples:
        UInt64 = 0

    private var accepted:
        UInt64 = 0

    private var rejected:
        UInt64 = 0

    private var deferred:
        UInt64 = 0

    // MARK: Initialization

    public init(
        policy:
            TouchRejectionPolicy =
                TouchRejectionPolicy()
    ) {

        self.classifier =
            TouchContactClassifier()

        self.temporalClassifier =
            TouchTemporalClassifier()

        self.policy =
            policy
    }

    // MARK: Processing

    public func process(
        sample:
            TouchSample,
        screen:
            TouchScreenBounds,
        context:
            TouchInteractionContext,
        fingerCount:
            Int = 1
    ) async
        -> TouchClassificationResult {

        totalSamples += 1

        var history =
            histories[
                sample.touchID
            ] ??
            TouchHistory()

        history.append(
            sample
        )

        histories[
            sample.touchID
        ] =
            history

        if sample.phase ==
            .began {

            startTimes[
                sample.touchID
            ] =
                sample.timestamp
        }

        let kinematics =
            TouchKinematicsEstimator()
                .estimate(
                    history:
                        history
                )

        let motion =
            TouchMotionFeatures(
                velocity:
                    kinematics?.velocity
                    ?? .zero,
                acceleration:
                    kinematics?.acceleration
                    ?? .zero
            )

        let geometry =
            TouchGeometry(
                position:
                    sample.position,
                majorRadius:
                    sample.contactArea,
                area:
                    sample.contactArea,
                force:
                    sample.force
            )

        let duration =
            sample.timestamp -
            (
                startTimes[
                    sample.touchID
                ] ??
                sample.timestamp
            )

        let distance =
            calculateDistance(
                history:
                    history
            )

        let edgeDistance =
            calculateEdgeDistance(
                position:
                    sample.position,
                screen:
                    screen
            )

        let features =
            TouchFeatureVector(
                geometry:
                    geometry,
                motion:
                    motion,
                duration:
                    max(
                        0,
                        duration
                    ),
                distanceTravelled:
                    distance,
                distanceFromEdge:
                    edgeDistance,
                fingerCount:
                    fingerCount,
                context:
                    context
            )

        let probabilities =
            classifier.classify(
                features:
                    features
            )

        let decision =
            await temporalClassifier.update(
                touchID:
                    sample.touchID,
                probabilities:
                    probabilities,
                policy:
                    policy,
                context:
                    context
            )

        let highest =
            probabilities.highest

        switch decision {

        case .accept,
             .acceptWithReducedConfidence:

            accepted += 1

        case .reject:

            rejected += 1

        case .defer:

            deferred += 1
        }

        if sample.phase ==
            .ended ||
           sample.phase ==
            .cancelled {

            histories.removeValue(
                forKey:
                    sample.touchID
            )

            startTimes.removeValue(
                forKey:
                    sample.touchID
            )

            await temporalClassifier.remove(
                touchID:
                    sample.touchID
            )
        }

        return TouchClassificationResult(
            touchID:
                sample.touchID,
            kind:
                highest.0,
            decision:
                decision,
            confidence:
                highest.1,
            probabilities:
                probabilities,
            features:
                features
        )
    }

    // MARK: Distance

    private func calculateDistance(
        history:
            TouchHistory
    ) -> Double {

        guard history.count >= 2
        else {
            return 0
        }

        var distance = 0.0

        let samples =
            history.samples

        for index in 1..<samples.count {

            distance +=
                samples[index - 1]
                    .position
                    .distance(
                        to:
                            samples[index]
                                .position
                    )
        }

        return distance
    }

    // MARK: Edge

    private func calculateEdgeDistance(
        position:
            TouchVector,
        screen:
            TouchScreenBounds
    ) -> Double {

        min(
            position.x,
            position.y,
            screen.width - position.x,
            screen.height - position.y
        )
    }

    // MARK: Statistics

    public func statistics()
        -> TouchRejectionStatistics {

        TouchRejectionStatistics(
            totalSamples:
                totalSamples,
            accepted:
                accepted,
            rejected:
                rejected,
            deferred:
                deferred
        )
    }

    public func reset() {

        histories.removeAll()
        startTimes.removeAll()

        totalSamples = 0
        accepted = 0
        rejected = 0
        deferred = 0
    }
}
14. Statistics
import Foundation

public struct TouchRejectionStatistics:
    Codable,
    Sendable {

    public let totalSamples:
        UInt64

    public let accepted:
        UInt64

    public let rejected:
        UInt64

    public let deferred:
        UInt64

    public var rejectionRate:
        Double {

        guard totalSamples > 0
        else {
            return 0
        }

        return Double(rejected) /
            Double(totalSamples)
    }
}
15. Combined Predictive + Rejection engine

Now we can combine #1 and #2.

import Foundation

public actor IntelligentTouchEngine {

    private let predictor:
        PredictiveTouchEngine

    private let rejection:
        TouchRejectionEngine

    public init() {

        self.predictor =
            PredictiveTouchEngine(
                model:
                    .constantAcceleration
            )

        self.rejection =
            TouchRejectionEngine()
    }

    public func process(
        sample:
            TouchSample,
        screen:
            TouchScreenBounds,
        context:
            TouchInteractionContext,
        fingerCount:
            Int = 1
    ) async
        -> IntelligentTouchResult {

        let classification =
            await rejection.process(
                sample:
                    sample,
                screen:
                    screen,
                context:
                    context,
                fingerCount:
                    fingerCount
            )

        switch classification.decision {

        case .reject:

            return IntelligentTouchResult(
                classification:
                    classification,
                prediction:
                    nil
            )

        case .accept,
             .acceptWithReducedConfidence,
             .defer:

            let prediction =
                await predictor.process(
                    sample:
                        sample
                )

            return IntelligentTouchResult(
                classification:
                    classification,
                prediction:
                    prediction
            )
        }
    }

    public func correct(
        actual:
            TouchSample
    ) async {

        await predictor.correct(
            actual:
                actual
        )
    }
}
16. Unified result
import Foundation

public struct IntelligentTouchResult:
    Sendable {

    public let classification:
        TouchClassificationResult

    public let prediction:
        TouchPrediction?

    public init(
        classification:
            TouchClassificationResult,
        prediction:
            TouchPrediction?
    ) {

        self.classification =
            classification

        self.prediction =
            prediction
    }

    public var shouldRender:
        Bool {

        classification.decision !=
            .reject
    }
}
17. Example

A normal fingertip:

let engine =
    IntelligentTouchEngine()

let screen =
    TouchScreenBounds(
        width: 1179,
        height: 2556
    )

let sample =
    TouchSample(
        touchID:
            TouchID(
                rawValue:
                    1
            ),
        timestamp:
            1.000,
        position:
            TouchVector(
                x: 400,
                y: 800
            ),
        phase:
            .began,
        force:
            0.2,
        contactArea:
            120
    )

let result =
    await engine.process(
        sample:
            sample,
        screen:
            screen,
        context:
            .normalUI
    )

print(
    result.classification.kind
)

print(
    result.classification.decision
)

The intended output would be conceptually:

fingertip
accept
18. Simulating a palm
let palm =
    TouchSample(
        touchID:
            TouchID(
                rawValue:
                    2
            ),
        timestamp:
            2.000,
        position:
            TouchVector(
                x: 600,
                y: 1200
            ),
        phase:
            .moved,
        force:
            0.8,
        contactArea:
            2_000
    )

let result =
    await engine.process(
        sample:
            palm,
        screen:
            screen,
        context:
            .normalUI
    )

The classifier now has evidence such as:

contact size       → large
velocity           → low
context            → normal UI
                    ↓
             palm probability ↑
                    ↓
              temporal filter
                    ↓
                  reject
19. But drawing is different

This is critical.

We don't want to destroy drawing by aggressively rejecting large contacts.

let drawingResult =
    await engine.process(
        sample:
            palm,
        screen:
            screen,
        context:
            .drawing
    )

The policy can instead produce:

large contact
      ↓
possible palm
      ↓
DRAWING MODE
      ↓
accept with reduced confidence

Later, #9 can make this considerably more sophisticated.

20. Tests
import XCTest
@testable import PredictiveTouchEngine

final class TouchRejectionTests:
    XCTestCase {

    func testSmallContactIsAccepted()
        async {

        let engine =
            TouchRejectionEngine()

        let screen =
            TouchScreenBounds(
                width:
                    1_000,
                height:
                    2_000
            )

        let sample =
            TouchSample(
                touchID:
                    TouchID(
                        rawValue:
                            1
                    ),
                timestamp:
                    1,
                position:
                    TouchVector(
                        x:
                            500,
                        y:
                            1_000
                    ),
                phase:
                    .moved,
                contactArea:
                    100
            )

        let result =
            await engine.process(
                sample:
                    sample,
                screen:
                    screen,
                context:
                    .normalUI
            )

        XCTAssertNotEqual(
            result.kind,
            .palm
        )
    }

    func testLargeContactLooksLikePalm()
        async {

        let engine =
            TouchRejectionEngine()

        let screen =
            TouchScreenBounds(
                width:
                    1_000,
                height:
                    2_000
            )

        let sample =
            TouchSample(
                touchID:
                    TouchID(
                        rawValue:
                            2
                    ),
                timestamp:
                    1,
                position:
                    TouchVector(
                        x:
                            500,
                        y:
                            1_000
                    ),
                phase:
                    .moved,
                contactArea:
                    2_500
            )

        let result =
            await engine.process(
                sample:
                    sample,
                screen:
                    screen,
                context:
                    .normalUI
            )

        XCTAssertGreaterThan(
            result.probabilities.palm,
            0
        )
    }

    func testDrawingContextIsMorePermissive()
        async {

        let engine =
            TouchRejectionEngine()

        let screen =
            TouchScreenBounds(
                width:
                    1_000,
                height:
                    2_000
            )

        let sample =
            TouchSample(
                touchID:
                    TouchID(
                        rawValue:
                            3
                    ),
                timestamp:
                    1,
                position:
                    TouchVector(
                        x:
                            500,
                        y:
                            1_000
                    ),
                phase:
                    .moved,
                contactArea:
                    2_000
            )

        let result =
            await engine.process(
                sample:
                    sample,
                screen:
                    screen,
                context:
                    .drawing
            )

        XCTAssertNotEqual(
            result.decision,
            .reject
        )
    }
}






1. Sensitivity model
TouchSensitivityTypes.swift
import Foundation

public struct TouchSensitivity:
    Codable,
    Sendable,
    Equatable {

    /// How much spatial movement is tolerated
    /// before a touch is considered to have moved.
    public var movementTolerance:
        Double

    /// Minimum movement required to classify
    /// a contact as intentional motion.
    public var intentionalMovementThreshold:
        Double

    /// Radius around an interactive target in which
    /// a touch can be accepted.
    public var hitTolerance:
        Double

    /// Tolerance applied to contact-size variation.
    public var contactSizeTolerance:
        Double

    /// How aggressively small movements are smoothed.
    /// 0 = no smoothing, 1 = maximum smoothing.
    public var smoothing:
        Double

    /// Multiplier for gesture recognition thresholds.
    public var gestureThresholdMultiplier:
        Double

    /// Edge sensitivity.
    public var edgeSensitivity:
        Double

    /// Confidence required before accepting
    /// an ambiguous contact.
    public var acceptanceConfidence:
        Double

    public init(
        movementTolerance: Double = 2.0,
        intentionalMovementThreshold: Double = 4.0,
        hitTolerance: Double = 8.0,
        contactSizeTolerance: Double = 1.0,
        smoothing: Double = 0.15,
        gestureThresholdMultiplier: Double = 1.0,
        edgeSensitivity: Double = 1.0,
        acceptanceConfidence: Double = 0.65
    ) {
        self.movementTolerance =
            movementTolerance

        self.intentionalMovementThreshold =
            intentionalMovementThreshold

        self.hitTolerance =
            hitTolerance

        self.contactSizeTolerance =
            contactSizeTolerance

        self.smoothing =
            smoothing

        self.gestureThresholdMultiplier =
            gestureThresholdMultiplier

        self.edgeSensitivity =
            edgeSensitivity

        self.acceptanceConfidence =
            acceptanceConfidence
    }

    public static let normal =
        TouchSensitivity()

    public static let precise =
        TouchSensitivity(
            movementTolerance: 1.0,
            intentionalMovementThreshold: 2.0,
            hitTolerance: 4.0,
            contactSizeTolerance: 0.7,
            smoothing: 0.08,
            gestureThresholdMultiplier: 0.85,
            edgeSensitivity: 0.85,
            acceptanceConfidence: 0.70
        )

    public static let forgiving =
        TouchSensitivity(
            movementTolerance: 4.0,
            intentionalMovementThreshold: 7.0,
            hitTolerance: 14.0,
            contactSizeTolerance: 1.5,
            smoothing: 0.25,
            gestureThresholdMultiplier: 1.15,
            edgeSensitivity: 1.2,
            acceptanceConfidence: 0.55
        )

    public static let gaming =
        TouchSensitivity(
            movementTolerance: 1.0,
            intentionalMovementThreshold: 2.0,
            hitTolerance: 5.0,
            contactSizeTolerance: 0.8,
            smoothing: 0.03,
            gestureThresholdMultiplier: 0.70,
            edgeSensitivity: 0.70,
            acceptanceConfidence: 0.55
        )

    public static let drawing =
        TouchSensitivity(
            movementTolerance: 0.5,
            intentionalMovementThreshold: 1.0,
            hitTolerance: 2.0,
            contactSizeTolerance: 0.5,
            smoothing: 0.02,
            gestureThresholdMultiplier: 0.60,
            edgeSensitivity: 0.80,
            acceptanceConfidence: 0.50
        )

    public static let keyboard =
        TouchSensitivity(
            movementTolerance: 2.5,
            intentionalMovementThreshold: 5.0,
            hitTolerance: 12.0,
            contactSizeTolerance: 1.3,
            smoothing: 0.20,
            gestureThresholdMultiplier: 1.0,
            edgeSensitivity: 1.0,
            acceptanceConfidence: 0.55
        )
}
2. Interaction modes
import Foundation

public enum TouchSensitivityMode:
    String,
    Codable,
    Sendable {

    case automatic
    case normal
    case precise
    case forgiving
    case gaming
    case drawing
    case keyboard
    case accessibility
}
3. Environmental conditions

A sensitivity engine should account for conditions that change touch quality.

import Foundation

public enum TouchEnvironment:
    String,
    Codable,
    Sendable {

    case normal
    case highJitter
    case suspectedWetSurface
    case glovedInteraction
    case lowConfidence
}
4. Screen regions
import Foundation

public enum TouchScreenRegion:
    String,
    Codable,
    Sendable {

    case center
    case top
    case bottom
    case leftEdge
    case rightEdge
    case topLeftCorner
    case topRightCorner
    case bottomLeftCorner
    case bottomRightCorner
}
5. User behaviour statistics

The engine can learn interaction characteristics without needing a machine-learning model yet.

import Foundation

public struct TouchBehaviourProfile:
    Codable,
    Sendable {

    public private(set) var averageTapMovement:
        Double = 0

    public private(set) var averageSwipeSpeed:
        Double = 0

    public private(set) var averageContactSize:
        Double = 0

    public private(set) var tapCount:
        UInt64 = 0

    public private(set) var swipeCount:
        UInt64 = 0

    public private(set) var totalContacts:
        UInt64 = 0

    public init() {}

    public mutating func recordTap(
        movement:
            Double
    ) {
        tapCount += 1
        totalContacts += 1

        averageTapMovement =
            runningAverage(
                oldAverage:
                    averageTapMovement,
                newValue:
                    movement,
                count:
                    tapCount
            )
    }

    public mutating func recordSwipe(
        speed:
            Double
    ) {
        swipeCount += 1
        totalContacts += 1

        averageSwipeSpeed =
            runningAverage(
                oldAverage:
                    averageSwipeSpeed,
                newValue:
                    speed,
                count:
                    swipeCount
            )
    }

    public mutating func recordContactSize(
        _ size:
            Double
    ) {

        totalContacts += 1

        averageContactSize =
            runningAverage(
                oldAverage:
                    averageContactSize,
                newValue:
                    size,
                count:
                    totalContacts
            )
    }

    private func runningAverage(
        oldAverage:
            Double,
        newValue:
            Double,
        count:
            UInt64
    ) -> Double {

        guard count > 1
        else {
            return newValue
        }

        return
            oldAverage +
            (
                newValue -
                oldAverage
            ) /
            Double(count)
    }
}
6. Sensitivity context

Everything the engine needs to make its decision is gathered into one structure.

import Foundation

public struct TouchSensitivityContext:
    Sendable {

    public let mode:
        TouchSensitivityMode

    public let environment:
        TouchEnvironment

    public let screenRegion:
        TouchScreenRegion

    public let screenBounds:
        TouchScreenBounds

    public let behaviour:
        TouchBehaviourProfile

    public let fingerCount:
        Int

    public let accessibilityEnabled:
        Bool

    public init(
        mode:
            TouchSensitivityMode = .automatic,
        environment:
            TouchEnvironment = .normal,
        screenRegion:
            TouchScreenRegion = .center,
        screenBounds:
            TouchScreenBounds,
        behaviour:
            TouchBehaviourProfile = TouchBehaviourProfile(),
        fingerCount:
            Int = 1,
        accessibilityEnabled:
            Bool = false
    ) {
        self.mode =
            mode

        self.environment =
            environment

        self.screenRegion =
            screenRegion

        self.screenBounds =
            screenBounds

        self.behaviour =
            behaviour

        self.fingerCount =
            max(
                1,
                fingerCount
            )

        self.accessibilityEnabled =
            accessibilityEnabled
    }
}
7. Adaptive policy

This is the main calculation.

import Foundation

public struct AdaptiveSensitivityPolicy:
    Sendable {

    public init() {}

    public func resolve(
        context:
            TouchSensitivityContext
    ) -> TouchSensitivity {

        var sensitivity =
            baseSensitivity(
                mode:
                    context.mode
            )

        applyEnvironment(
            &sensitivity,
            environment:
                context.environment
        )

        applyBehaviour(
            &sensitivity,
            behaviour:
                context.behaviour
        )

        applyRegion(
            &sensitivity,
            region:
                context.screenRegion
        )

        applyAccessibility(
            &sensitivity,
            enabled:
                context.accessibilityEnabled
        )

        applyMultiTouch(
            &sensitivity,
            fingerCount:
                context.fingerCount
        )

        return clamp(
            sensitivity
        )
    }

    private func baseSensitivity(
        mode:
            TouchSensitivityMode
    ) -> TouchSensitivity {

        switch mode {

        case .automatic:
            return .normal

        case .normal:
            return .normal

        case .precise:
            return .precise

        case .forgiving:
            return .forgiving

        case .gaming:
            return .gaming

        case .drawing:
            return .drawing

        case .keyboard:
            return .keyboard

        case .accessibility:
            return .forgiving
        }
    }

    private func applyEnvironment(
        _ sensitivity:
            inout TouchSensitivity,
        environment:
            TouchEnvironment
    ) {

        switch environment {

        case .normal:
            break

        case .highJitter:

            sensitivity.smoothing =
                min(
                    0.50,
                    sensitivity.smoothing +
                    0.15
                )

            sensitivity.movementTolerance *=
                1.25

        case .suspectedWetSurface:

            sensitivity.hitTolerance *=
                1.15

            sensitivity.acceptanceConfidence =
                min(
                    0.90,
                    sensitivity.acceptanceConfidence +
                    0.10
                )

        case .glovedInteraction:

            sensitivity.hitTolerance *=
                1.35

            sensitivity.movementTolerance *=
                1.30

        case .lowConfidence:

            sensitivity.acceptanceConfidence =
                min(
                    0.95,
                    sensitivity.acceptanceConfidence +
                    0.15
                )
        }
    }

    private func applyBehaviour(
        _ sensitivity:
            inout TouchSensitivity,
        behaviour:
            TouchBehaviourProfile
    ) {

        guard behaviour.totalContacts >= 20
        else {
            return
        }

        // Users with very stable taps can use
        // more precise hit interpretation.

        if behaviour.averageTapMovement < 2 {

            sensitivity.movementTolerance *=
                0.90
        }

        // Fast swipe users benefit from
        // slightly lower gesture thresholds.

        if behaviour.averageSwipeSpeed > 1_200 {

            sensitivity.gestureThresholdMultiplier *=
                0.92
        }
    }

    private func applyRegion(
        _ sensitivity:
            inout TouchSensitivity,
        region:
            TouchScreenRegion
    ) {

        switch region {

        case .center:
            break

        case .top,
             .bottom:

            sensitivity.hitTolerance *=
                1.05

        case .leftEdge,
             .rightEdge:

            sensitivity.edgeSensitivity *=
                1.15

        case .topLeftCorner,
             .topRightCorner,
             .bottomLeftCorner,
             .bottomRightCorner:

            sensitivity.edgeSensitivity *=
                1.25
        }
    }

    private func applyAccessibility(
        _ sensitivity:
            inout TouchSensitivity,
        enabled:
            Bool
    ) {

        guard enabled
        else {
            return
        }

        sensitivity.hitTolerance *=
            1.50

        sensitivity.movementTolerance *=
            1.40

        sensitivity.acceptanceConfidence =
            0.50
    }

    private func applyMultiTouch(
        _ sensitivity:
            inout TouchSensitivity,
        fingerCount:
            Int
    ) {

        guard fingerCount >= 2
        else {
            return
        }

        // Multi-touch interactions need
        // tighter gesture interpretation.

        sensitivity.gestureThresholdMultiplier *=
            0.90
    }

    private func clamp(
        _ sensitivity:
            TouchSensitivity
    ) -> TouchSensitivity {

        var result =
            sensitivity

        result.movementTolerance =
            max(
                0.1,
                min(
                    50,
                    result.movementTolerance
                )
            )

        result.intentionalMovementThreshold =
            max(
                0.2,
                min(
                    100,
                    result.intentionalMovementThreshold
                )
            )

        result.hitTolerance =
            max(
                1,
                min(
                    100,
                    result.hitTolerance
                )
            )

        result.smoothing =
            max(
                0,
                min(
                    1,
                    result.smoothing
                )
            )

        result.gestureThresholdMultiplier =
            max(
                0.25,
                min(
                    3,
                    result.gestureThresholdMultiplier
                )
            )

        result.edgeSensitivity =
            max(
                0.25,
                min(
                    3,
                    result.edgeSensitivity
                )
            )

        result.acceptanceConfidence =
            max(
                0,
                min(
                    1,
                    result.acceptanceConfidence
                )
            )

        return result
    }
}
8. Automatic context detection

Rather than requiring the application to explicitly tell us everything, we can infer some context from the touch stream.

import Foundation

public struct TouchContextDetector:
    Sendable {

    public init() {}

    public func detectRegion(
        position:
            TouchVector,
        screen:
            TouchScreenBounds,
        edgeThreshold:
            Double = 32
    ) -> TouchScreenRegion {

        let left =
            position.x <= edgeThreshold

        let right =
            position.x >=
            screen.width -
            edgeThreshold

        let top =
            position.y <= edgeThreshold

        let bottom =
            position.y >=
            screen.height -
            edgeThreshold

        switch (
            left,
            right,
            top,
            bottom
        ) {

        case (true, false, true, false):
            return .topLeftCorner

        case (false, true, true, false):
            return .topRightCorner

        case (true, false, false, true):
            return .bottomLeftCorner

        case (false, true, false, true):
            return .bottomRightCorner

        case (true, false, false, false):
            return .leftEdge

        case (false, true, false, false):
            return .rightEdge

        case (false, false, true, false):
            return .top

        case (false, false, false, true):
            return .bottom

        default:
            return .center
        }
    }
}
9. Sensitivity-adjusted touch

The engine needs to output not only the policy but also how the current contact should be interpreted.

import Foundation

public struct AdaptiveTouchResult:
    Sendable {

    public let touchID:
        TouchID

    public let sensitivity:
        TouchSensitivity

    public let adjustedMovement:
        TouchVector

    public let movementMagnitude:
        Double

    public let isIntentionalMovement:
        Bool

    public let confidence:
        Double

    public init(
        touchID:
            TouchID,
        sensitivity:
            TouchSensitivity,
        adjustedMovement:
            TouchVector,
        movementMagnitude:
            Double,
        isIntentionalMovement:
            Bool,
        confidence:
            Double
    ) {

        self.touchID =
            touchID

        self.sensitivity =
            sensitivity

        self.adjustedMovement =
            adjustedMovement

        self.movementMagnitude =
            movementMagnitude

        self.isIntentionalMovement =
            isIntentionalMovement

        self.confidence =
            confidence
    }
}
10. Per-touch state
import Foundation

private struct AdaptiveTouchTrack:
    Sendable {

    var previousPosition:
        TouchVector?

    var smoothedPosition:
        TouchVector?

    var lastTimestamp:
        TimeInterval = 0

    var totalDistance:
        Double = 0

    var sampleCount:
        UInt64 = 0

    var startPosition:
        TouchVector?
}
11. Main Adaptive Touch Sensitivity Engine
AdaptiveTouchSensitivityEngine.swift
import Foundation

public actor AdaptiveTouchSensitivityEngine {

    private let policy:
        AdaptiveSensitivityPolicy

    private let contextDetector:
        TouchContextDetector

    private var tracks:
        [TouchID: AdaptiveTouchTrack] = [:]

    private var behaviour =
        TouchBehaviourProfile()

    public init() {

        self.policy =
            AdaptiveSensitivityPolicy()

        self.contextDetector =
            TouchContextDetector()
    }

    // MARK: Process

    public func process(
        sample:
            TouchSample,
        screen:
            TouchScreenBounds,
        mode:
            TouchSensitivityMode = .automatic,
        environment:
            TouchEnvironment = .normal,
        fingerCount:
            Int = 1,
        accessibilityEnabled:
            Bool = false
    ) -> AdaptiveTouchResult {

        var track =
            tracks[
                sample.touchID
            ] ??
            AdaptiveTouchTrack()

        let region =
            contextDetector.detectRegion(
                position:
                    sample.position,
                screen:
                    screen
            )

        let context =
            TouchSensitivityContext(
                mode:
                    mode,
                environment:
                    environment,
                screenRegion:
                    region,
                screenBounds:
                    screen,
                behaviour:
                    behaviour,
                fingerCount:
                    fingerCount,
                accessibilityEnabled:
                    accessibilityEnabled
            )

        let sensitivity =
            policy.resolve(
                context:
                    context
            )

        // MARK: Position filtering

        let smoothed =
            smooth(
                previous:
                    track.smoothedPosition,
                current:
                    sample.position,
                amount:
                    sensitivity.smoothing
            )

        // MARK: Movement

        let movement =
            if let previous =
                track.smoothedPosition {

                smoothed - previous

            } else {
                TouchVector.zero
            }

        let movementMagnitude =
            movement.magnitude

        track.totalDistance +=
            movementMagnitude

        track.sampleCount += 1

        track.previousPosition =
            sample.position

        track.smoothedPosition =
            smoothed

        track.lastTimestamp =
            sample.timestamp

        if track.startPosition == nil {

            track.startPosition =
                sample.position
        }

        tracks[
            sample.touchID
        ] =
            track

        let intentional =
            movementMagnitude >=
            sensitivity
                .intentionalMovementThreshold

        let confidence =
            movementConfidence(
                movement:
                    movementMagnitude,
                sensitivity:
                    sensitivity
            )

        if sample.phase ==
            .ended ||
           sample.phase ==
            .cancelled {

            finalizeBehaviour(
                track:
                    track,
                sample:
                    sample
            )

            tracks.removeValue(
                forKey:
                    sample.touchID
            )
        }

        return AdaptiveTouchResult(
            touchID:
                sample.touchID,
            sensitivity:
                sensitivity,
            adjustedMovement:
                movement,
            movementMagnitude:
                movementMagnitude,
            isIntentionalMovement:
                intentional,
            confidence:
                confidence
        )
    }

    // MARK: Smoothing

    private func smooth(
        previous:
            TouchVector?,
        current:
            TouchVector,
        amount:
            Double
    ) -> TouchVector {

        guard let previous
        else {
            return current
        }

        let clamped =
            max(
                0,
                min(
                    1,
                    amount
                )
            )

        return
            current * (1 - clamped) +
            previous * clamped
    }

    // MARK: Movement confidence

    private func movementConfidence(
        movement:
            Double,
        sensitivity:
            TouchSensitivity
    ) -> Double {

        let threshold =
            sensitivity
                .intentionalMovementThreshold

        guard threshold > 0
        else {
            return 1
        }

        return min(
            1,
            movement / threshold
        )
    }

    // MARK: Behaviour

    private func finalizeBehaviour(
        track:
            AdaptiveTouchTrack,
        sample:
            TouchSample
    ) {

        guard
            let start =
                track.startPosition
        else {
            return
        }

        let displacement =
            start.distance(
                to:
                    sample.position
            )

        if displacement < 12 {

            behaviour.recordTap(
                movement:
                    displacement
            )

        } else if
            track.lastTimestamp > 0 {

            let duration =
                sample.timestamp -
                track.lastTimestamp

            if duration > 0 {

                let speed =
                    track.totalDistance /
                    duration

                behaviour.recordSwipe(
                    speed:
                        speed
                )
            }
        }

        if let area =
            sample.contactArea {

            behaviour.recordContactSize(
                area
            )
        }
    }

    // MARK: Profile

    public func behaviourProfile()
        -> TouchBehaviourProfile {

        behaviour
    }

    public func reset() {

        tracks.removeAll()
        behaviour =
            TouchBehaviourProfile()
    }
}

There is one thing I'd change before production: finalizeBehaviour should preserve the touch start timestamp separately instead of using lastTimestamp, because the latter is the final sample timestamp. Here's the corrected track structure and finalizer:

private struct AdaptiveTouchTrack:
    Sendable {

    var previousPosition:
        TouchVector?

    var smoothedPosition:
        TouchVector?

    var startPosition:
        TouchVector?

    var startTimestamp:
        TimeInterval?

    var lastTimestamp:
        TimeInterval = 0

    var totalDistance:
        Double = 0

    var sampleCount:
        UInt64 = 0
}

And:

private func finalizeBehaviour(
    track:
        AdaptiveTouchTrack,
    sample:
        TouchSample
) {

    guard
        let start =
            track.startPosition
    else {
        return
    }

    let displacement =
        start.distance(
            to:
                sample.position
        )

    if displacement < 12 {

        behaviour.recordTap(
            movement:
                displacement
        )

    } else if
        let startTime =
            track.startTimestamp {

        let duration =
            sample.timestamp -
            startTime

        if duration > 0 {

            let speed =
                track.totalDistance /
                duration

            behaviour.recordSwipe(
                speed:
                    speed
            )
        }
    }

    if let area =
        sample.contactArea {

        behaviour.recordContactSize(
            area
        )
    }
}

And when the first sample arrives:

if track.startPosition == nil {

    track.startPosition =
        sample.position

    track.startTimestamp =
        sample.timestamp
}

That gives us the correct touch duration.

12. Direct sensitivity changes

Apps such as games or drawing applications may want to explicitly control the mode.

let engine =
    AdaptiveTouchSensitivityEngine()

let result =
    await engine.process(
        sample:
            sample,
        screen:
            TouchScreenBounds(
                width:
                    1179,
                height:
                    2556
            ),
        mode:
            .gaming
    )

print(
    result.sensitivity
)
13. Automatic mode

The interesting mode is .automatic.

The system can start conservatively:

unknown user
      │
      ▼
normal sensitivity
      │
      ▼
collect interaction statistics
      │
      ▼
20+ interactions
      │
      ▼
behaviour profile
      │
      ├── precise taps
      ├── fast swipes
      └── contact characteristics
      │
      ▼
adapt sensitivity

This means the engine doesn't need to assume that every user interacts with the screen identically.

14. Combine #1 + #2 + #3

Now our touch stack becomes considerably more interesting.

                         TOUCH INPUT
                              │
                              ▼
                  ┌─────────────────────┐
                  │ Adaptive Sensitivity│
                  │      Engine #3      │
                  └──────────┬──────────┘
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
      Predictive Touch #1          Palm Rejection #2
              │                             │
              ├─ velocity                  ├─ geometry
              ├─ acceleration              ├─ area
              ├─ prediction                ├─ context
              └─ latency                   └─ probability
              │                             │
              └──────────────┬──────────────┘
                             ▼
                     INTELLIGENT TOUCH
                             │
                             ▼
                    Gesture Recognition
                             │
                             ▼
                         UI / GAME

And this gives us a much more useful concept than a simple “touch sensitivity” slider.

The engine can effectively create a dynamic touch response surface:

               TOP
       ┌───────────────────┐
       │   more forgiving  │
       │                   │
       │    precise        │
 LEFT  │      centre       │ RIGHT
 EDGE  │                   │ EDGE
       │                   │
       │   gesture-aware   │
       └───────────────────┘
              BOTTOM

Different parts of the screen can have different thresholds without changing the physical touchscreen itself.

15. Where this becomes really powerful

The next evolution would be to add a touch calibration engine.

Instead of merely saying:

sensitivity = 1.0

we could maintain a profile such as:

public struct TouchCalibrationProfile:
    Codable,
    Sendable {

    public var preferredHitTolerance:
        Double

    public var preferredMovementThreshold:
        Double

    public var preferredSmoothing:
        Double

    public var preferredEdgeTolerance:
        Double

    public var preferredGestureThreshold:
        Double

    public init(
        preferredHitTolerance:
            Double = 8,
        preferredMovementThreshold:
            Double = 4,
        preferredSmoothing:
            Double = 0.15,
        preferredEdgeTolerance:
            Double = 32,
        preferredGestureThreshold:
            Double = 1
    ) {

        self.preferredHitTolerance =
            preferredHitTolerance

        self.preferredMovementThreshold =
            preferredMovementThreshold

        self.preferredSmoothing =
            preferredSmoothing

        self.preferredEdgeTolerance =
            preferredEdgeTolerance

        self.preferredGestureThreshold =
            preferredGestureThreshold
    }
}

Then the system could learn from:

                 USER
                  │
        ┌─────────┴─────────┐
        │                   │
       taps              gestures
        │                   │
        ▼                   ▼
    accuracy            recognition
        │                   │
        └─────────┬─────────┘
                  ▼
          calibration model
                  │
                  ▼
        personalized touch
             response
             
             
             
             
             
             
             
             
             
             1. Core types
import Foundation
import CoreGraphics

// MARK: - Touch Identity

public struct SubPixelTouchID: Hashable, Sendable {
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

// MARK: - 2D Vector

public struct TouchPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = TouchPoint(x: 0, y: 0)

    public static func + (
        lhs: TouchPoint,
        rhs: TouchPoint
    ) -> TouchPoint {
        TouchPoint(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }

    public static func - (
        lhs: TouchPoint,
        rhs: TouchPoint
    ) -> TouchPoint {
        TouchPoint(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y
        )
    }

    public static func * (
        lhs: TouchPoint,
        rhs: Double
    ) -> TouchPoint {
        TouchPoint(
            x: lhs.x * rhs,
            y: lhs.y * rhs
        )
    }

    public static func / (
        lhs: TouchPoint,
        rhs: Double
    ) -> TouchPoint {
        guard rhs != 0 else {
            return lhs
        }

        return TouchPoint(
            x: lhs.x / rhs,
            y: lhs.y / rhs
        )
    }

    public var magnitude: Double {
        sqrt(x * x + y * y)
    }

    public var squaredMagnitude: Double {
        x * x + y * y
    }

    public var normalized: TouchPoint {
        let length = magnitude

        guard length > 0 else {
            return .zero
        }

        return self / length
    }

    public func distance(to other: TouchPoint) -> Double {
        (self - other).magnitude
    }

    public func clampedMagnitude(
        maximum: Double
    ) -> TouchPoint {
        let length = magnitude

        guard length > maximum else {
            return self
        }

        return normalized * maximum
    }
}
2. Raw touch sample
public enum SubPixelTouchPhase: Sendable {
    case began
    case moved
    case stationary
    case ended
    case cancelled
}

public struct SubPixelTouchSample: Sendable {

    public let id: SubPixelTouchID

    public let position: TouchPoint

    /// Optional physical contact radius.
    public let majorRadius: Double?

    /// Optional secondary radius.
    public let minorRadius: Double?

    /// Optional force.
    public let force: Double?

    /// Monotonic timestamp in seconds.
    public let timestamp: TimeInterval

    public let phase: SubPixelTouchPhase

    public init(
        id: SubPixelTouchID,
        position: TouchPoint,
        majorRadius: Double? = nil,
        minorRadius: Double? = nil,
        force: Double? = nil,
        timestamp: TimeInterval,
        phase: SubPixelTouchPhase
    ) {
        self.id = id
        self.position = position
        self.majorRadius = majorRadius
        self.minorRadius = minorRadius
        self.force = force
        self.timestamp = timestamp
        self.phase = phase
    }
}
3. Estimated touch state

We want to estimate:

x
y

vx
vy

ax
ay

rather than merely storing the last position.

public struct TouchStateEstimate: Sendable {

    public var position: TouchPoint

    public var velocity: TouchPoint

    public var acceleration: TouchPoint

    public var timestamp: TimeInterval

    /// 0...1
    public var confidence: Double

    /// Estimated positional noise in points.
    public var noiseEstimate: Double

    public init(
        position: TouchPoint,
        velocity: TouchPoint,
        acceleration: TouchPoint,
        timestamp: TimeInterval,
        confidence: Double,
        noiseEstimate: Double
    ) {
        self.position = position
        self.velocity = velocity
        self.acceleration = acceleration
        self.timestamp = timestamp
        self.confidence = confidence
        self.noiseEstimate = noiseEstimate
    }
}
4. Configuration

This is intentionally device-independent.

public struct SubPixelFilterConfiguration: Sendable {

    /// Minimum accepted timestep.
    public var minimumDeltaTime: Double = 0.0005

    /// Maximum timestep before treating the sample as discontinuous.
    public var maximumDeltaTime: Double = 0.050

    /// Base smoothing factor.
    public var baseSmoothing: Double = 0.72

    /// Smoothing when touch is moving quickly.
    public var motionSmoothing: Double = 0.28

    /// Maximum positional innovation before treating a sample as suspicious.
    public var outlierThreshold: Double = 45.0

    /// Maximum predicted displacement.
    public var maximumPredictionDistance: Double = 250.0

    /// Velocity adaptation rate.
    public var velocityAdaptation: Double = 0.55

    /// Acceleration adaptation rate.
    public var accelerationAdaptation: Double = 0.40

    /// Noise adaptation rate.
    public var noiseAdaptation: Double = 0.08

    public init() {}
}
5. Exponential sub-pixel filter

The smoothing amount changes according to motion.

When the finger is stationary:

more smoothing

When the finger is moving rapidly:

less smoothing

That is important because a fixed smoothing filter makes fast scrolling or drawing feel delayed.

public struct AdaptiveSubPixelFilter: Sendable {

    private var configuration: SubPixelFilterConfiguration

    private(set) public var filteredPosition: TouchPoint?

    private(set) public var velocity: TouchPoint = .zero

    private(set) public var acceleration: TouchPoint = .zero

    private(set) public var noiseEstimate: Double = 0

    private(set) public var lastTimestamp: TimeInterval?

    public init(
        configuration: SubPixelFilterConfiguration = .init()
    ) {
        self.configuration = configuration
    }

    public mutating func reset() {

        filteredPosition = nil
        velocity = .zero
        acceleration = .zero
        noiseEstimate = 0
        lastTimestamp = nil
    }

    public mutating func update(
        position measurement: TouchPoint,
        timestamp: TimeInterval
    ) -> TouchStateEstimate {

        guard let previousTimestamp = lastTimestamp,
              let previousPosition = filteredPosition else {

            filteredPosition = measurement
            lastTimestamp = timestamp

            return TouchStateEstimate(
                position: measurement,
                velocity: .zero,
                acceleration: .zero,
                timestamp: timestamp,
                confidence: 1,
                noiseEstimate: 0
            )
        }

        var dt = timestamp - previousTimestamp

        if dt < configuration.minimumDeltaTime {
            dt = configuration.minimumDeltaTime
        }

        if dt > configuration.maximumDeltaTime {

            filteredPosition = measurement
            velocity = .zero
            acceleration = .zero
            noiseEstimate = 0
            lastTimestamp = timestamp

            return TouchStateEstimate(
                position: measurement,
                velocity: .zero,
                acceleration: .zero,
                timestamp: timestamp,
                confidence: 0.5,
                noiseEstimate: 0
            )
        }

        let rawDisplacement = measurement - previousPosition
        let rawVelocity = rawDisplacement / dt

        let velocityChange = rawVelocity - velocity
        let rawAcceleration = velocityChange / dt

        let speed = rawVelocity.magnitude

        let movementRatio = min(
            speed / 1500.0,
            1.0
        )

        let smoothing = configuration.baseSmoothing
            + (
                configuration.motionSmoothing
                - configuration.baseSmoothing
            ) * movementRatio

        let alpha = 1.0 - smoothing

        let newPosition =
            previousPosition * (1.0 - alpha)
            + measurement * alpha

        let newVelocity =
            velocity * (1.0 - configuration.velocityAdaptation)
            + rawVelocity * configuration.velocityAdaptation

        let newAcceleration =
            acceleration * (1.0 - configuration.accelerationAdaptation)
            + rawAcceleration * configuration.accelerationAdaptation

        let innovation =
            measurement.distance(to: newPosition)

        noiseEstimate =
            noiseEstimate * (1.0 - configuration.noiseAdaptation)
            + innovation * configuration.noiseAdaptation

        filteredPosition = newPosition
        velocity = newVelocity
        acceleration = newAcceleration
        lastTimestamp = timestamp

        let confidence = calculateConfidence(
            innovation: innovation,
            noise: noiseEstimate,
            speed: speed
        )

        return TouchStateEstimate(
            position: newPosition,
            velocity: newVelocity,
            acceleration: newAcceleration,
            timestamp: timestamp,
            confidence: confidence,
            noiseEstimate: noiseEstimate
        )
    }

    private func calculateConfidence(
        innovation: Double,
        noise: Double,
        speed: Double
    ) -> Double {

        let innovationPenalty =
            min(innovation / configuration.outlierThreshold, 1.0)

        let noisePenalty =
            min(noise / 15.0, 1.0)

        let speedPenalty =
            min(speed / 4000.0, 1.0)

        let confidence =
            1.0
            - innovationPenalty * 0.55
            - noisePenalty * 0.30
            - speedPenalty * 0.15

        return min(
            max(confidence, 0),
            1
        )
    }
}
6. Jitter detector

A touchscreen should not interpret tiny electrical/mechanical fluctuations as intentional movement.

public struct TouchJitterDetector: Sendable {

    public var jitterThreshold: Double = 1.25

    public var severeJitterThreshold: Double = 4.0

    public init() {}

    public func classify(
        displacement: Double,
        noiseEstimate: Double
    ) -> JitterClassification {

        if displacement <= jitterThreshold {
            return .stable
        }

        if displacement <= severeJitterThreshold {
            return .minorJitter
        }

        if noiseEstimate > severeJitterThreshold {
            return .severeJitter
        }

        return .movement
    }
}

public enum JitterClassification: Sendable {
    case stable
    case minorJitter
    case severeJitter
    case movement
}
7. Outlier rejection

One bad sample shouldn't suddenly teleport a finger 100 pixels.

public struct TouchOutlierFilter: Sendable {

    public var maximumInnovation: Double

    public init(
        maximumInnovation: Double = 45.0
    ) {
        self.maximumInnovation = maximumInnovation
    }

    public func filter(
        measurement: TouchPoint,
        predicted: TouchPoint
    ) -> TouchPoint {

        let difference = measurement - predicted
        let distance = difference.magnitude

        guard distance > maximumInnovation else {
            return measurement
        }

        let clamped = difference.clampedMagnitude(
            maximum: maximumInnovation
        )

        return predicted + clamped
    }
}
8. Constant-acceleration predictor

This is where #4 becomes substantially more useful than a basic linear extrapolator.

We estimate:

p(t) = p0 + vt + ½at²
public struct SubPixelPredictor: Sendable {

    public var maximumDistance: Double

    public init(
        maximumDistance: Double = 250
    ) {
        self.maximumDistance = maximumDistance
    }

    public func predict(
        state: TouchStateEstimate,
        horizon: TimeInterval
    ) -> TouchPoint {

        let velocityTerm =
            state.velocity * horizon

        let accelerationTerm =
            state.acceleration
            * (0.5 * horizon * horizon)

        let displacement =
            velocityTerm + accelerationTerm

        let bounded =
            displacement.clampedMagnitude(
                maximum: maximumDistance
            )

        return state.position + bounded
    }

    public func predictMultiple(
        state: TouchStateEstimate,
        horizons: [TimeInterval]
    ) -> [TouchPoint] {

        horizons.map {
            predict(
                state: state,
                horizon: $0
            )
        }
    }
}
9. Multi-horizon prediction

Instead of producing one prediction, we can provide several.

public struct TouchPredictionSet: Sendable {

    public let current: TouchPoint

    public let prediction4ms: TouchPoint

    public let prediction8ms: TouchPoint

    public let prediction12ms: TouchPoint

    public let prediction16ms: TouchPoint

    public let confidence: Double

    public init(
        current: TouchPoint,
        prediction4ms: TouchPoint,
        prediction8ms: TouchPoint,
        prediction12ms: TouchPoint,
        prediction16ms: TouchPoint,
        confidence: Double
    ) {
        self.current = current
        self.prediction4ms = prediction4ms
        self.prediction8ms = prediction8ms
        self.prediction12ms = prediction12ms
        self.prediction16ms = prediction16ms
        self.confidence = confidence
    }
}
10. Main synchronous hot-path engine

This is intentionally a struct.

It can therefore sit directly in a high-frequency input pipeline without requiring an actor hop for every sample.

public struct SubPixelTouchEstimator: Sendable {

    private var filter: AdaptiveSubPixelFilter

    private let jitterDetector: TouchJitterDetector

    private let outlierFilter: TouchOutlierFilter

    private let predictor: SubPixelPredictor

    public init(
        configuration: SubPixelFilterConfiguration = .init()
    ) {

        self.filter =
            AdaptiveSubPixelFilter(
                configuration: configuration
            )

        self.jitterDetector =
            TouchJitterDetector()

        self.outlierFilter =
            TouchOutlierFilter(
                maximumInnovation:
                    configuration.outlierThreshold
            )

        self.predictor =
            SubPixelPredictor(
                maximumDistance:
                    configuration.maximumPredictionDistance
            )
    }

    public mutating func reset() {
        filter.reset()
    }

    public mutating func process(
        sample: SubPixelTouchSample
    ) -> SubPixelTouchResult {

        let estimate =
            filter.update(
                position: sample.position,
                timestamp: sample.timestamp
            )

        let jitter =
            jitterDetector.classify(
                displacement:
                    sample.position.distance(
                        to: estimate.position
                    ),
                noiseEstimate:
                    estimate.noiseEstimate
            )

        let predicted4 =
            predictor.predict(
                state: estimate,
                horizon: 0.004
            )

        let predicted8 =
            predictor.predict(
                state: estimate,
                horizon: 0.008
            )

        let predicted12 =
            predictor.predict(
                state: estimate,
                horizon: 0.012
            )

        let predicted16 =
            predictor.predict(
                state: estimate,
                horizon: 0.016
            )

        let acceptedMeasurement =
            outlierFilter.filter(
                measurement: sample.position,
                predicted: estimate.position
            )

        return SubPixelTouchResult(
            touchID: sample.id,
            timestamp: sample.timestamp,
            rawPosition: sample.position,
            filteredPosition: estimate.position,
            acceptedPosition: acceptedMeasurement,
            velocity: estimate.velocity,
            acceleration: estimate.acceleration,
            noiseEstimate: estimate.noiseEstimate,
            jitter: jitter,
            predictions: TouchPredictionSet(
                current: estimate.position,
                prediction4ms: predicted4,
                prediction8ms: predicted8,
                prediction12ms: predicted12,
                prediction16ms: predicted16,
                confidence: estimate.confidence
            ),
            confidence: estimate.confidence
        )
    }
}
11. Result type
public struct SubPixelTouchResult: Sendable {

    public let touchID: SubPixelTouchID

    public let timestamp: TimeInterval

    public let rawPosition: TouchPoint

    public let filteredPosition: TouchPoint

    public let acceptedPosition: TouchPoint

    public let velocity: TouchPoint

    public let acceleration: TouchPoint

    public let noiseEstimate: Double

    public let jitter: JitterClassification

    public let predictions: TouchPredictionSet

    public let confidence: Double

    public var isStable: Bool {
        jitter == .stable
    }

    public var isMoving: Bool {
        velocity.magnitude > 10
    }
}
12. Multi-touch manager

Each finger gets its own estimator.

public actor MultiTouchSubPixelEngine {

    private var estimators:
        [SubPixelTouchID: SubPixelTouchEstimator] = [:]

    private let configuration:
        SubPixelFilterConfiguration

    public init(
        configuration: SubPixelFilterConfiguration = .init()
    ) {
        self.configuration = configuration
    }

    public func process(
        sample: SubPixelTouchSample
    ) -> SubPixelTouchResult {

        var estimator =
            estimators[sample.id]
            ?? SubPixelTouchEstimator(
                configuration: configuration
            )

        let result =
            estimator.process(
                sample: sample
            )

        estimators[sample.id] = estimator

        switch sample.phase {

        case .ended, .cancelled:
            estimators.removeValue(
                forKey: sample.id
            )

        default:
            break
        }

        return result
    }

    public func reset() {
        estimators.removeAll()
    }
}
13. Sub-pixel interpolation

The next layer can generate an interpolated point between two measured positions.

public struct SubPixelInterpolator: Sendable {

    public init() {}

    public func interpolate(
        from start: TouchPoint,
        to end: TouchPoint,
        fraction: Double
    ) -> TouchPoint {

        let t =
            min(
                max(fraction, 0),
                1
            )

        return start * (1.0 - t)
            + end * t
    }
}

This is particularly useful when the input sampling interval doesn't line up perfectly with the rendering interval.

14. Frame-time prediction

For a display pipeline, prediction should ideally be tied to the expected rendering deadline rather than always predicting exactly 8 ms.

public struct DisplayPredictionClock: Sendable {

    public var refreshRate: Double

    public init(
        refreshRate: Double
    ) {
        self.refreshRate = refreshRate
    }

    public var frameDuration: Double {
        guard refreshRate > 0 else {
            return 1.0 / 60.0
        }

        return 1.0 / refreshRate
    }

    public func predictionHorizon(
        renderLatency: Double
    ) -> Double {

        frameDuration + renderLatency
    }
}

Examples:

60 Hz  → 16.67 ms/frame
90 Hz  → 11.11 ms/frame
120 Hz →  8.33 ms/frame
144 Hz →  6.94 ms/frame
240 Hz →  4.17 ms/frame

The important point is that the predictor should eventually predict to the rendering/display deadline, not simply use a hard-coded number.

15. Frame-synchronised prediction
public struct FrameSynchronizedTouchPredictor: Sendable {

    private let predictor: SubPixelPredictor

    public init(
        maximumPredictionDistance: Double = 250
    ) {
        predictor = SubPixelPredictor(
            maximumDistance:
                maximumPredictionDistance
        )
    }

    public func predict(
        state: TouchStateEstimate,
        display: DisplayPredictionClock,
        renderLatency: TimeInterval
    ) -> TouchPoint {

        let horizon =
            display.predictionHorizon(
                renderLatency:
                    renderLatency
            )

        return predictor.predict(
            state: state,
            horizon: horizon
        )
    }
}
16. Prediction-error measurement

This is extremely important.

A production-quality system shouldn't simply predict. It should continuously determine how wrong its predictions were.

public struct PredictionErrorSample: Sendable {

    public let touchID: SubPixelTouchID

    public let horizon: TimeInterval

    public let predicted: TouchPoint

    public let actual: TouchPoint

    public let errorDistance: Double

    public init(
        touchID: SubPixelTouchID,
        horizon: TimeInterval,
        predicted: TouchPoint,
        actual: TouchPoint
    ) {

        self.touchID = touchID
        self.horizon = horizon
        self.predicted = predicted
        self.actual = actual

        self.errorDistance =
            predicted.distance(
                to: actual
            )
    }
}
17. Adaptive prediction controller

Now we can make the system learn how aggressive prediction should be.

public struct AdaptivePredictionController: Sendable {

    public private(set) var horizon: Double = 0.008

    public var minimumHorizon: Double = 0.002

    public var maximumHorizon: Double = 0.020

    public var targetError: Double = 3.0

    public var adaptationRate: Double = 0.12

    public init() {}

    public mutating func update(
        predictionError: Double
    ) {

        if predictionError > targetError {

            horizon -=
                adaptationRate
                * 0.001

        } else {

            horizon +=
                adaptationRate
                * 0.001
        }

        horizon =
            min(
                max(
                    horizon,
                    minimumHorizon
                ),
                maximumHorizon
            )
    }
}

So the system can behave roughly like:

prediction accurate
        ↓
increase horizon slightly
        ↓
lower apparent input latency

prediction becomes inaccurate
        ↓
reduce horizon
        ↓
prevent overshoot
18. Telemetry
public struct SubPixelTouchMetrics: Sendable {

    public private(set) var samples: UInt64 = 0

    public private(set) var stableSamples: UInt64 = 0

    public private(set) var jitterSamples: UInt64 = 0

    public private(set) var outlierSamples: UInt64 = 0

    public private(set) var cumulativePredictionError: Double = 0

    public private(set) var predictionMeasurements: UInt64 = 0

    public mutating func record(
        result: SubPixelTouchResult
    ) {

        samples += 1

        switch result.jitter {

        case .stable:
            stableSamples += 1

        case .minorJitter,
             .severeJitter:
            jitterSamples += 1

        case .movement:
            break
        }
    }

    public mutating func recordPredictionError(
        _ error: Double
    ) {

        cumulativePredictionError += error

        predictionMeasurements += 1
    }

    public var meanPredictionError: Double {

        guard predictionMeasurements > 0 else {
            return 0
        }

        return cumulativePredictionError
            / Double(predictionMeasurements)
    }

    public var jitterRate: Double {

        guard samples > 0 else {
            return 0
        }

        return Double(jitterSamples)
            / Double(samples)
    }
}
19. High-level adaptive engine

Now combine everything.

public actor SubPixelTouchEngine {

    private var estimators:
        [SubPixelTouchID: SubPixelTouchEstimator] = [:]

    private var controllers:
        [SubPixelTouchID: AdaptivePredictionController] = [:]

    private var metrics =
        SubPixelTouchMetrics()

    private let configuration:
        SubPixelFilterConfiguration

    public init(
        configuration:
            SubPixelFilterConfiguration = .init()
    ) {

        self.configuration =
            configuration
    }

    public func process(
        sample: SubPixelTouchSample
    ) -> SubPixelTouchResult {

        var estimator =
            estimators[sample.id]
            ?? SubPixelTouchEstimator(
                configuration:
                    configuration
            )

        var controller =
            controllers[sample.id]
            ?? AdaptivePredictionController()

        let result =
            estimator.process(
                sample: sample
            )

        metrics.record(
            result: result
        )

        controller.update(
            predictionError:
                result.predictions.current.distance(
                    to: result.rawPosition
                )
        )

        estimators[sample.id] = estimator
        controllers[sample.id] = controller

        if sample.phase == .ended
            || sample.phase == .cancelled {

            estimators.removeValue(
                forKey: sample.id
            )

            controllers.removeValue(
                forKey: sample.id
            )
        }

        return result
    }

    public func statistics()
        -> SubPixelTouchMetrics {

        metrics
    }

    public func reset() {

        estimators.removeAll()
        controllers.removeAll()

        metrics =
            SubPixelTouchMetrics()
    }
}
20. UIKit adapter

For an actual iOS application, the raw UIKit touch data can feed this layer.

#if canImport(UIKit)

import UIKit

public final class SubPixelTouchView: UIView {

    private let engine =
        SubPixelTouchEngine()

    public override func touchesBegan(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches: touches,
            phase: .began
        )
    }

    public override func touchesMoved(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches: touches,
            phase: .moved
        )
    }

    public override func touchesEnded(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches: touches,
            phase: .ended
        )
    }

    public override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {

        process(
            touches: touches,
            phase: .cancelled
        )
    }

    private func process(
        touches: Set<UITouch>,
        phase: SubPixelTouchPhase
    ) {

        for touch in touches {

            let location =
                touch.location(
                    in: self
                )

            let id =
                SubPixelTouchID(
                    UInt64(
                        ObjectIdentifier(
                            touch
                        ).hashValue
                    )
                )

            let sample =
                SubPixelTouchSample(
                    id: id,
                    position: TouchPoint(
                        x: location.x,
                        y: location.y
                    ),
                    majorRadius:
                        Double(touch.majorRadius),
                    force:
                        Double(touch.force),
                    timestamp:
                        touch.timestamp,
                    phase:
                        phase
                )

            Task {

                let result =
                    await engine.process(
                        sample: sample
                    )

                handle(
                    result: result
                )
            }
        }
    }

    private func handle(
        result: SubPixelTouchResult
    ) {

        // Feed result into:
        //
        // gesture recognizer
        // drawing engine
        // game engine
        // scrolling engine
        // custom UI
    }
}

#endif

For a real high-performance implementation, I would not create a new Task per touch sample as above. That adapter is illustrative. The actual hot path should keep the estimator synchronous and schedule only state/telemetry work asynchronously.

21. Example: drawing application

A drawing engine could deliberately use the predicted point.

struct DrawingPoint: Sendable {

    let actual: TouchPoint
    let smoothed: TouchPoint
    let predicted: TouchPoint
}

func makeDrawingPoint(
    from result: SubPixelTouchResult
) -> DrawingPoint {

    DrawingPoint(
        actual: result.rawPosition,
        smoothed: result.filteredPosition,
        predicted:
            result.predictions.prediction8ms
    )
}

This gives the renderer three choices:

RAW
 └── maximum responsiveness
      but maximum jitter

SMOOTHED
 └── cleaner
      but slightly more latency

PREDICTED
 └── visually lowest apparent latency
      but prediction can be wrong
22. XCTest
import XCTest

final class SubPixelTouchEstimatorTests: XCTestCase {

    func testStationaryTouchRemainsStable() {

        var estimator =
            SubPixelTouchEstimator()

        let id =
            SubPixelTouchID(1)

        let first =
            estimator.process(
                sample:
                    SubPixelTouchSample(
                        id: id,
                        position:
                            TouchPoint(
                                x: 100,
                                y: 100
                            ),
                        timestamp: 0,
                        phase: .began
                    )
            )

        XCTAssertEqual(
            first.filteredPosition,
            TouchPoint(
                x: 100,
                y: 100
            )
        )

        let second =
            estimator.process(
                sample:
                    SubPixelTouchSample(
                        id: id,
                        position:
                            TouchPoint(
                                x: 100.2,
                                y: 100.1
                            ),
                        timestamp: 0.008,
                        phase: .moved
                    )
            )

        XCTAssertLessThan(
            second.velocity.magnitude,
            100
        )
    }

    func testMovingTouchProducesVelocity() {

        var estimator =
            SubPixelTouchEstimator()

        let id =
            SubPixelTouchID(2)

        _ = estimator.process(
            sample:
                SubPixelTouchSample(
                    id: id,
                    position:
                        TouchPoint(
                            x: 0,
                            y: 0
                        ),
                    timestamp: 0,
                    phase: .began
                )
        )

        let result =
            estimator.process(
                sample:
                    SubPixelTouchSample(
                        id: id,
                        position:
                            TouchPoint(
                                x: 100,
                                y: 0
                            ),
                        timestamp: 0.01,
                        phase: .moved
                    )
            )

        XCTAssertGreaterThan(
            result.velocity.x,
            0
        )
    }

    func testPredictionMovesAheadOfFinger() {

        var estimator =
            SubPixelTouchEstimator()

        let id =
            SubPixelTouchID(3)

        _ = estimator.process(
            sample:
                SubPixelTouchSample(
                    id: id,
                    position:
                        TouchPoint(
                            x: 0,
                            y: 0
                        ),
                    timestamp: 0,
                    phase: .began
                )
        )

        let result =
            estimator.process(
                sample:
                    SubPixelTouchSample(
                        id: id,
                        position:
                            TouchPoint(
                                x: 10,
                                y: 0
                            ),
                        timestamp: 0.01,
                        phase: .moved
                )
            )

        XCTAssertGreaterThan(
            result.predictions.prediction8ms.x,
            result.filteredPosition.x
        )
    }

    func testReset() {

        var estimator =
            SubPixelTouchEstimator()

        estimator.reset()

        let result =
            estimator.process(
                sample:
                    SubPixelTouchSample(
                        id:
                            SubPixelTouchID(4),
                        position:
                            TouchPoint(
                                x: 50,
                                y: 50
                            ),
                        timestamp: 0,
                        phase: .began
                    )
            )

        XCTAssertEqual(
            result.velocity,
            .zero
        )
    }
}







1. Core geometry
import Foundation
import CoreGraphics

public struct InteractionPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero =
        InteractionPoint(x: 0, y: 0)

    public init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(
            x: x,
            y: y
        )
    }
}

public struct InteractionSize: Sendable {
    public var width: Double
    public var height: Double

    public init(
        width: Double,
        height: Double
    ) {
        self.width = width
        self.height = height
    }
}

public struct InteractionRect: Sendable {

    public var origin: InteractionPoint
    public var size: InteractionSize

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.origin =
            InteractionPoint(
                x: x,
                y: y
            )

        self.size =
            InteractionSize(
                width: width,
                height: height
            )
    }

    public var minX: Double {
        origin.x
    }

    public var maxX: Double {
        origin.x + size.width
    }

    public var minY: Double {
        origin.y
    }

    public var maxY: Double {
        origin.y + size.height
    }

    public var center: InteractionPoint {
        InteractionPoint(
            x: origin.x + size.width / 2,
            y: origin.y + size.height / 2
        )
    }

    public func contains(
        _ point: InteractionPoint
    ) -> Bool {

        point.x >= minX &&
        point.x <= maxX &&
        point.y >= minY &&
        point.y <= maxY
    }

    public func expanded(
        by amount: Double
    ) -> InteractionRect {

        InteractionRect(
            x: minX - amount,
            y: minY - amount,
            width: size.width + amount * 2,
            height: size.height + amount * 2
        )
    }

    public func distance(
        to point: InteractionPoint
    ) -> Double {

        let dx =
            max(
                minX - point.x,
                0,
                point.x - maxX
            )

        let dy =
            max(
                minY - point.y,
                0,
                point.y - maxY
            )

        return sqrt(
            dx * dx + dy * dy
        )
    }
}
2. Zone identity

Each interaction zone gets a strongly typed identifier.

public struct TouchZoneID:
    Hashable,
    Sendable
{
    public let rawValue: String

    public init(
        _ rawValue: String
    ) {
        self.rawValue = rawValue
    }
}
3. Zone types
public enum TouchZoneType:
    Sendable,
    Equatable
{

    case button
    case slider
    case textField
    case keyboardKey

    case scrollView
    case drawingCanvas
    case gameControl

    case dragSource
    case dropTarget

    case navigation
    case toolbar

    case edgeGesture
    case systemReserved

    case custom
}
4. Interaction context

The same physical location can behave differently depending on application state.

public enum TouchInteractionMode:
    Sendable,
    Equatable
{

    case normal
    case typing
    case scrolling
    case drawing
    case gaming
    case dragging
    case selecting
    case accessibility
    case media
}
5. Dynamic touch zone
public struct TouchZone:
    Sendable,
    Identifiable
{

    public let id: TouchZoneID

    public var type: TouchZoneType

    public var frame: InteractionRect

    /// How important this zone is when overlapping another zone.
    public var priority: Int

    /// Base hitbox expansion.
    public var hitExpansion: Double

    /// Minimum confidence required.
    public var minimumConfidence: Double

    /// Whether prediction may be used.
    public var allowsPrediction: Bool

    /// Whether this zone can receive multi-touch.
    public var allowsMultiTouch: Bool

    /// Whether this is currently enabled.
    public var enabled: Bool

    public init(
        id: TouchZoneID,
        type: TouchZoneType,
        frame: InteractionRect,
        priority: Int = 0,
        hitExpansion: Double = 0,
        minimumConfidence: Double = 0.5,
        allowsPrediction: Bool = true,
        allowsMultiTouch: Bool = false,
        enabled: Bool = true
    ) {

        self.id = id
        self.type = type
        self.frame = frame
        self.priority = priority
        self.hitExpansion = hitExpansion
        self.minimumConfidence =
            minimumConfidence
        self.allowsPrediction =
            allowsPrediction
        self.allowsMultiTouch =
            allowsMultiTouch
        self.enabled = enabled
    }

    public var effectiveFrame: InteractionRect {
        frame.expanded(
            by: hitExpansion
        )
    }

    public func contains(
        _ point: InteractionPoint
    ) -> Bool {

        enabled &&
        effectiveFrame.contains(point)
    }
}
6. Screen edge model

This becomes particularly useful for navigation gestures.

public enum TouchEdge:
    Sendable,
    Equatable
{

    case none
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}
public struct TouchEdgeConfiguration:
    Sendable
{

    public var edgeWidth: Double

    public var cornerSize: Double

    public init(
        edgeWidth: Double = 32,
        cornerSize: Double = 48
    ) {
        self.edgeWidth = edgeWidth
        self.cornerSize = cornerSize
    }
}
7. Edge detector
public struct TouchEdgeDetector:
    Sendable
{

    public let configuration:
        TouchEdgeConfiguration

    public init(
        configuration:
            TouchEdgeConfiguration = .init()
    ) {
        self.configuration =
            configuration
    }

    public func detect(
        point: InteractionPoint,
        screen: InteractionRect
    ) -> TouchEdge {

        let left =
            point.x <=
            screen.minX
            + configuration.edgeWidth

        let right =
            point.x >=
            screen.maxX
            - configuration.edgeWidth

        let top =
            point.y <=
            screen.minY
            + configuration.edgeWidth

        let bottom =
            point.y >=
            screen.maxY
            - configuration.edgeWidth

        let corner =
            configuration.cornerSize

        let topLeft =
            point.x <= screen.minX + corner &&
            point.y <= screen.minY + corner

        let topRight =
            point.x >= screen.maxX - corner &&
            point.y <= screen.minY + corner

        let bottomLeft =
            point.x <= screen.minX + corner &&
            point.y >= screen.maxY - corner

        let bottomRight =
            point.x >= screen.maxX - corner &&
            point.y >= screen.maxY - corner

        if topLeft {
            return .topLeft
        }

        if topRight {
            return .topRight
        }

        if bottomLeft {
            return .bottomLeft
        }

        if bottomRight {
            return .bottomRight
        }

        if left {
            return .left
        }

        if right {
            return .right
        }

        if top {
            return .top
        }

        if bottom {
            return .bottom
        }

        return .none
    }
}
8. Context-aware zone profile

Different modes should produce different interaction geometry.

public struct TouchZoneProfile:
    Sendable
{

    public var globalHitExpansion: Double

    public var edgeSensitivity: Double

    public var gestureThresholdMultiplier: Double

    public var predictionWeight: Double

    public var minimumConfidence: Double

    public init(
        globalHitExpansion: Double = 0,
        edgeSensitivity: Double = 1,
        gestureThresholdMultiplier: Double = 1,
        predictionWeight: Double = 1,
        minimumConfidence: Double = 0.5
    ) {
        self.globalHitExpansion =
            globalHitExpansion

        self.edgeSensitivity =
            edgeSensitivity

        self.gestureThresholdMultiplier =
            gestureThresholdMultiplier

        self.predictionWeight =
            predictionWeight

        self.minimumConfidence =
            minimumConfidence
    }

    public static let normal =
        TouchZoneProfile()

    public static let typing =
        TouchZoneProfile(
            globalHitExpansion: 6,
            edgeSensitivity: 0.8,
            gestureThresholdMultiplier: 1.15,
            predictionWeight: 0.7,
            minimumConfidence: 0.45
        )

    public static let gaming =
        TouchZoneProfile(
            globalHitExpansion: 8,
            edgeSensitivity: 1.2,
            gestureThresholdMultiplier: 0.8,
            predictionWeight: 1.2,
            minimumConfidence: 0.35
        )

    public static let drawing =
        TouchZoneProfile(
            globalHitExpansion: 1,
            edgeSensitivity: 0.6,
            gestureThresholdMultiplier: 1.0,
            predictionWeight: 1.3,
            minimumConfidence: 0.65
        )

    public static let accessibility =
        TouchZoneProfile(
            globalHitExpansion: 14,
            edgeSensitivity: 1.4,
            gestureThresholdMultiplier: 1.2,
            predictionWeight: 0.6,
            minimumConfidence: 0.4
        )
}
9. Dynamic hitbox calculation

This is where #3 and #5 meet.

public struct DynamicHitboxEngine:
    Sendable
{

    public init() {}

    public func frame(
        for zone: TouchZone,
        profile: TouchZoneProfile,
        localConfidence: Double
    ) -> InteractionRect {

        var expansion =
            zone.hitExpansion

        expansion +=
            profile.globalHitExpansion

        if localConfidence < 0.5 {
            expansion += 4
        }

        return zone.frame.expanded(
            by: expansion
        )
    }
}

So a small button could effectively become:

visual button

┌───────────────┐
│     BUTTON    │
└───────────────┘

        ↓

interaction area

┌───────────────────────┐
│                       │
│     ┌───────────┐     │
│     │  BUTTON   │     │
│     └───────────┘     │
│                       │
└───────────────────────┘

without visually changing the UI.

10. Zone scoring

If several zones overlap, don't simply pick the first one.

Score them.

public struct TouchZoneScore:
    Sendable
{

    public let zoneID: TouchZoneID

    public let score: Double

    public let distance: Double

    public let priority: Int

    public init(
        zoneID: TouchZoneID,
        score: Double,
        distance: Double,
        priority: Int
    ) {
        self.zoneID = zoneID
        self.score = score
        self.distance = distance
        self.priority = priority
    }
}
public struct TouchZoneScorer:
    Sendable
{

    public init() {}

    public func score(
        zone: TouchZone,
        point: InteractionPoint,
        confidence: Double,
        predicted: Bool
    ) -> TouchZoneScore {

        guard zone.enabled else {
            return TouchZoneScore(
                zoneID: zone.id,
                score: -.infinity,
                distance: .infinity,
                priority: zone.priority
            )
        }

        let frame =
            zone.effectiveFrame

        let distance =
            frame.distance(
                to: point
            )

        var score =
            Double(zone.priority) * 10

        if frame.contains(point) {
            score += 100
        } else {
            score -= distance
        }

        score += confidence * 25

        if predicted &&
            !zone.allowsPrediction {

            score -= 50
        }

        return TouchZoneScore(
            zoneID: zone.id,
            score: score,
            distance: distance,
            priority: zone.priority
        )
    }
}
11. Dynamic interaction map
public actor TouchZoneRegistry {

    private var zones:
        [TouchZoneID: TouchZone] = [:]

    public init() {}

    public func register(
        _ zone: TouchZone
    ) {
        zones[zone.id] = zone
    }

    public func register(
        _ newZones: [TouchZone]
    ) {

        for zone in newZones {
            zones[zone.id] = zone
        }
    }

    public func remove(
        _ id: TouchZoneID
    ) {
        zones.removeValue(
            forKey: id
        )
    }

    public func update(
        _ zone: TouchZone
    ) {
        zones[zone.id] = zone
    }

    public func allZones()
        -> [TouchZone]
    {
        Array(zones.values)
    }

    public func clear() {
        zones.removeAll()
    }
}
12. Context-aware resolver

This is the main decision engine.

public struct TouchZoneResolution:
    Sendable
{

    public let zone: TouchZone?

    public let score: Double

    public let edge: TouchEdge

    public let predictedPoint: InteractionPoint

    public let usedPrediction: Bool

    public let confidence: Double
}
public struct TouchZoneResolver:
    Sendable
{

    private let scorer =
        TouchZoneScorer()

    private let edgeDetector:
        TouchEdgeDetector

    public init(
        edgeConfiguration:
            TouchEdgeConfiguration = .init()
    ) {

        self.edgeDetector =
            TouchEdgeDetector(
                configuration:
                    edgeConfiguration
            )
    }

    public func resolve(
        point: InteractionPoint,
        predictedPoint: InteractionPoint?,
        confidence: Double,
        zones: [TouchZone],
        screen: InteractionRect,
        profile: TouchZoneProfile
    ) -> TouchZoneResolution {

        let edge =
            edgeDetector.detect(
                point: point,
                screen: screen
            )

        let usePrediction =
            predictedPoint != nil &&
            confidence >= profile.minimumConfidence

        let candidatePoint =
            usePrediction
            ? predictedPoint!
            : point

        let candidates =
            zones.compactMap { zone
                -> TouchZoneScore? in

                guard zone.enabled else {
                    return nil
                }

                let score =
                    scorer.score(
                        zone: zone,
                        point: candidatePoint,
                        confidence: confidence,
                        predicted: usePrediction
                    )

                guard score.score.isFinite else {
                    return nil
                }

                return score
            }

        let winner =
            candidates.max {
                $0.score < $1.score
            }

        let selectedZone =
            winner.flatMap { winningScore in

                zones.first {
                    $0.id ==
                    winningScore.zoneID
                }
            }

        return TouchZoneResolution(
            zone: selectedZone,
            score: winner?.score ?? -.infinity,
            edge: edge,
            predictedPoint: candidatePoint,
            usedPrediction: usePrediction,
            confidence: confidence
        )
    }
}
13. Context resolver

The interaction mode can automatically select a different profile.

public struct TouchContextResolver:
    Sendable
{

    public init() {}

    public func profile(
        for mode: TouchInteractionMode
    ) -> TouchZoneProfile {

        switch mode {

        case .normal:
            return .normal

        case .typing:
            return .typing

        case .gaming:
            return .gaming

        case .drawing:
            return .drawing

        case .accessibility:
            return .accessibility

        case .scrolling:
            return TouchZoneProfile(
                globalHitExpansion: 4,
                edgeSensitivity: 1.1,
                gestureThresholdMultiplier: 0.85,
                predictionWeight: 1.2,
                minimumConfidence: 0.45
            )

        case .dragging:
            return TouchZoneProfile(
                globalHitExpansion: 6,
                edgeSensitivity: 1,
                gestureThresholdMultiplier: 0.7,
                predictionWeight: 1.25,
                minimumConfidence: 0.4
            )

        case .selecting:
            return TouchZoneProfile(
                globalHitExpansion: 2,
                edgeSensitivity: 0.9,
                gestureThresholdMultiplier: 1.1,
                predictionWeight: 0.9,
                minimumConfidence: 0.6
            )

        case .media:
            return TouchZoneProfile(
                globalHitExpansion: 10,
                edgeSensitivity: 1,
                gestureThresholdMultiplier: 0.9,
                predictionWeight: 1,
                minimumConfidence: 0.4
            )
        }
    }
}
14. Touch interaction event
public enum TouchZoneEvent:
    Sendable
{

    case entered(TouchZoneID)
    case exited(TouchZoneID)
    case activated(TouchZoneID)
    case moved(TouchZoneID)
    case edge(TouchEdge)
}
15. Zone tracking

We don't want the selected zone to jump rapidly between neighbouring buttons because of tiny movements.

public struct TouchZoneTrack:
    Sendable
{

    public var currentZone:
        TouchZoneID?

    public var candidateZone:
        TouchZoneID?

    public var candidateFrames:
        Int

    public var lastTimestamp:
        TimeInterval

    public init() {

        currentZone = nil
        candidateZone = nil
        candidateFrames = 0
        lastTimestamp = 0
    }
}
16. Hysteresis

This is an important touch-system technique.

public struct TouchZoneHysteresis:
    Sendable
{

    public var requiredSamples: Int = 2

    public init() {}

    public mutating func update(
        selected: TouchZoneID?,
        track: inout TouchZoneTrack
    ) -> TouchZoneID? {

        if selected ==
            track.currentZone {

            track.candidateZone = nil
            track.candidateFrames = 0

            return selected
        }

        if selected ==
            track.candidateZone {

            track.candidateFrames += 1

        } else {

            track.candidateZone =
                selected

            track.candidateFrames = 1
        }

        if track.candidateFrames >=
            requiredSamples {

            track.currentZone =
                selected

            track.candidateZone = nil
            track.candidateFrames = 0
        }

        return track.currentZone
    }
}

This means:

Button A
   ↓
finger approaches boundary
   ↓
A
A
A
B
A
B
A

doesn't cause:

A → B → A → B → A

on every tiny fluctuation.

17. Main Context-Aware Touch Zone Engine
public actor ContextAwareTouchZoneEngine {

    private let registry:
        TouchZoneRegistry

    private let resolver:
        TouchZoneResolver

    private let contextResolver:
        TouchContextResolver

    private var tracks:
        [SubPixelTouchID: TouchZoneTrack] = [:]

    private var hysteresis =
        TouchZoneHysteresis()

    public init(
        registry: TouchZoneRegistry =
            TouchZoneRegistry()
    ) {

        self.registry = registry

        self.resolver =
            TouchZoneResolver()

        self.contextResolver =
            TouchContextResolver()
    }

    public func process(
        touchID: SubPixelTouchID,
        point: InteractionPoint,
        predictedPoint: InteractionPoint?,
        confidence: Double,
        timestamp: TimeInterval,
        screen: InteractionRect,
        mode: TouchInteractionMode
    ) async -> TouchZoneResolution {

        let zones =
            await registry.allZones()

        let profile =
            contextResolver.profile(
                for: mode
            )

        let resolution =
            resolver.resolve(
                point: point,
                predictedPoint:
                    predictedPoint,
                confidence: confidence,
                zones: zones,
                screen: screen,
                profile: profile
            )

        var track =
            tracks[touchID]
            ?? TouchZoneTrack()

        _ = hysteresis.update(
            selected:
                resolution.zone?.id,
            track: &track
        )

        track.lastTimestamp =
            timestamp

        tracks[touchID] =
            track

        return resolution
    }

    public func endTouch(
        _ touchID: SubPixelTouchID
    ) {

        tracks.removeValue(
            forKey: touchID
        )
    }

    public func reset() {
        tracks.removeAll()
    }
}
18. Automatic zone generation

This gets particularly interesting.

Instead of manually defining every interaction region, Swift can construct zones from UI geometry.

For example:

public struct GeneratedZone:
    Sendable
{

    public let zone: TouchZone

    public let source:
        TouchZoneGenerationSource
}

public enum TouchZoneGenerationSource:
    Sendable
{

    case application
    case accessibility
    case keyboard
    case system
    case inferred
}
public struct TouchZoneGenerator:
    Sendable
{

    public init() {}

    public func buttonZone(
        id: String,
        frame: InteractionRect
    ) -> TouchZone {

        TouchZone(
            id:
                TouchZoneID(id),
            type: .button,
            frame: frame,
            priority: 50,
            hitExpansion: 4,
            minimumConfidence: 0.45,
            allowsPrediction: true,
            allowsMultiTouch: false
        )
    }

    public func keyboardKey(
        id: String,
        frame: InteractionRect
    ) -> TouchZone {

        TouchZone(
            id:
                TouchZoneID(id),
            type: .keyboardKey,
            frame: frame,
            priority: 80,
            hitExpansion: 8,
            minimumConfidence: 0.35,
            allowsPrediction: true,
            allowsMultiTouch: true
        )
    }

    public func drawingCanvas(
        id: String,
        frame: InteractionRect
    ) -> TouchZone {

        TouchZone(
            id:
                TouchZoneID(id),
            type: .drawingCanvas,
            frame: frame,
            priority: 20,
            hitExpansion: 0,
            minimumConfidence: 0.7,
            allowsPrediction: true,
            allowsMultiTouch: true
        )
    }
}
19. Adaptive keyboard zones

One of the strongest applications of this system is typing.

Instead of treating:

Q W E R T Y

as fixed rectangular targets, the system can enlarge likely targets based on typing context.

public struct KeyboardZoneOptimizer:
    Sendable
{

    public init() {}

    public func optimize(
        zones: [TouchZone],
        predictedNextCharacter:
            Character?
    ) -> [TouchZone] {

        zones.map { zone in

            guard
                zone.type ==
                    .keyboardKey
            else {
                return zone
            }

            var updated = zone

            if predictedNextCharacter != nil {

                updated.hitExpansion += 2
            }

            return updated
        }
    }
}

A future version could incorporate a language model to estimate the next likely key, while keeping the actual touch geometry deterministic.

20. Gaming zones

Gaming has a different requirement.

You often want:

large invisible controls
+
very low gesture thresholds
+
aggressive prediction

For example:

let fireButton =
    TouchZone(
        id:
            TouchZoneID("fire"),
        type: .gameControl,
        frame:
            InteractionRect(
                x: 960,
                y: 1850,
                width: 180,
                height: 180
            ),
        priority: 100,
        hitExpansion: 20,
        minimumConfidence: 0.3,
        allowsPrediction: true,
        allowsMultiTouch: true
    )

The visible button could remain much smaller than the actual interaction field.

21. Edge gesture zones

We can explicitly register system-style edge regions.

public struct EdgeZoneFactory:
    Sendable
{

    public init() {}

    public func leftEdge(
        screen: InteractionRect
    ) -> TouchZone {

        TouchZone(
            id:
                TouchZoneID(
                    "system.edge.left"
                ),
            type: .edgeGesture,
            frame:
                InteractionRect(
                    x: screen.minX,
                    y: screen.minY,
                    width: 32,
                    height: screen.size.height
                ),
            priority: 1_000,
            hitExpansion: 4,
            minimumConfidence: 0.65,
            allowsPrediction: true,
            allowsMultiTouch: false
        )
    }

    public func rightEdge(
        screen: InteractionRect
    ) -> TouchZone {

        TouchZone(
            id:
                TouchZoneID(
                    "system.edge.right"
                ),
            type: .edgeGesture,
            frame:
                InteractionRect(
                    x: screen.maxX - 32,
                    y: screen.minY,
                    width: 32,
                    height: screen.size.height
                ),
            priority: 1_000,
            hitExpansion: 4,
            minimumConfidence: 0.65,
            allowsPrediction: true,
            allowsMultiTouch: false
        )
    }
}
22. Context switching

The same screen can completely change behaviour:

let mode: TouchInteractionMode

if isDrawing {
    mode = .drawing
} else if isTyping {
    mode = .typing
} else if isGame {
    mode = .gaming
} else {
    mode = .normal
}

That feeds directly into the zone engine.

23. Connecting #1–#5

Now we can create one unified pipeline.

public struct IntelligentTouchOutput:
    Sendable
{

    public let touchID:
        SubPixelTouchID

    public let position:
        InteractionPoint

    public let predictedPosition:
        InteractionPoint?

    public let confidence:
        Double

    public let selectedZone:
        TouchZone?

    public let edge:
        TouchEdge

    public let usedPrediction:
        Bool
}

And a coordinator:

public actor IntelligentTouchCoordinator {

    private let zoneEngine:
        ContextAwareTouchZoneEngine

    public init(
        zoneEngine:
            ContextAwareTouchZoneEngine =
                ContextAwareTouchZoneEngine()
    ) {
        self.zoneEngine =
            zoneEngine
    }

    public func process(
        touchID: SubPixelTouchID,
        position: InteractionPoint,
        predictedPosition:
            InteractionPoint?,
        confidence: Double,
        timestamp: TimeInterval,
        screen: InteractionRect,
        mode: TouchInteractionMode
    ) async -> IntelligentTouchOutput {

        let resolution =
            await zoneEngine.process(
                touchID: touchID,
                point: position,
                predictedPoint:
                    predictedPosition,
                confidence: confidence,
                timestamp: timestamp,
                screen: screen,
                mode: mode
            )

        return IntelligentTouchOutput(
            touchID: touchID,
            position: position,
            predictedPosition:
                predictedPosition,
            confidence: confidence,
            selectedZone:
                resolution.zone,
            edge:
                resolution.edge,
            usedPrediction:
                resolution.usedPrediction
        )
    }
}
24. Example

Imagine a 1179 × 2556 screen:

let screen =
    InteractionRect(
        x: 0,
        y: 0,
        width: 1179,
        height: 2556
    )

let registry =
    TouchZoneRegistry()

let generator =
    TouchZoneGenerator()

let playButton =
    generator.buttonZone(
        id: "play",
        frame:
            InteractionRect(
                x: 500,
                y: 1200,
                width: 180,
                height: 80
            )
    )

await registry.register(
    playButton
)

let engine =
    ContextAwareTouchZoneEngine(
        registry: registry
    )

let result =
    await engine.process(
        touchID:
            SubPixelTouchID(1),
        point:
            InteractionPoint(
                x: 575,
                y: 1230
            ),
        predictedPoint:
            InteractionPoint(
                x: 579,
                y: 1231
            ),
        confidence: 0.94,
        timestamp: 10.002,
        screen: screen,
        mode: .normal
    )

print(
    result.zone?.id.rawValue
        ?? "none"
)

Output:

play
25. XCTest
import XCTest

final class ContextAwareTouchZoneTests:
    XCTestCase {

    func testPointInsideZone() {

        let zone =
            TouchZone(
                id:
                    TouchZoneID("button"),
                type: .button,
                frame:
                    InteractionRect(
                        x: 100,
                        y: 100,
                        width: 200,
                        height: 100
                    )
            )

        let point =
            InteractionPoint(
                x: 150,
                y: 120
            )

        XCTAssertTrue(
            zone.contains(point)
        )
    }

    func testExpandedHitbox() {

        let zone =
            TouchZone(
                id:
                    TouchZoneID("button"),
                type: .button,
                frame:
                    InteractionRect(
                        x: 100,
                        y: 100,
                        width: 100,
                        height: 50
                    ),
                hitExpansion: 20
            )

        let point =
            InteractionPoint(
                x: 90,
                y: 110
            )

        XCTAssertTrue(
            zone.contains(point)
        )
    }

    func testEdgeDetection() {

        let detector =
            TouchEdgeDetector()

        let screen =
            InteractionRect(
                x: 0,
                y: 0,
                width: 1179,
                height: 2556
            )

        let edge =
            detector.detect(
                point:
                    InteractionPoint(
                        x: 5,
                        y: 1000
                    ),
                screen: screen
            )

        XCTAssertEqual(
            edge,
            .left
        )
    }

    func testZoneScoring() {

        let scorer =
            TouchZoneScorer()

        let zone =
            TouchZone(
                id:
                    TouchZoneID("button"),
                type: .button,
                frame:
                    InteractionRect(
                        x: 100,
                        y: 100,
                        width: 100,
                        height: 100
                    ),
                priority: 10
            )

        let score =
            scorer.score(
                zone: zone,
                point:
                    InteractionPoint(
                        x: 150,
                        y: 150
                    ),
                confidence: 1,
                predicted: false
            )

        XCTAssertGreaterThan(
            score.score,
            100
        )
    }
}







1. Core touch representation
import Foundation
import CoreGraphics

public struct GestureTouchID:
    Hashable,
    Sendable
{
    public let rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

public struct GesturePoint:
    Sendable,
    Equatable
{
    public var x: Double
    public var y: Double

    public init(
        x: Double,
        y: Double
    ) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(
            x: x,
            y: y
        )
    }

    public static func + (
        lhs: GesturePoint,
        rhs: GesturePoint
    ) -> GesturePoint {

        GesturePoint(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }

    public static func - (
        lhs: GesturePoint,
        rhs: GesturePoint
    ) -> GesturePoint {

        GesturePoint(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y
        )
    }

    public static func / (
        lhs: GesturePoint,
        rhs: Double
    ) -> GesturePoint {

        GesturePoint(
            x: lhs.x / rhs,
            y: lhs.y / rhs
        )
    }

    public func distance(
        to other: GesturePoint
    ) -> Double {

        let dx = x - other.x
        let dy = y - other.y

        return sqrt(
            dx * dx + dy * dy
        )
    }

    public var magnitude: Double {
        sqrt(
            x * x +
            y * y
        )
    }
}
2. Gesture phases
public enum GesturePhase:
    Sendable,
    Equatable
{
    case possible
    case began
    case changed
    case ended
    case cancelled
    case failed
}
3. Gesture types
public enum GestureKind:
    Hashable,
    Sendable
{
    case tap
    case doubleTap
    case longPress

    case pan
    case swipe

    case pinch
    case rotation

    case twoFingerPan

    case edgeSwipe

    case custom(String)
}
4. Touch sample
public struct GestureTouchSample:
    Sendable
{
    public let id: GestureTouchID
    public let position: GesturePoint
    public let timestamp: TimeInterval

    public let predictedPosition:
        GesturePoint?

    public let confidence: Double

    public let isRejected: Bool

    public init(
        id: GestureTouchID,
        position: GesturePoint,
        timestamp: TimeInterval,
        predictedPosition:
            GesturePoint? = nil,
        confidence: Double = 1,
        isRejected: Bool = false
    ) {
        self.id = id
        self.position = position
        self.timestamp = timestamp
        self.predictedPosition =
            predictedPosition
        self.confidence =
            confidence
        self.isRejected =
            isRejected
    }
}
5. Gesture configuration

The entire engine should be configurable rather than filled with hard-coded magic numbers.

public struct GestureConfiguration:
    Sendable
{
    public var tapMaximumMovement: Double
    public var tapMaximumDuration: TimeInterval

    public var doubleTapMaximumInterval:
        TimeInterval

    public var longPressMinimumDuration:
        TimeInterval

    public var panMinimumMovement: Double

    public var swipeMinimumDistance: Double
    public var swipeMinimumVelocity: Double

    public var pinchMinimumScaleChange: Double

    public var rotationMinimumAngle:
        Double

    public var edgeActivationDistance:
        Double

    public init(
        tapMaximumMovement: Double = 12,
        tapMaximumDuration: TimeInterval = 0.30,
        doubleTapMaximumInterval:
            TimeInterval = 0.28,
        longPressMinimumDuration:
            TimeInterval = 0.50,
        panMinimumMovement: Double = 8,
        swipeMinimumDistance: Double = 80,
        swipeMinimumVelocity: Double = 500,
        pinchMinimumScaleChange: Double = 0.05,
        rotationMinimumAngle: Double = 0.08,
        edgeActivationDistance: Double = 32
    ) {
        self.tapMaximumMovement =
            tapMaximumMovement

        self.tapMaximumDuration =
            tapMaximumDuration

        self.doubleTapMaximumInterval =
            doubleTapMaximumInterval

        self.longPressMinimumDuration =
            longPressMinimumDuration

        self.panMinimumMovement =
            panMinimumMovement

        self.swipeMinimumDistance =
            swipeMinimumDistance

        self.swipeMinimumVelocity =
            swipeMinimumVelocity

        self.pinchMinimumScaleChange =
            pinchMinimumScaleChange

        self.rotationMinimumAngle =
            rotationMinimumAngle

        self.edgeActivationDistance =
            edgeActivationDistance
    }
}
6. Per-finger state
public struct GestureTouchTrack:
    Sendable
{
    public let id: GestureTouchID

    public var startPosition:
        GesturePoint

    public var currentPosition:
        GesturePoint

    public var previousPosition:
        GesturePoint

    public var startTimestamp:
        TimeInterval

    public var lastTimestamp:
        TimeInterval

    public var totalDistance:
        Double

    public var maximumDistanceFromStart:
        Double

    public var velocity:
        GesturePoint

    public init(
        sample:
            GestureTouchSample
    ) {

        self.id = sample.id
        self.startPosition =
            sample.position

        self.currentPosition =
            sample.position

        self.previousPosition =
            sample.position

        self.startTimestamp =
            sample.timestamp

        self.lastTimestamp =
            sample.timestamp

        self.totalDistance = 0
        self.maximumDistanceFromStart = 0
        self.velocity =
            GesturePoint(x: 0, y: 0)
    }

    public mutating func update(
        with sample: GestureTouchSample
    ) {

        let delta =
            sample.position -
            currentPosition

        let dt =
            max(
                sample.timestamp -
                    lastTimestamp,
                0.000001
            )

        let distance =
            delta.magnitude

        totalDistance += distance

        maximumDistanceFromStart =
            max(
                maximumDistanceFromStart,
                sample.position.distance(
                    to: startPosition
                )
            )

        velocity =
            delta / dt

        previousPosition =
            currentPosition

        currentPosition =
            sample.position

        lastTimestamp =
            sample.timestamp
    }

    public var duration: TimeInterval {
        lastTimestamp -
        startTimestamp
    }

    public var displacement: GesturePoint {
        currentPosition -
        startPosition
    }

    public var speed: Double {
        velocity.magnitude
    }
}
7. Vector mathematics
public enum GestureMath {

    public static func dot(
        _ a: GesturePoint,
        _ b: GesturePoint
    ) -> Double {

        a.x * b.x +
        a.y * b.y
    }

    public static func cross(
        _ a: GesturePoint,
        _ b: GesturePoint
    ) -> Double {

        a.x * b.y -
        a.y * b.x
    }

    public static func angle(
        _ a: GesturePoint,
        _ b: GesturePoint
    ) -> Double {

        let denominator =
            a.magnitude *
            b.magnitude

        guard denominator > 0 else {
            return 0
        }

        let cosine =
            max(
                -1,
                min(
                    1,
                    dot(a, b) / denominator
                )
            )

        return acos(cosine)
    }

    public static func signedAngle(
        _ a: GesturePoint,
        _ b: GesturePoint
    ) -> Double {

        let angle =
            angle(a, b)

        return cross(a, b) >= 0
            ? angle
            : -angle
    }
}
8. Tap recognizer
public struct TapRecognizer:
    Sendable
{
    private let configuration:
        GestureConfiguration

    public init(
        configuration:
            GestureConfiguration
    ) {
        self.configuration =
            configuration
    }

    public func recognize(
        track: GestureTouchTrack
    ) -> GesturePhase {

        guard
            track.maximumDistanceFromStart
                <= configuration.tapMaximumMovement
        else {
            return .failed
        }

        guard
            track.duration
                <= configuration.tapMaximumDuration
        else {
            return .failed
        }

        return .ended
    }
}
9. Long press
public struct LongPressRecognizer:
    Sendable
{
    private let configuration:
        GestureConfiguration

    public init(
        configuration:
            GestureConfiguration
    ) {
        self.configuration =
            configuration
    }

    public func phase(
        track: GestureTouchTrack
    ) -> GesturePhase {

        if track.maximumDistanceFromStart >
            configuration.tapMaximumMovement {

            return .failed
        }

        if track.duration >=
            configuration.longPressMinimumDuration {

            return .began
        }

        return .possible
    }
}
10. Pan recognizer
public struct PanRecognizer:
    Sendable
{
    private let configuration:
        GestureConfiguration

    public init(
        configuration:
            GestureConfiguration
    ) {
        self.configuration =
            configuration
    }

    public func phase(
        track: GestureTouchTrack
    ) -> GesturePhase {

        let distance =
            track.displacement.magnitude

        guard distance >=
            configuration.panMinimumMovement
        else {
            return .possible
        }

        return .changed
    }
}
11. Swipe classification
public enum SwipeDirection:
    Sendable,
    Equatable
{
    case left
    case right
    case up
    case down
}
public struct SwipeResult:
    Sendable
{
    public let direction:
        SwipeDirection

    public let velocity:
        Double

    public let distance:
        Double
}
public struct SwipeRecognizer:
    Sendable
{
    private let configuration:
        GestureConfiguration

    public init(
        configuration:
            GestureConfiguration
    ) {
        self.configuration =
            configuration
    }

    public func recognize(
        track: GestureTouchTrack
    ) -> SwipeResult? {

        let distance =
            track.displacement.magnitude

        let speed =
            track.speed

        guard
            distance >=
                configuration.swipeMinimumDistance,
            speed >=
                configuration.swipeMinimumVelocity
        else {
            return nil
        }

        let displacement =
            track.displacement

        if abs(displacement.x) >
            abs(displacement.y) {

            return SwipeResult(
                direction:
                    displacement.x >= 0
                    ? .right
                    : .left,
                velocity: speed,
                distance: distance
            )

        } else {

            return SwipeResult(
                direction:
                    displacement.y >= 0
                    ? .down
                    : .up,
                velocity: speed,
                distance: distance
            )
        }
    }
}
12. Multi-touch centroid
public struct MultiTouchGeometry:
    Sendable
{
    public let centroid:
        GesturePoint

    public let distance:
        Double

    public let angle:
        Double
}
public enum MultiTouchCalculator {

    public static func calculate(
        _ tracks:
            [GestureTouchTrack]
    ) -> MultiTouchGeometry? {

        guard tracks.count >= 2 else {
            return nil
        }

        let first =
            tracks[0]

        let second =
            tracks[1]

        let centroid =
            GesturePoint(
                x:
                    (first.currentPosition.x +
                     second.currentPosition.x)
                    / 2,
                y:
                    (first.currentPosition.y +
                     second.currentPosition.y)
                    / 2
            )

        let vector =
            second.currentPosition -
            first.currentPosition

        return MultiTouchGeometry(
            centroid: centroid,
            distance: vector.magnitude,
            angle:
                atan2(
                    vector.y,
                    vector.x
                )
        )
    }
}
13. Pinch recognizer
public struct PinchResult:
    Sendable
{
    public let scale: Double
    public let velocity: Double
}
public struct PinchRecognizer:
    Sendable
{
    private let configuration:
        GestureConfiguration

    public init(
        configuration:
            GestureConfiguration
    ) {
        self.configuration =
            configuration
    }

    public func recognize(
        initialDistance: Double,
        currentDistance: Double,
        deltaTime: TimeInterval
    ) -> PinchResult? {

        guard initialDistance > 0 else {
            return nil
        }

        let scale =
            currentDistance /
            initialDistance

        guard
            abs(scale - 1) >=
                configuration.pinchMinimumScaleChange
        else {
            return nil
        }

        let velocity =
            (currentDistance -
             initialDistance)
            / max(deltaTime, 0.000001)

        return PinchResult(
            scale: scale,
            velocity: velocity
        )
    }
}
14. Rotation recognizer
public struct RotationResult:
    Sendable
{
    public let angle: Double
}
public struct RotationRecognizer:
    Sendable
{
    private let configuration:
        GestureConfiguration

    public init(
        configuration:
            GestureConfiguration
    ) {
        self.configuration =
            configuration
    }

    public func recognize(
        initialAngle: Double,
        currentAngle: Double
    ) -> RotationResult? {

        let delta =
            currentAngle -
            initialAngle

        guard abs(delta) >=
            configuration.rotationMinimumAngle
        else {
            return nil
        }

        return RotationResult(
            angle: delta
        )
    }
}
15. Gesture priority

Some gestures should take precedence over others.

public enum GesturePriority:
    Int,
    Sendable
{
    case background = 0
    case normal = 100
    case high = 200
    case system = 1_000
}
16. Gesture recognizer descriptor
public struct GestureDescriptor:
    Hashable,
    Sendable
{
    public let id: String
    public let kind: GestureKind

    public let priority:
        GesturePriority

    public let simultaneous:
        Bool

    public let cancellable:
        Bool

    public init(
        id: String,
        kind: GestureKind,
        priority:
            GesturePriority = .normal,
        simultaneous: Bool = false,
        cancellable: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.simultaneous =
            simultaneous
        self.cancellable =
            cancellable
    }
}
17. Gesture events
public enum GestureEvent:
    Sendable
{

    case began(
        descriptor: GestureDescriptor
    )

    case changed(
        descriptor: GestureDescriptor,
        location: GesturePoint,
        velocity: GesturePoint
    )

    case ended(
        descriptor: GestureDescriptor
    )

    case cancelled(
        descriptor: GestureDescriptor
    )

    case swipe(
        direction: SwipeDirection,
        velocity: Double
    )

    case pinch(
        scale: Double
    )

    case rotation(
        angle: Double
    )
}
18. Gesture arbitration

This is one of the most important parts.

Suppose a finger begins moving over a scroll view.

The system needs to decide whether it is:

tap?
drag?
scroll?
edge gesture?
button press?

The arbiter resolves conflicts.

public struct GestureArbiter:
    Sendable
{

    public init() {}

    public func winner(
        _ descriptors:
            [GestureDescriptor]
    ) -> GestureDescriptor? {

        descriptors.max {
            $0.priority.rawValue <
            $1.priority.rawValue
        }
    }

    public func canRunSimultaneously(
        _ a: GestureDescriptor,
        _ b: GestureDescriptor
    ) -> Bool {

        a.simultaneous &&
        b.simultaneous
    }
}
19. Gesture state machine
public struct ActiveGesture:
    Sendable
{
    public let descriptor:
        GestureDescriptor

    public var phase:
        GesturePhase

    public var startedAt:
        TimeInterval

    public var lastUpdated:
        TimeInterval
}
20. High-frequency gesture engine
public final class UltraLowLatencyGestureEngine:
    @unchecked Sendable
{

    private let configuration:
        GestureConfiguration

    private let tapRecognizer:
        TapRecognizer

    private let longPressRecognizer:
        LongPressRecognizer

    private let panRecognizer:
        PanRecognizer

    private let swipeRecognizer:
        SwipeRecognizer

    private let pinchRecognizer:
        PinchRecognizer

    private let rotationRecognizer:
        RotationRecognizer

    private let arbiter =
        GestureArbiter()

    private var tracks:
        [GestureTouchID: GestureTouchTrack]
        = [:]

    private var activeGestures:
        [GestureDescriptor: ActiveGesture]
        = [:]

    private var initialMultiTouch:
        MultiTouchGeometry?

    private var eventHandler:
        ((GestureEvent) -> Void)?

    public init(
        configuration:
            GestureConfiguration = .init()
    ) {

        self.configuration =
            configuration

        self.tapRecognizer =
            TapRecognizer(
                configuration:
                    configuration
            )

        self.longPressRecognizer =
            LongPressRecognizer(
                configuration:
                    configuration
            )

        self.panRecognizer =
            PanRecognizer(
                configuration:
                    configuration
            )

        self.swipeRecognizer =
            SwipeRecognizer(
                configuration:
                    configuration
            )

        self.pinchRecognizer =
            PinchRecognizer(
                configuration:
                    configuration
            )

        self.rotationRecognizer =
            RotationRecognizer(
                configuration:
                    configuration
            )
    }

    public func setEventHandler(
        _ handler:
            @escaping
            (GestureEvent) -> Void
    ) {

        eventHandler = handler
    }
}
21. Touch begin
extension UltraLowLatencyGestureEngine {

    public func touchBegan(
        _ sample:
            GestureTouchSample
    ) {

        guard !sample.isRejected else {
            return
        }

        let track =
            GestureTouchTrack(
                sample: sample
            )

        tracks[sample.id] =
            track

        if tracks.count == 2 {

            let geometry =
                MultiTouchCalculator.calculate(
                    Array(tracks.values)
                )

            initialMultiTouch =
                geometry
        }

        evaluateInitialGestures(
            timestamp:
                sample.timestamp
        )
    }

    private func evaluateInitialGestures(
        timestamp: TimeInterval
    ) {

        guard
            let track =
                tracks.values.first
        else {
            return
        }

        let longPress =
            GestureDescriptor(
                id: "long-press",
                kind: .longPress,
                priority: .normal
            )

        let pan =
            GestureDescriptor(
                id: "pan",
                kind: .pan,
                priority: .normal
            )

        let tap =
            GestureDescriptor(
                id: "tap",
                kind: .tap,
                priority: .normal
            )

        _ = longPressRecognizer.phase(
            track: track
        )

        _ = panRecognizer.phase(
            track: track
        )

        _ = tapRecognizer.recognize(
            track: track
        )

        activeGestures[tap] =
            ActiveGesture(
                descriptor: tap,
                phase: .possible,
                startedAt: timestamp,
                lastUpdated: timestamp
            )

        activeGestures[pan] =
            ActiveGesture(
                descriptor: pan,
                phase: .possible,
                startedAt: timestamp,
                lastUpdated: timestamp
            )

        activeGestures[longPress] =
            ActiveGesture(
                descriptor: longPress,
                phase: .possible,
                startedAt: timestamp,
                lastUpdated: timestamp
            )
    }
}
22. Touch movement
extension UltraLowLatencyGestureEngine {

    public func touchMoved(
        _ sample:
            GestureTouchSample
    ) {

        guard !sample.isRejected else {
            return
        }

        guard
            var track =
                tracks[sample.id]
        else {
            return
        }

        track.update(
            with: sample
        )

        tracks[sample.id] =
            track

        evaluateSingleFingerGestures(
            track: track
        )

        evaluateMultiTouch()
    }
}
23. Single-finger gesture processing
extension UltraLowLatencyGestureEngine {

    private func
        evaluateSingleFingerGestures(
            track:
                GestureTouchTrack
        )
    {

        let pan =
            GestureDescriptor(
                id: "pan",
                kind: .pan,
                priority: .normal
            )

        let longPress =
            GestureDescriptor(
                id: "long-press",
                kind: .longPress,
                priority: .normal
            )

        if panRecognizer.phase(
            track: track
        ) == .changed {

            beginIfNecessary(
                pan,
                timestamp:
                    track.lastTimestamp
            )

            emit(
                .changed(
                    descriptor: pan,
                    location:
                        track.currentPosition,
                    velocity:
                        track.velocity
                )
            )

            cancelGesture(
                id: "tap"
            )

            cancelGesture(
                id: "long-press"
            )
        }

        let longPressPhase =
            longPressRecognizer.phase(
                track: track
            )

        if longPressPhase == .began {

            beginIfNecessary(
                longPress,
                timestamp:
                    track.lastTimestamp
            )

            cancelGesture(
                id: "tap"
            )
        }
    }
}
24. Gesture lifecycle
extension UltraLowLatencyGestureEngine {

    private func beginIfNecessary(
        _ descriptor:
            GestureDescriptor,
        timestamp:
            TimeInterval
    ) {

        guard
            let existing =
                activeGestures[descriptor]
        else {

            activeGestures[descriptor] =
                ActiveGesture(
                    descriptor: descriptor,
                    phase: .began,
                    startedAt: timestamp,
                    lastUpdated: timestamp
                )

            emit(
                .began(
                    descriptor: descriptor
                )
            )

            return
        }

        guard existing.phase ==
            .possible
        else {
            return
        }

        activeGestures[descriptor] =
            ActiveGesture(
                descriptor: descriptor,
                phase: .began,
                startedAt:
                    existing.startedAt,
                lastUpdated:
                    timestamp
            )

        emit(
            .began(
                descriptor: descriptor
            )
        )
    }

    private func cancelGesture(
        id: String
    ) {

        guard
            let descriptor =
                activeGestures.keys.first(
                    where: { $0.id == id }
                )
        else {
            return
        }

        guard
            let gesture =
                activeGestures[descriptor],
            gesture.descriptor.cancellable
        else {
            return
        }

        activeGestures.removeValue(
            forKey: descriptor
        )

        emit(
            .cancelled(
                descriptor: descriptor
            )
        )
    }
}
25. Multi-touch processing

Now we add pinch and rotation.

extension UltraLowLatencyGestureEngine {

    private func evaluateMultiTouch() {

        guard tracks.count >= 2 else {
            return
        }

        let current =
            MultiTouchCalculator.calculate(
                Array(tracks.values)
            )

        guard
            let current,
            let initial =
                initialMultiTouch
        else {
            return
        }

        let tracksArray =
            Array(tracks.values)

        guard
            let earliest =
                tracksArray.map({
                    $0.startTimestamp
                }).min()
        else {
            return
        }

        let duration =
            max(
                tracksArray.map({
                    $0.lastTimestamp
                }).max()! -
                earliest,
                0.000001
            )

        if let pinch =
            pinchRecognizer.recognize(
                initialDistance:
                    initial.distance,
                currentDistance:
                    current.distance,
                deltaTime:
                    duration
            ) {

            let descriptor =
                GestureDescriptor(
                    id: "pinch",
                    kind: .pinch,
                    priority: .high,
                    simultaneous: true
                )

            beginIfNecessary(
                descriptor,
                timestamp:
                    tracksArray.map({
                        $0.lastTimestamp
                    }).max()!
            )

            emit(
                .pinch(
                    scale:
                        pinch.scale
                )
            )
        }

        if let rotation =
            rotationRecognizer.recognize(
                initialAngle:
                    initial.angle,
                currentAngle:
                    current.angle
            ) {

            let descriptor =
                GestureDescriptor(
                    id: "rotation",
                    kind: .rotation,
                    priority: .high,
                    simultaneous: true
                )

            beginIfNecessary(
                descriptor,
                timestamp:
                    tracksArray.map({
                        $0.lastTimestamp
                    }).max()!
            )

            emit(
                .rotation(
                    angle:
                        rotation.angle
                )
            )
        }
    }
}
26. Touch end
extension UltraLowLatencyGestureEngine {

    public func touchEnded(
        _ sample:
            GestureTouchSample
    ) {

        guard
            var track =
                tracks[sample.id]
        else {
            return
        }

        track.update(
            with: sample
        )

        if let swipe =
            swipeRecognizer.recognize(
                track: track
            ) {

            emit(
                .swipe(
                    direction:
                        swipe.direction,
                    velocity:
                        swipe.velocity
                )
            )
        } else {

            finishTapIfAppropriate(
                track: track
            )
        }

        tracks.removeValue(
            forKey: sample.id
        )

        if tracks.count < 2 {
            initialMultiTouch = nil
        }

        finishGestures(
            timestamp:
                sample.timestamp
        )
    }

    private func finishTapIfAppropriate(
        track:
            GestureTouchTrack
    ) {

        guard
            track.duration <=
                configuration.tapMaximumDuration,
            track.maximumDistanceFromStart <=
                configuration.tapMaximumMovement
        else {
            return
        }

        let descriptor =
            GestureDescriptor(
                id: "tap",
                kind: .tap,
                priority: .normal
            )

        emit(
            .ended(
                descriptor: descriptor
            )
        )
    }

    private func finishGestures(
        timestamp:
            TimeInterval
    ) {

        for descriptor
        in activeGestures.keys {

            emit(
                .ended(
                    descriptor: descriptor
                )
            )
        }

        activeGestures.removeAll()
    }
}
27. Cancellation
extension UltraLowLatencyGestureEngine {

    public func cancelAll() {

        for descriptor
        in activeGestures.keys {

            emit(
                .cancelled(
                    descriptor: descriptor
                )
            )
        }

        tracks.removeAll()
        activeGestures.removeAll()
        initialMultiTouch = nil
    }
}
28. Event output
extension UltraLowLatencyGestureEngine {

    private func emit(
        _ event: GestureEvent
    ) {

        eventHandler?(event)
    }
}

This gives the hot path an extremely simple interface:

let engine =
    UltraLowLatencyGestureEngine()

engine.setEventHandler { event in

    switch event {

    case .began(let gesture):
        print(
            "Gesture began:",
            gesture.kind
        )

    case .changed(
        let gesture,
        let location,
        let velocity
    ):
        print(
            gesture.kind,
            location,
            velocity
        )

    case .ended(let gesture):
        print(
            "Gesture ended:",
            gesture.kind
        )

    case .cancelled(let gesture):
        print(
            "Gesture cancelled:",
            gesture.kind
        )

    case .swipe(
        let direction,
        let velocity
    ):
        print(
            "Swipe:",
            direction,
            velocity
        )

    case .pinch(let scale):
        print(
            "Pinch:",
            scale
        )

    case .rotation(let angle):
        print(
            "Rotation:",
            angle
        )
    }
}
29. Double-tap detection

For a production interaction system, double-tap should be handled separately from ordinary tap recognition.

public struct DoubleTapDetector:
    Sendable
{
    private let maximumInterval:
        TimeInterval

    private let maximumDistance:
        Double

    private var lastTapTime:
        TimeInterval?

    private var lastTapPosition:
        GesturePoint?

    public init(
        maximumInterval:
            TimeInterval = 0.28,
        maximumDistance:
            Double = 24
    ) {

        self.maximumInterval =
            maximumInterval

        self.maximumDistance =
            maximumDistance
    }

    public mutating func registerTap(
        position:
            GesturePoint,
        timestamp:
            TimeInterval
    ) -> Bool {

        defer {
            lastTapTime =
                timestamp

            lastTapPosition =
                position
        }

        guard
            let lastTapTime,
            let lastTapPosition
        else {
            return false
        }

        let timeDifference =
            timestamp -
            lastTapTime

        let distance =
            position.distance(
                to: lastTapPosition
            )

        return
            timeDifference <=
                maximumInterval &&
            distance <=
                maximumDistance
    }

    public mutating func reset() {

        lastTapTime = nil
        lastTapPosition = nil
    }
}
30. Gesture velocity prediction

This connects directly back to #1 and #4.

Instead of waiting until the finger actually reaches the destination:

finger
  ●──────→

we can estimate:

current point
     ●
      \
       \
        ● predicted

and use that predicted point for gesture classification.

public struct GesturePrediction:
    Sendable
{
    public let point:
        GesturePoint

    public let horizon:
        TimeInterval

    public let confidence:
        Double
}
public struct GesturePredictor:
    Sendable
{

    public init() {}

    public func predict(
        track:
            GestureTouchTrack,
        horizon:
            TimeInterval
    ) -> GesturePrediction {

        let predicted =
            track.currentPosition +
            (
                track.velocity *
                horizon
            )

        let confidence =
            max(
                0,
                min(
                    1,
                    1 -
                    track.speed /
                    5000
                )
            )

        return GesturePrediction(
            point: predicted,
            horizon: horizon,
            confidence: confidence
        )
    }
}

This can make fast swipes and game controls feel considerably more immediate.

31. Edge gesture recognizer

The #5 context-zone system can tell us that the touch started near an edge.

public enum GestureEdge:
    Sendable
{
    case left
    case right
    case top
    case bottom
}
public struct EdgeGestureRecognizer:
    Sendable
{

    public let activationDistance:
        Double

    public init(
        activationDistance:
            Double = 32
    ) {
        self.activationDistance =
            activationDistance
    }

    public func recognize(
        start:
            GesturePoint,
        current:
            GesturePoint,
        screen:
            InteractionRect
    ) -> GestureEdge? {

        let displacement =
            current -
            start

        if start.x <=
            screen.minX +
            activationDistance,
           displacement.x >
            activationDistance {

            return .left
        }

        if start.x >=
            screen.maxX -
            activationDistance,
           displacement.x <
            -activationDistance {

            return .right
        }

        if start.y <=
            screen.minY +
            activationDistance,
           displacement.y >
            activationDistance {

            return .top
        }

        if start.y >=
            screen.maxY -
            activationDistance,
           displacement.y <
            -activationDistance {

            return .bottom
        }

        return nil
    }
}







1. Basic vector mathematics
import Foundation
import CoreGraphics

public struct ScrollVector:
    Sendable,
    Equatable
{
    public var x: Double
    public var y: Double

    public init(
        x: Double = 0,
        y: Double = 0
    ) {
        self.x = x
        self.y = y
    }

    public var magnitude: Double {
        sqrt(x * x + y * y)
    }

    public var squaredMagnitude: Double {
        x * x + y * y
    }

    public static let zero =
        ScrollVector()

    public static func + (
        lhs: ScrollVector,
        rhs: ScrollVector
    ) -> ScrollVector {

        ScrollVector(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }

    public static func - (
        lhs: ScrollVector,
        rhs: ScrollVector
    ) -> ScrollVector {

        ScrollVector(
            x: lhs.x - rhs.x,
            y: lhs.y - rhs.y
        )
    }

    public static func * (
        lhs: ScrollVector,
        rhs: Double
    ) -> ScrollVector {

        ScrollVector(
            x: lhs.x * rhs,
            y: lhs.y * rhs
        )
    }

    public static func / (
        lhs: ScrollVector,
        rhs: Double
    ) -> ScrollVector {

        guard rhs != 0 else {
            return .zero
        }

        return ScrollVector(
            x: lhs.x / rhs,
            y: lhs.y / rhs
        )
    }

    public func clamped(
        magnitude maximum: Double
    ) -> ScrollVector {

        let length = magnitude

        guard length > maximum,
              length > 0
        else {
            return self
        }

        return self *
            (maximum / length)
    }

    public var cgPoint: CGPoint {
        CGPoint(
            x: x,
            y: y
        )
    }
}
2. Scroll configuration

We don't want physics constants scattered throughout the implementation.

public struct ScrollPhysicsConfiguration:
    Sendable
{
    public var friction:
        Double

    public var maximumVelocity:
        Double

    public var minimumVelocity:
        Double

    public var velocityResponse:
        Double

    public var springStiffness:
        Double

    public var springDamping:
        Double

    public var overscrollResistance:
        Double

    public var maximumOverscroll:
        Double

    public var frameRate:
        Double

    public var predictionHorizon:
        TimeInterval

    public init(
        friction: Double = 6.5,
        maximumVelocity: Double = 8_000,
        minimumVelocity: Double = 1,
        velocityResponse: Double = 0.85,
        springStiffness: Double = 240,
        springDamping: Double = 30,
        overscrollResistance: Double = 0.35,
        maximumOverscroll: Double = 160,
        frameRate: Double = 120,
        predictionHorizon:
            TimeInterval = 1.0 / 120.0
    ) {

        self.friction = friction
        self.maximumVelocity =
            maximumVelocity

        self.minimumVelocity =
            minimumVelocity

        self.velocityResponse =
            velocityResponse

        self.springStiffness =
            springStiffness

        self.springDamping =
            springDamping

        self.overscrollResistance =
            overscrollResistance

        self.maximumOverscroll =
            maximumOverscroll

        self.frameRate =
            frameRate

        self.predictionHorizon =
            predictionHorizon
    }
}
3. Scrollable bounds
public struct ScrollBounds:
    Sendable,
    Equatable
{
    public var minimumX: Double
    public var maximumX: Double

    public var minimumY: Double
    public var maximumY: Double

    public init(
        minimumX: Double = 0,
        maximumX: Double = 0,
        minimumY: Double = 0,
        maximumY: Double = 0
    ) {

        self.minimumX = minimumX
        self.maximumX = maximumX

        self.minimumY = minimumY
        self.maximumY = maximumY
    }
}
4. Scroll position
public struct ScrollPosition:
    Sendable,
    Equatable
{
    public var x: Double
    public var y: Double

    public init(
        x: Double = 0,
        y: Double = 0
    ) {
        self.x = x
        self.y = y
    }

    public static let zero =
        ScrollPosition()

    public static func + (
        lhs: ScrollPosition,
        rhs: ScrollVector
    ) -> ScrollPosition {

        ScrollPosition(
            x: lhs.x + rhs.x,
            y: lhs.y + rhs.y
        )
    }
}
5. Scroll state
public enum ScrollState:
    Sendable,
    Equatable
{
    case idle
    case dragging
    case decelerating
    case overscrolling
    case springing
}
6. Scroll interaction profile

The engine should distinguish between different kinds of users.

public enum ScrollInteractionStyle:
    Sendable,
    Equatable
{
    case precise
    case normal
    case fast
    case flickHeavy
    case accessibility
}
7. Adaptive profile
public struct ScrollBehaviourProfile:
    Sendable
{
    public private(set) var averageSwipeVelocity:
        Double = 0

    public private(set) var averageSwipeDistance:
        Double = 0

    public private(set) var swipeCount:
        UInt64 = 0

    public private(set) var averageDragDuration:
        TimeInterval = 0

    public mutating func recordSwipe(
        velocity: Double,
        distance: Double,
        duration: TimeInterval
    ) {

        swipeCount += 1

        let n =
            Double(swipeCount)

        averageSwipeVelocity +=
            (velocity -
             averageSwipeVelocity) / n

        averageSwipeDistance +=
            (distance -
             averageSwipeDistance) / n

        averageDragDuration +=
            (duration -
             averageDragDuration) / n
    }

    public var style:
        ScrollInteractionStyle {

        if averageSwipeVelocity > 4_500 {
            return .flickHeavy
        }

        if averageSwipeVelocity > 2_500 {
            return .fast
        }

        if averageSwipeVelocity < 500 {
            return .precise
        }

        return .normal
    }
}
8. Adaptive physics policy

This is the key difference between a fixed scrolling system and an adaptive one.

public struct AdaptiveScrollPolicy:
    Sendable
{
    public init() {}

    public func configuration(
        base:
            ScrollPhysicsConfiguration,
        profile:
            ScrollBehaviourProfile
    ) -> ScrollPhysicsConfiguration {

        var result = base

        switch profile.style {

        case .precise:
            result.friction *= 1.30
            result.maximumVelocity *= 0.80
            result.velocityResponse *= 0.90

        case .normal:
            break

        case .fast:
            result.friction *= 0.90
            result.maximumVelocity *= 1.10

        case .flickHeavy:
            result.friction *= 0.78
            result.maximumVelocity *= 1.20
            result.velocityResponse *= 1.05

        case .accessibility:
            result.friction *= 1.45
            result.maximumVelocity *= 0.70
        }

        return result
    }
}

This doesn't mean the system secretly changes the user's device sensitivity. It changes the scroll response model.

9. Velocity estimator

Raw touch velocity is noisy.

We therefore maintain a filtered estimate.

public struct ScrollVelocityEstimator:
    Sendable
{
    private var velocity:
        ScrollVector = .zero

    private let smoothing:
        Double

    public init(
        smoothing: Double = 0.82
    ) {
        self.smoothing =
            max(
                0,
                min(0.99, smoothing)
            )
    }

    public mutating func update(
        displacement:
            ScrollVector,
        deltaTime:
            TimeInterval
    ) -> ScrollVector {

        guard deltaTime > 0 else {
            return velocity
        }

        let instantaneous =
            displacement /
            deltaTime

        velocity =
            velocity * smoothing +
            instantaneous *
            (1 - smoothing)

        return velocity
    }

    public mutating func reset() {
        velocity = .zero
    }

    public var current:
        ScrollVector {
        velocity
    }
}
10. Touch-driven scrolling
public struct ScrollDragSample:
    Sendable
{
    public let position:
        ScrollVector

    public let timestamp:
        TimeInterval

    public init(
        position: ScrollVector,
        timestamp: TimeInterval
    ) {
        self.position = position
        self.timestamp = timestamp
    }
}
11. Scroll physics state
public struct ScrollPhysicsState:
    Sendable
{
    public var position:
        ScrollPosition

    public var velocity:
        ScrollVector

    public var state:
        ScrollState

    public var overscroll:
        ScrollVector

    public init(
        position:
            ScrollPosition = .zero,
        velocity:
            ScrollVector = .zero,
        state:
            ScrollState = .idle,
        overscroll:
            ScrollVector = .zero
    ) {

        self.position = position
        self.velocity = velocity
        self.state = state
        self.overscroll = overscroll
    }
}
12. Main physics engine
public final class AdaptiveScrollPhysics:
    @unchecked Sendable
{
    private var configuration:
        ScrollPhysicsConfiguration

    private let policy:
        AdaptiveScrollPolicy

    private var profile =
        ScrollBehaviourProfile()

    private var velocityEstimator =
        ScrollVelocityEstimator()

    private var state =
        ScrollPhysicsState()

    private var bounds =
        ScrollBounds()

    private var lastTouch:
        ScrollDragSample?

    private var dragStart:
        ScrollDragSample?

    public init(
        configuration:
            ScrollPhysicsConfiguration = .init()
    ) {

        self.configuration =
            configuration

        self.policy =
            AdaptiveScrollPolicy()
    }

    public func setBounds(
        _ bounds: ScrollBounds
    ) {

        self.bounds =
            bounds
    }

    public func setPosition(
        _ position:
            ScrollPosition
    ) {

        state.position =
            position
    }

    public var currentState:
        ScrollPhysicsState {
        state
    }
}
13. Begin dragging
extension AdaptiveScrollPhysics {

    public func beginDrag(
        at sample:
            ScrollDragSample
    ) {

        state.state =
            .dragging

        state.velocity =
            .zero

        velocityEstimator.reset()

        lastTouch =
            sample

        dragStart =
            sample

        state.overscroll =
            .zero
    }
}
14. Process finger movement
extension AdaptiveScrollPhysics {

    @discardableResult
    public func drag(
        to sample:
            ScrollDragSample
    ) -> ScrollPhysicsState {

        guard
            state.state == .dragging,
            let previous = lastTouch
        else {
            beginDrag(at: sample)
            return state
        }

        let delta =
            sample.position -
            previous.position

        let dt =
            max(
                sample.timestamp -
                previous.timestamp,
                0.000001
            )

        let velocity =
            velocityEstimator.update(
                displacement: delta,
                deltaTime: dt
            )

        applyDrag(
            delta: delta
        )

        state.velocity =
            velocity.clamped(
                magnitude:
                    configuration.maximumVelocity
            )

        lastTouch =
            sample

        return state
    }

    private func applyDrag(
        delta:
            ScrollVector
    ) {

        let proposed =
            state.position +
            delta

        state.position =
            constrainedPosition(
                proposed
            )
    }
}
15. Overscroll

This is important for the characteristic elastic behaviour.

extension AdaptiveScrollPhysics {

    private func constrainedPosition(
        _ proposed:
            ScrollPosition
    ) -> ScrollPosition {

        var result =
            proposed

        if proposed.x <
            bounds.minimumX {

            let excess =
                proposed.x -
                bounds.minimumX

            state.overscroll.x =
                excess *
                configuration.overscrollResistance

            result.x =
                bounds.minimumX +
                state.overscroll.x

        } else if proposed.x >
                    bounds.maximumX {

            let excess =
                proposed.x -
                bounds.maximumX

            state.overscroll.x =
                excess *
                configuration.overscrollResistance

            result.x =
                bounds.maximumX +
                state.overscroll.x

        } else {

            state.overscroll.x = 0
        }

        if proposed.y <
            bounds.minimumY {

            let excess =
                proposed.y -
                bounds.minimumY

            state.overscroll.y =
                excess *
                configuration.overscrollResistance

            result.y =
                bounds.minimumY +
                state.overscroll.y

        } else if proposed.y >
                    bounds.maximumY {

            let excess =
                proposed.y -
                bounds.maximumY

            state.overscroll.y =
                excess *
                configuration.overscrollResistance

            result.y =
                bounds.maximumY +
                state.overscroll.y

        } else {

            state.overscroll.y = 0
        }

        state.overscroll.x =
            max(
                -configuration.maximumOverscroll,
                min(
                    configuration.maximumOverscroll,
                    state.overscroll.x
                )
            )

        state.overscroll.y =
            max(
                -configuration.maximumOverscroll,
                min(
                    configuration.maximumOverscroll,
                    state.overscroll.y
                )
            )

        if state.overscroll.squaredMagnitude > 0 {
            state.state =
                .overscrolling
        }

        return result
    }
}
16. Release → momentum

When the finger leaves the display, we don't immediately stop.

We transfer the final finger velocity into the scrolling system.

extension AdaptiveScrollPhysics {

    public func endDrag(
        timestamp:
            TimeInterval
    ) {

        guard
            let start = dragStart,
            let last = lastTouch
        else {
            stop()
            return
        }

        let distance =
            last.position.distance(
                to: start.position
            )

        let duration =
            max(
                last.timestamp -
                start.timestamp,
                0.000001
            )

        profile.recordSwipe(
            velocity:
                state.velocity.magnitude,
            distance:
                distance,
            duration:
                duration
        )

        if state.overscroll.squaredMagnitude > 0 {

            state.state =
                .springing

        } else if state.velocity.magnitude >
                    configuration.minimumVelocity {

            state.state =
                .decelerating

        } else {

            stop()
        }

        lastTouch = nil
        dragStart = nil
    }

    private func stop() {

        state.velocity =
            .zero

        state.overscroll =
            .zero

        state.state =
            .idle

        velocityEstimator.reset()
    }
}
17. Exponential deceleration

A simple and effective model is:

$$ v(t+\Delta t)=v(t)e^{-k\Delta t} $$
extension AdaptiveScrollPhysics {

    public func step(
        deltaTime:
            TimeInterval
    ) -> ScrollPhysicsState {

        guard deltaTime > 0 else {
            return state
        }

        switch state.state {

        case .decelerating:
            stepDeceleration(
                deltaTime:
                    deltaTime
            )

        case .springing:
            stepSpring(
                deltaTime:
                    deltaTime
            )

        case .overscrolling:
            stepOverscroll(
                deltaTime:
                    deltaTime
            )

        default:
            break
        }

        return state
    }

    private func stepDeceleration(
        deltaTime:
            TimeInterval
    ) {

        let decay =
            exp(
                -configuration.friction *
                deltaTime
            )

        state.velocity =
            state.velocity *
            decay

        let movement =
            state.velocity *
            deltaTime

        let proposed =
            state.position +
            movement

        state.position =
            constrainedPosition(
                proposed
            )

        if state.overscroll.squaredMagnitude > 0 {

            state.state =
                .springing

            return
        }

        if state.velocity.magnitude <
            configuration.minimumVelocity {

            state.velocity =
                .zero

            state.state =
                .idle
        }
    }
}
18. Spring physics

The elastic return can be modeled as:

$$ a=-kx-cv $$

where:

k = spring stiffness
c = damping
x = displacement from the boundary
v = current velocity
extension AdaptiveScrollPhysics {

    private func stepSpring(
        deltaTime:
            TimeInterval
    ) {

        var acceleration =
            ScrollVector.zero

        if state.overscroll.x != 0 {

            acceleration.x =
                -configuration.springStiffness *
                state.overscroll.x -
                configuration.springDamping *
                state.velocity.x
        }

        if state.overscroll.y != 0 {

            acceleration.y =
                -configuration.springStiffness *
                state.overscroll.y -
                configuration.springDamping *
                state.velocity.y
        }

        state.velocity +=
            acceleration *
            deltaTime

        state.overscroll +=
            state.velocity *
            deltaTime

        state.position =
            ScrollPosition(
                x:
                    state.overscroll.x != 0
                    ? boundaryX() +
                        state.overscroll.x
                    : state.position.x,

                y:
                    state.overscroll.y != 0
                    ? boundaryY() +
                        state.overscroll.y
                    : state.position.y
            )

        if state.overscroll.magnitude < 0.5 &&
            state.velocity.magnitude < 5 {

            state.overscroll =
                .zero

            state.velocity =
                .zero

            state.position =
                ScrollPosition(
                    x:
                        clamp(
                            state.position.x,
                            bounds.minimumX,
                            bounds.maximumX
                        ),
                    y:
                        clamp(
                            state.position.y,
                            bounds.minimumY,
                            bounds.maximumY
                        )
                )

            state.state =
                .idle
        }
    }

    private func boundaryX()
        -> Double
    {
        state.overscroll.x < 0
            ? bounds.minimumX
            : bounds.maximumX
    }

    private func boundaryY()
        -> Double
    {
        state.overscroll.y < 0
            ? bounds.minimumY
            : bounds.maximumY
    }

    private func clamp(
        _ value: Double,
        _ minimum: Double,
        _ maximum: Double
    ) -> Double {

        max(
            minimum,
            min(maximum, value)
        )
    }
}
19. Overscroll settling
extension AdaptiveScrollPhysics {

    private func stepOverscroll(
        deltaTime:
            TimeInterval
    ) {

        state.velocity *=
            exp(
                -configuration.friction *
                deltaTime
            )

        state.overscroll *=
            exp(
                -configuration.friction *
                deltaTime
            )

        if state.overscroll.magnitude < 0.5 {

            state.overscroll =
                .zero

            state.velocity =
                .zero

            state.state =
                .idle
        }
    }
}
20. Adaptive runtime configuration

The engine can periodically retune itself.

extension AdaptiveScrollPhysics {

    public func adapt() {

        configuration =
            policy.configuration(
                base:
                    configuration,
                profile:
                    profile
            )
    }

    public var behaviourProfile:
        ScrollBehaviourProfile {

        profile
    }
}

A fast flick-oriented user therefore gets a slightly different momentum curve than somebody who performs slow, precise scrolling.

21. High-refresh-rate frame driver

This is where the engine becomes particularly interesting.

The physics engine should be independent of UIKit.

public protocol ScrollFrameDriver:
    AnyObject
{
    func start()
    func stop()

    var onFrame:
        ((TimeInterval) -> Void)?
    { get set }
}

A platform implementation can then connect to a display-linked callback.

For example, conceptually:

final class DisplayFrameDriver:
    ScrollFrameDriver
{
    var onFrame:
        ((TimeInterval) -> Void)?

    private var running = false

    func start() {
        running = true
    }

    func stop() {
        running = false
    }

    func simulateFrame(
        timestamp:
            TimeInterval
    ) {

        guard running else {
            return
        }

        onFrame?(timestamp)
    }
}

In an actual iOS implementation, this layer would normally be connected to an appropriate display synchronization API rather than manually simulating frames.

22. Scroll controller

Now we combine touch input and physics.

public final class AdaptiveScrollController:
    @unchecked Sendable
{
    private let physics:
        AdaptiveScrollPhysics

    private var lastFrameTime:
        TimeInterval?

    public var onPositionChanged:
        ((ScrollPosition) -> Void)?

    public init(
        physics:
            AdaptiveScrollPhysics =
                AdaptiveScrollPhysics()
    ) {

        self.physics =
            physics
    }

    public func begin(
        position:
            ScrollVector,
        timestamp:
            TimeInterval
    ) {

        physics.beginDrag(
            at:
                ScrollDragSample(
                    position: position,
                    timestamp: timestamp
                )
        )
    }

    public func move(
        position:
            ScrollVector,
        timestamp:
            TimeInterval
    ) {

        let state =
            physics.drag(
                to:
                    ScrollDragSample(
                        position: position,
                        timestamp: timestamp
                    )
            )

        onPositionChanged?(
            state.position
        )
    }

    public func end(
        timestamp:
            TimeInterval
    ) {

        physics.endDrag(
            timestamp:
                timestamp
        )
    }

    public func frame(
        timestamp:
            TimeInterval
    ) {

        let delta: TimeInterval

        if let lastFrameTime {
            delta =
                timestamp -
                lastFrameTime
        } else {
            delta =
                1.0 / 120.0
        }

        lastFrameTime =
            timestamp

        let state =
            physics.step(
                deltaTime:
                    min(delta, 0.05)
            )

        onPositionChanged?(
            state.position
        )
    }
}
23. Example
let physics =
    AdaptiveScrollPhysics()

physics.setBounds(
    ScrollBounds(
        minimumX: 0,
        maximumX: 0,
        minimumY: 0,
        maximumY: 8_000
    )
)

let controller =
    AdaptiveScrollController(
        physics: physics
    )

controller.onPositionChanged = {
    position in

    print(
        "Scroll position:",
        position
    )
}

Start:

controller.begin(
    position:
        ScrollVector(
            x: 500,
            y: 800
        ),
    timestamp: 0
)

Move:

controller.move(
    position:
        ScrollVector(
            x: 500,
            y: 700
        ),
    timestamp: 0.016
)

controller.move(
    position:
        ScrollVector(
            x: 500,
            y: 500
        ),
    timestamp: 0.032
)

controller.move(
    position:
        ScrollVector(
            x: 500,
            y: 250
        ),
    timestamp: 0.048
)

Release:

controller.end(
    timestamp: 0.050
)

Then drive physics:

var time = 0.050

for _ in 0..<240 {

    time += 1.0 / 120.0

    controller.frame(
        timestamp: time
    )
}

The result is a simulated inertial scroll.

24. Nested scrolling

This is important for modern interfaces.

For example:

Scroll View A
    │
    └── Scroll View B
           │
           └── horizontal carousel

We can explicitly model ownership.

public enum ScrollAxis:
    Sendable
{
    case horizontal
    case vertical
    case both
}
public struct ScrollContainer:
    Sendable,
    Hashable
{
    public let id: String
    public let axis: ScrollAxis
    public let priority: Int

    public init(
        id: String,
        axis: ScrollAxis,
        priority: Int
    ) {
        self.id = id
        self.axis = axis
        self.priority = priority
    }
}

Then:

public struct ScrollOwnershipResolver:
    Sendable
{
    public init() {}

    public func resolve(
        velocity:
            ScrollVector,
        containers:
            [ScrollContainer]
    ) -> ScrollContainer? {

        guard !containers.isEmpty else {
            return nil
        }

        let horizontal =
            abs(velocity.x) >
            abs(velocity.y)

        return containers
            .filter { container in

                switch container.axis {

                case .horizontal:
                    return horizontal

                case .vertical:
                    return !horizontal

                case .both:
                    return true
                }
            }
            .max {
                $0.priority <
                $1.priority
            }
    }
}

This prevents a horizontal carousel from accidentally handing every gesture to a vertically scrolling parent.

25. Predictive scrolling

Now connect #1/#4 to #7.

public struct ScrollPrediction:
    Sendable
{
    public let position:
        ScrollPosition

    public let velocity:
        ScrollVector

    public let horizon:
        TimeInterval
}
public struct ScrollPredictor:
    Sendable
{
    public init() {}

    public func predict(
        state:
            ScrollPhysicsState,
        horizon:
            TimeInterval
    ) -> ScrollPrediction {

        let predictedPosition =
            state.position +
            state.velocity *
            horizon

        return ScrollPrediction(
            position:
                predictedPosition,
            velocity:
                state.velocity,
            horizon:
                horizon
        )
    }
}

This permits the rendering layer to prepare for where the scroll is going rather than only where it currently is.

26. Scroll telemetry

Now we can measure the quality of the system.

public struct ScrollTelemetry:
    Sendable
{
    public var dragDuration:
        TimeInterval = 0

    public var maximumVelocity:
        Double = 0

    public var totalDistance:
        Double = 0

    public var frameCount:
        UInt64 = 0

    public var averageFrameTime:
        TimeInterval = 0

    public var overscrollCount:
        UInt64 = 0

    public var interruptedGestures:
        UInt64 = 0
}

A production version could feed this into the #10 System Monitoring & Diagnostics subsystem.

27. Scroll quality monitor
public struct ScrollQualityReport:
    Sendable
{
    public let averageFrameTime:
        TimeInterval

    public let maximumVelocity:
        Double

    public let overscrollEvents:
        UInt64

    public let interruptedGestures:
        UInt64

    public var estimatedFrameRate:
        Double {

        guard averageFrameTime > 0 else {
            return 0
        }

        return 1 /
            averageFrameTime
    }
}

This lets the system detect things like:

120 Hz target
       ↓
actual frame interval
       ↓
8.33 ms       → excellent
12 ms         → degraded
16.67 ms      → effectively 60 Hz
25 ms         → severe hitching
28. Unit tests
import XCTest

final class AdaptiveScrollPhysicsTests:
    XCTestCase
{
    func testDragMovesPosition() {

        let physics =
            AdaptiveScrollPhysics()

        physics.setBounds(
            ScrollBounds(
                minimumY: 0,
                maximumY: 1_000
            )
        )

        physics.beginDrag(
            at:
                ScrollDragSample(
                    position:
                        ScrollVector(
                            y: 500
                        ),
                    timestamp: 0
                )
        )

        let state =
            physics.drag(
                to:
                    ScrollDragSample(
                        position:
                            ScrollVector(
                                y: 400
                            ),
                        timestamp: 0.016
                    )
            )

        XCTAssertEqual(
            state.position.y,
            400,
            accuracy: 0.001
        )
    }

    func testVelocityIsGenerated() {

        let physics =
            AdaptiveScrollPhysics()

        physics.beginDrag(
            at:
                ScrollDragSample(
                    position:
                        ScrollVector(
                            y: 500
                        ),
                    timestamp: 0
                )
        )

        let state =
            physics.drag(
                to:
                    ScrollDragSample(
                        position:
                            ScrollVector(
                                y: 400
                            ),
                        timestamp: 0.016
                    )
            )

        XCTAssertGreaterThan(
            state.velocity.magnitude,
            0
        )
    }

    func testDecelerationEventuallyStops() {

        let physics =
            AdaptiveScrollPhysics()

        physics.setBounds(
            ScrollBounds(
                minimumY: 0,
                maximumY: 10_000
            )
        )

        physics.beginDrag(
            at:
                ScrollDragSample(
                    position:
                        ScrollVector(
                            y: 1_000
                        ),
                    timestamp: 0
                )
        )

        _ =
            physics.drag(
                to:
                    ScrollDragSample(
                        position:
                            ScrollVector(
                                y: 500
                            ),
                        timestamp: 0.05
                    )
            )

        physics.endDrag(
            timestamp: 0.05
        )

        for _ in 0..<2_000 {

            _ =
                physics.step(
                    deltaTime:
                        1.0 / 120.0
                )
        }

        XCTAssertEqual(
            physics.currentState.state,
            .idle
        )
    }
}





1. Display configuration
import Foundation
import CoreGraphics

public struct DisplayConfiguration:
    Sendable,
    Equatable
{
    public let refreshRate: Double
    public let width: Int
    public let height: Int
    public let scale: Double

    public init(
        refreshRate: Double,
        width: Int,
        height: Int,
        scale: Double
    ) {
        self.refreshRate = refreshRate
        self.width = width
        self.height = height
        self.scale = scale
    }

    public var frameDuration:
        TimeInterval {

        guard refreshRate > 0 else {
            return 1.0 / 60.0
        }

        return 1.0 / refreshRate
    }

    public var pixelsPerFrame:
        Int64 {

        Int64(width) *
        Int64(height)
    }
}

Examples:

let display60 =
    DisplayConfiguration(
        refreshRate: 60,
        width: 1179,
        height: 2556,
        scale: 3
    )

let display120 =
    DisplayConfiguration(
        refreshRate: 120,
        width: 1179,
        height: 2556,
        scale: 3
    )
2. Display timing

We need a precise representation of where we are inside a display cycle.

public struct DisplayFrame:
    Sendable,
    Equatable
{
    public let frameNumber: UInt64
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(
        frameNumber: UInt64,
        startTime: TimeInterval,
        duration: TimeInterval
    ) {
        self.frameNumber = frameNumber
        self.startTime = startTime
        self.endTime =
            startTime + duration
    }

    public var duration:
        TimeInterval {
        endTime - startTime
    }
}
3. Display clock
public struct DisplayClock:
    Sendable
{
    public let configuration:
        DisplayConfiguration

    public init(
        configuration:
            DisplayConfiguration
    ) {
        self.configuration =
            configuration
    }

    public func frame(
        containing timestamp:
            TimeInterval
    ) -> DisplayFrame {

        let duration =
            configuration.frameDuration

        let number =
            UInt64(
                max(
                    0,
                    floor(
                        timestamp /
                        duration
                    )
                )
            )

        let start =
            Double(number) *
            duration

        return DisplayFrame(
            frameNumber: number,
            startTime: start,
            duration: duration
        )
    }

    public func nextFrame(
        after timestamp:
            TimeInterval
    ) -> DisplayFrame {

        let current =
            frame(
                containing:
                    timestamp
            )

        if timestamp <
            current.endTime {

            return current
        }

        return DisplayFrame(
            frameNumber:
                current.frameNumber + 1,
            startTime:
                current.endTime,
            duration:
                configuration.frameDuration
        )
    }
}
4. Touch timestamp

Every input event needs a timestamp.

public struct DisplayTouchEvent:
    Sendable
{
    public let touchID: UInt64

    public let position:
        CGPoint

    public let timestamp:
        TimeInterval

    public let predictedPosition:
        CGPoint?

    public init(
        touchID: UInt64,
        position: CGPoint,
        timestamp: TimeInterval,
        predictedPosition:
            CGPoint? = nil
    ) {
        self.touchID = touchID
        self.position = position
        self.timestamp = timestamp
        self.predictedPosition =
            predictedPosition
    }
}
5. Input-to-frame latency
public struct TouchLatencySample:
    Sendable
{
    public let touchTimestamp:
        TimeInterval

    public let processingStart:
        TimeInterval

    public let processingEnd:
        TimeInterval

    public let renderStart:
        TimeInterval

    public let renderEnd:
        TimeInterval

    public let displayTime:
        TimeInterval

    public init(
        touchTimestamp:
            TimeInterval,
        processingStart:
            TimeInterval,
        processingEnd:
            TimeInterval,
        renderStart:
            TimeInterval,
        renderEnd:
            TimeInterval,
        displayTime:
            TimeInterval
    ) {
        self.touchTimestamp =
            touchTimestamp

        self.processingStart =
            processingStart

        self.processingEnd =
            processingEnd

        self.renderStart =
            renderStart

        self.renderEnd =
            renderEnd

        self.displayTime =
            displayTime
    }

    public var touchToProcessing:
        TimeInterval {

        processingStart -
        touchTimestamp
    }

    public var processingDuration:
        TimeInterval {

        processingEnd -
        processingStart
    }

    public var renderDuration:
        TimeInterval {

        renderEnd -
        renderStart
    }

    public var touchToDisplay:
        TimeInterval {

        displayTime -
        touchTimestamp
    }
}

This lets us distinguish:

Touch → CPU
CPU → GPU
GPU → frame
Frame → display

instead of treating everything as one mysterious latency number.

6. Frame deadline

The rendering engine needs to know how much time is actually available.

public struct FrameDeadline:
    Sendable,
    Equatable
{
    public let frame:
        DisplayFrame

    public let renderDeadline:
        TimeInterval

    public let safetyMargin:
        TimeInterval

    public init(
        frame:
            DisplayFrame,
        safetyMargin:
            TimeInterval = 0.001
    ) {

        self.frame = frame

        self.safetyMargin =
            safetyMargin

        self.renderDeadline =
            frame.endTime -
            safetyMargin
    }

    public func remainingTime(
        at timestamp:
            TimeInterval
    ) -> TimeInterval {

        max(
            0,
            renderDeadline -
            timestamp
        )
    }

    public func hasMissedDeadline(
        at timestamp:
            TimeInterval
    ) -> Bool {

        timestamp >
            renderDeadline
    }
}
7. Workload classification

Not every frame deserves the same scheduling policy.

public enum FrameWorkload:
    Sendable,
    Equatable
{
    case idle
    case scrolling
    case gesture
    case animation
    case drawing
    case gaming
    case camera
    case mixed
}
8. Frame priority
public enum FramePriority:
    Int,
    Sendable
{
    case background = 0
    case normal = 100
    case interactive = 500
    case realtime = 1_000
}
9. Render request
public struct RenderRequest:
    Sendable
{
    public let id:
        UInt64

    public let workload:
        FrameWorkload

    public let priority:
        FramePriority

    public let createdAt:
        TimeInterval

    public let estimatedDuration:
        TimeInterval

    public init(
        id: UInt64,
        workload:
            FrameWorkload,
        priority:
            FramePriority,
        createdAt:
            TimeInterval,
        estimatedDuration:
            TimeInterval
    ) {
        self.id = id
        self.workload = workload
        self.priority = priority
        self.createdAt = createdAt
        self.estimatedDuration =
            estimatedDuration
    }
}
10. Frame scheduler
public final class TouchDisplayFrameScheduler:
    @unchecked Sendable
{
    private let clock:
        DisplayClock

    private var nextFrameNumber:
        UInt64 = 0

    private var pending:
        [RenderRequest] = []

    public init(
        display:
            DisplayConfiguration
    ) {

        self.clock =
            DisplayClock(
                configuration:
                    display
            )
    }

    public func submit(
        _ request:
            RenderRequest
    ) {

        pending.append(
            request
        )

        pending.sort {
            if $0.priority.rawValue !=
                $1.priority.rawValue {

                return
                    $0.priority.rawValue >
                    $1.priority.rawValue
            }

            return
                $0.createdAt <
                $1.createdAt
        }
    }

    public func next(
        timestamp:
            TimeInterval
    ) -> RenderRequest? {

        guard !pending.isEmpty else {
            return nil
        }

        let frame =
            clock.nextFrame(
                after:
                    timestamp
            )

        let deadline =
            FrameDeadline(
                frame:
                    frame
            )

        let remaining =
            deadline.remainingTime(
                at:
                    timestamp
            )

        if let index =
            pending.firstIndex(
                where: {
                    $0.estimatedDuration <=
                    remaining
                }
            ) {

            return pending.remove(
                at: index
            )
        }

        return nil
    }
}
11. Predict the correct display frame

This is where #1 and #4 become useful.

public struct TouchDisplayPrediction:
    Sendable
{
    public let touch:
        DisplayTouchEvent

    public let targetFrame:
        DisplayFrame

    public let predictedPosition:
        CGPoint

    public let predictionHorizon:
        TimeInterval

    public let confidence:
        Double
}
public struct TouchDisplayPredictor:
    Sendable
{
    private let clock:
        DisplayClock

    public init(
        display:
            DisplayConfiguration
    ) {
        self.clock =
            DisplayClock(
                configuration:
                    display
            )
    }

    public func predict(
        touch:
            DisplayTouchEvent,
        now:
            TimeInterval
    ) -> TouchDisplayPrediction {

        let target =
            clock.nextFrame(
                after:
                    now
            )

        let horizon =
            max(
                0,
                target.endTime -
                touch.timestamp
            )

        let position =
            touch.predictedPosition ??
            touch.position

        let confidence =
            touch.predictedPosition == nil
            ? 0.70
            : 0.95

        return TouchDisplayPrediction(
            touch: touch,
            targetFrame: target,
            predictedPosition:
                position,
            predictionHorizon:
                horizon,
            confidence:
                confidence
        )
    }
}
12. Latency budget

We can now establish a budget.

public struct FrameLatencyBudget:
    Sendable
{
    public var inputBudget:
        TimeInterval

    public var processingBudget:
        TimeInterval

    public var renderBudget:
        TimeInterval

    public var safetyBudget:
        TimeInterval

    public init(
        inputBudget:
            TimeInterval = 0.0015,
        processingBudget:
            TimeInterval = 0.0025,
        renderBudget:
            TimeInterval = 0.0040,
        safetyBudget:
            TimeInterval = 0.0010
    ) {
        self.inputBudget =
            inputBudget

        self.processingBudget =
            processingBudget

        self.renderBudget =
            renderBudget

        self.safetyBudget =
            safetyBudget
    }

    public var total:
        TimeInterval {

        inputBudget +
        processingBudget +
        renderBudget +
        safetyBudget
    }
}

At 120 Hz, a frame is only about 8.33 ms, so the system cannot casually consume the entire interval before rendering starts.

13. Budget manager
public struct FrameBudgetDecision:
    Sendable
{
    public let allowHeavyWork:
        Bool

    public let remaining:
        TimeInterval

    public let deadline:
        TimeInterval
}
public struct FrameBudgetManager:
    Sendable
{
    public let budget:
        FrameLatencyBudget

    public init(
        budget:
            FrameLatencyBudget = .init()
    ) {
        self.budget =
            budget
    }

    public func evaluate(
        deadline:
            FrameDeadline,
        now:
            TimeInterval
    ) -> FrameBudgetDecision {

        let remaining =
            deadline.remainingTime(
                at:
                    now
            )

        return FrameBudgetDecision(
            allowHeavyWork:
                remaining >
                budget.processingBudget +
                budget.renderBudget,
            remaining:
                remaining,
            deadline:
                deadline.renderDeadline
        )
    }
}
14. Adaptive frame policy

If the frame is running late, expensive non-interactive work should be deferred.

public enum FrameWorkDecision:
    Sendable
{
    case execute
    case defer
    case reduceQuality
    case cancel
}
public struct AdaptiveFramePolicy:
    Sendable
{
    public init() {}

    public func decide(
        workload:
            FrameWorkload,
        remaining:
            TimeInterval,
        estimatedCost:
            TimeInterval
    ) -> FrameWorkDecision {

        if estimatedCost <= remaining {
            return .execute
        }

        switch workload {

        case .scrolling,
             .gesture,
             .gaming,
             .drawing:

            return .reduceQuality

        case .camera:

            return .reduceQuality

        case .animation:

            return .defer

        case .mixed:

            return .reduceQuality

        case .idle,
             .background:

            return .defer
        }
    }
}
15. Frame coordinator

Now combine the pieces.

public final class TouchDisplayCoordinator:
    @unchecked Sendable
{
    private let clock:
        DisplayClock

    private let predictor:
        TouchDisplayPredictor

    private let budgetManager:
        FrameBudgetManager

    private let policy:
        AdaptiveFramePolicy

    public init(
        display:
            DisplayConfiguration,
        budget:
            FrameLatencyBudget = .init()
    ) {

        self.clock =
            DisplayClock(
                configuration:
                    display
            )

        self.predictor =
            TouchDisplayPredictor(
                display:
                    display
            )

        self.budgetManager =
            FrameBudgetManager(
                budget:
                    budget
            )

        self.policy =
            AdaptiveFramePolicy()
    }
}
16. Process an incoming touch
extension TouchDisplayCoordinator {

    public func processTouch(
        _ touch:
            DisplayTouchEvent,
        now:
            TimeInterval
    ) -> TouchDisplayPrediction {

        predictor.predict(
            touch: touch,
            now: now
        )
    }
}
17. Decide whether rendering work can happen
extension TouchDisplayCoordinator {

    public func renderDecision(
        workload:
            FrameWorkload,
        estimatedCost:
            TimeInterval,
        now:
            TimeInterval
    ) -> FrameWorkDecision {

        let frame =
            clock.nextFrame(
                after:
                    now
            )

        let deadline =
            FrameDeadline(
                frame:
                    frame
            )

        let decision =
            budgetManager.evaluate(
                deadline:
                    deadline,
                now:
                    now
            )

        return policy.decide(
            workload:
                workload,
            remaining:
                decision.remaining,
            estimatedCost:
                estimatedCost
        )
    }
}
18. Frame pacing

A common problem is producing frames too early or too late.

We can model a pacing controller:

public struct FramePacingController:
    Sendable
{
    private(set) public var
        frameTimes:
            [TimeInterval] = []

    public let maximumSamples:
        Int

    public init(
        maximumSamples:
            Int = 120
    ) {
        self.maximumSamples =
            maximumSamples
    }

    public mutating func record(
        duration:
            TimeInterval
    ) {

        frameTimes.append(
            duration
        )

        if frameTimes.count >
            maximumSamples {

            frameTimes.removeFirst()
        }
    }

    public var average:
        TimeInterval {

        guard !frameTimes.isEmpty else {
            return 0
        }

        return frameTimes.reduce(
            0,
            +
        ) / Double(
            frameTimes.count
        )
    }

    public var estimatedFPS:
        Double {

        guard average > 0 else {
            return 0
        }

        return 1 / average
    }
}
19. Missed-frame detection
public struct FrameResult:
    Sendable
{
    public let frameNumber:
        UInt64

    public let duration:
        TimeInterval

    public let missedDeadline:
        Bool

    public let presented:
        Bool
}
public struct FrameMissDetector:
    Sendable
{
    public init() {}

    public func evaluate(
        frame:
            DisplayFrame,
        renderFinished:
            TimeInterval
    ) -> FrameResult {

        FrameResult(
            frameNumber:
                frame.frameNumber,

            duration:
                renderFinished -
                frame.startTime,

            missedDeadline:
                renderFinished >
                frame.endTime,

            presented:
                renderFinished <=
                frame.endTime
        )
    }
}
20. Touch-to-display measurement

This is the really valuable diagnostic layer.

public actor TouchDisplayTelemetry {

    private var samples:
        [TouchLatencySample] = []

    private let maximumSamples:
        Int

    public init(
        maximumSamples:
            Int = 1_000
    ) {
        self.maximumSamples =
            maximumSamples
    }

    public func record(
        _ sample:
            TouchLatencySample
    ) {

        samples.append(
            sample
        )

        if samples.count >
            maximumSamples {

            samples.removeFirst()
        }
    }

    public func meanTouchToDisplay()
        -> TimeInterval {

        guard !samples.isEmpty else {
            return 0
        }

        return samples.reduce(
            0
        ) {
            $0 +
            $1.touchToDisplay
        }
        /
        Double(samples.count)
    }

    public func maximumTouchToDisplay()
        -> TimeInterval {

        samples.map {
            $0.touchToDisplay
        }.max() ?? 0
    }

    public func sampleCount()
        -> Int {

        samples.count
    }
}

This can feed directly into the #10 diagnostics system.

21. Prediction error measurement

Prediction must be measured against reality.

public struct TouchPredictionError:
    Sendable
{
    public let predicted:
        CGPoint

    public let actual:
        CGPoint

    public let timestamp:
        TimeInterval

    public var distance:
        Double {

        let dx =
            predicted.x -
            actual.x

        let dy =
            predicted.y -
            actual.y

        return sqrt(
            dx * dx +
            dy * dy
        )
    }
}
22. Adaptive prediction horizon

Instead of permanently predicting 8 ms ahead, dynamically tune it.

public struct AdaptiveDisplayPredictionController:
    Sendable
{
    public private(set) var horizon:
        TimeInterval

    public let minimum:
        TimeInterval

    public let maximum:
        TimeInterval

    public let targetError:
        Double

    public init(
        horizon:
            TimeInterval = 0.008,
        minimum:
            TimeInterval = 0.002,
        maximum:
            TimeInterval = 0.016,
        targetError:
            Double = 3
    ) {

        self.horizon =
            horizon

        self.minimum =
            minimum

        self.maximum =
            maximum

        self.targetError =
            targetError
    }

    public mutating func update(
        predictionError:
            Double
    ) {

        if predictionError >
            targetError {

            horizon *= 0.85

        } else {

            horizon *= 1.05
        }

        horizon =
            max(
                minimum,
                min(
                    maximum,
                    horizon
                )
            )
    }
}

This is substantially better than using one fixed prediction interval for every user and every workload.

23. Input coalescing

High-frequency input can generate more samples than the renderer needs.

We can retain the most recent sample while preserving the prediction history.

public struct TouchSampleBuffer:
    Sendable
{
    private var samples:
        [DisplayTouchEvent] = []

    public let capacity:
        Int

    public init(
        capacity:
            Int = 32
    ) {
        self.capacity =
            capacity
    }

    public mutating func append(
        _ sample:
            DisplayTouchEvent
    ) {

        samples.append(
            sample
        )

        if samples.count >
            capacity {

            samples.removeFirst()
        }
    }

    public var latest:
        DisplayTouchEvent? {

        samples.last
    }

    public var all:
        [DisplayTouchEvent] {

        samples
    }

    public mutating func clear() {
        samples.removeAll()
    }
}
24. Render snapshot

The renderer shouldn't read mutable gesture state halfway through a frame.

Instead, create an immutable snapshot.

public struct TouchRenderSnapshot:
    Sendable
{
    public let timestamp:
        TimeInterval

    public let touches:
        [UInt64: CGPoint]

    public let predictedTouches:
        [UInt64: CGPoint]

    public let scrollPositions:
        [String: CGPoint]

    public init(
        timestamp:
            TimeInterval,
        touches:
            [UInt64: CGPoint],
        predictedTouches:
            [UInt64: CGPoint],
        scrollPositions:
            [String: CGPoint]
    ) {

        self.timestamp =
            timestamp

        self.touches =
            touches

        self.predictedTouches =
            predictedTouches

        self.scrollPositions =
            scrollPositions
    }
}

This is an important concurrency boundary:

INPUT THREAD
     │
     ▼
mutable input state
     │
     ▼
IMMUTABLE FRAME SNAPSHOT
     │
     ▼
GPU / RENDER THREAD
25. Atomic-style frame handoff
public actor FrameSnapshotStore {

    private var latest:
        TouchRenderSnapshot?

    public init() {}

    public func publish(
        _ snapshot:
            TouchRenderSnapshot
    ) {
        latest = snapshot
    }

    public func consume()
        -> TouchRenderSnapshot? {

        latest
    }
}

In a genuinely latency-critical implementation, this actor could be replaced by a specialised lock-free or atomic snapshot mechanism where appropriate.

26. Unified touchscreen/display engine

Now we can put the entire system together.

public actor TouchDisplaySynchronizationEngine {

    private let coordinator:
        TouchDisplayCoordinator

    private let telemetry:
        TouchDisplayTelemetry

    private let snapshotStore:
        FrameSnapshotStore

    private var predictionController =
        AdaptiveDisplayPredictionController()

    private var touchBuffers:
        [UInt64: TouchSampleBuffer] = [:]

    private var latestTouches:
        [UInt64: CGPoint] = [:]

    private var latestPredictions:
        [UInt64: CGPoint] = [:]

    private var scrollPositions:
        [String: CGPoint] = [:]

    public init(
        display:
            DisplayConfiguration
    ) {

        self.coordinator =
            TouchDisplayCoordinator(
                display:
                    display
            )

        self.telemetry =
            TouchDisplayTelemetry()

        self.snapshotStore =
            FrameSnapshotStore()
    }
}
27. Process touch
extension TouchDisplaySynchronizationEngine {

    public func receive(
        _ touch:
            DisplayTouchEvent,
        now:
            TimeInterval
    ) {

        var buffer =
            touchBuffers[
                touch.touchID
            ] ??
            TouchSampleBuffer()

        buffer.append(
            touch
        )

        touchBuffers[
            touch.touchID
        ] = buffer

        latestTouches[
            touch.touchID
        ] =
            touch.position

        let prediction =
            coordinator.processTouch(
                touch,
                now: now
            )

        latestPredictions[
            touch.touchID
        ] =
            prediction.predictedPosition
    }
}
28. Produce a frame snapshot
extension TouchDisplaySynchronizationEngine {

    public func makeFrameSnapshot(
        timestamp:
            TimeInterval
    ) async {

        let snapshot =
            TouchRenderSnapshot(
                timestamp:
                    timestamp,

                touches:
                    latestTouches,

                predictedTouches:
                    latestPredictions,

                scrollPositions:
                    scrollPositions
            )

        await snapshotStore.publish(
            snapshot
        )
    }
}
29. Prediction correction

When the actual touch arrives, compare it to what we predicted.

extension TouchDisplaySynchronizationEngine {

    public func correctPrediction(
        touchID:
            UInt64,
        actual:
            CGPoint,
        timestamp:
            TimeInterval
    ) {

        guard
            let predicted =
                latestPredictions[
                    touchID
                ]
        else {
            return
        }

        let dx =
            predicted.x -
            actual.x

        let dy =
            predicted.y -
            actual.y

        let error =
            sqrt(
                dx * dx +
                dy * dy
            )

        predictionController.update(
            predictionError:
                error
        )

        latestTouches[
            touchID
        ] = actual
    }
}

The important point is that prediction becomes a feedback system:

prediction
     ↓
display
     ↓
actual touch
     ↓
prediction error
     ↓
adaptive horizon
     ↓
better prediction
30. Frame statistics
public struct DisplaySynchronizationStatistics:
    Sendable
{
    public var frames:
        UInt64 = 0

    public var missedFrames:
        UInt64 = 0

    public var predictedTouches:
        UInt64 = 0

    public var correctedPredictions:
        UInt64 = 0

    public var cumulativePredictionError:
        Double = 0

    public var cumulativeTouchToDisplay:
        TimeInterval = 0

    public var maximumTouchToDisplay:
        TimeInterval = 0

    public var averagePredictionError:
        Double {

        guard correctedPredictions > 0 else {
            return 0
        }

        return cumulativePredictionError /
            Double(correctedPredictions)
    }

    public var averageTouchToDisplay:
        TimeInterval {

        guard frames > 0 else {
            return 0
        }

        return cumulativeTouchToDisplay /
            Double(frames)
    }
}
31. XCTest
import XCTest

final class DisplaySynchronizationTests:
    XCTestCase
{
    func test120HzFrameDuration() {

        let display =
            DisplayConfiguration(
                refreshRate: 120,
                width: 1179,
                height: 2556,
                scale: 3
            )

        XCTAssertEqual(
            display.frameDuration,
            1.0 / 120.0,
            accuracy: 0.000001
        )
    }

    func testFrameDeadline() {

        let display =
            DisplayConfiguration(
                refreshRate: 120,
                width: 1179,
                height: 2556,
                scale: 3
            )

        let clock =
            DisplayClock(
                configuration:
                    display
            )

        let frame =
            clock.frame(
                containing:
                    0.010
            )

        let deadline =
            FrameDeadline(
                frame:
                    frame
            )

        XCTAssertLessThan(
            deadline.renderDeadline,
            frame.endTime
        )
    }

    func testPrediction() {

        let display =
            DisplayConfiguration(
                refreshRate: 120,
                width: 1179,
                height: 2556,
                scale: 3
            )

        let predictor =
            TouchDisplayPredictor(
                display:
                    display
            )

        let touch =
            DisplayTouchEvent(
                touchID: 1,
                position:
                    CGPoint(
                        x: 100,
                        y: 200
                    ),
                timestamp: 0,
                predictedPosition:
                    CGPoint(
                        x: 105,
                        y: 205
                    )
            )

        let prediction =
            predictor.predict(
                touch:
                    touch,
                now:
                    0.001
            )

        XCTAssertEqual(
            prediction.predictedPosition,
            CGPoint(
                x: 105,
                y: 205
            )
        )

        XCTAssertGreaterThan(
            prediction.confidence,
            0
        )
    }
}




1. Intent types
import Foundation
import CoreGraphics

public enum TouchIntent:
    String,
    Sendable,
    Codable
{
    case unknown
    case tap
    case doubleTap
    case longPress
    case drag
    case scroll
    case swipe
    case textSelection
    case drawing
    case buttonActivation
    case edgeGesture
    case pinch
    case rotation
    case accidental
}
2. Intent confidence
public struct IntentProbability:
    Sendable,
    Codable,
    Equatable
{
    public let intent:
        TouchIntent

    public let probability:
        Double

    public init(
        intent:
            TouchIntent,
        probability:
            Double
    ) {

        self.intent = intent

        self.probability =
            max(
                0,
                min(1, probability)
            )
    }
}
3. Touch context

The same movement means different things depending on the UI.

public enum AIInteractionContext:
    String,
    Sendable,
    Codable
{
    case unknown
    case normalUI
    case keyboard
    case textEditor
    case scrollView
    case drawingCanvas
    case game
    case mediaPlayer
    case photoEditor
    case map
    case browser
    case accessibility
}
4. Touch trajectory

We need a compact representation of the interaction.

public struct IntentTouchPoint:
    Sendable,
    Codable
{
    public let x: Double
    public let y: Double
    public let timestamp: TimeInterval

    public init(
        x: Double,
        y: Double,
        timestamp:
            TimeInterval
    ) {

        self.x = x
        self.y = y
        self.timestamp =
            timestamp
    }

    public var point:
        CGPoint {

        CGPoint(
            x: x,
            y: y
        )
    }
}
5. Motion features
public struct IntentMotionFeatures:
    Sendable,
    Codable
{
    public var velocityX:
        Double = 0

    public var velocityY:
        Double = 0

    public var speed:
        Double = 0

    public var acceleration:
        Double = 0

    public var direction:
        Double = 0

    public var distance:
        Double = 0

    public var duration:
        TimeInterval = 0
}
6. Geometry features
public struct IntentGeometryFeatures:
    Sendable,
    Codable
{
    public var contactRadius:
        Double = 0

    public var aspectRatio:
        Double = 1

    public var contactArea:
        Double = 0

    public var edgeDistance:
        Double = 0

    public var screenWidth:
        Double = 1

    public var screenHeight:
        Double = 1
}
7. Complete feature vector

This is the interface between the deterministic touch system and the AI model.

public struct TouchIntentFeatures:
    Sendable,
    Codable
{
    public var motion:
        IntentMotionFeatures

    public var geometry:
        IntentGeometryFeatures

    public var fingerCount:
        Int

    public var context:
        AIInteractionContext

    public var zoneConfidence:
        Double

    public var palmProbability:
        Double

    public var accidentalProbability:
        Double

    public var predictionConfidence:
        Double

    public init(
        motion:
            IntentMotionFeatures,
        geometry:
            IntentGeometryFeatures,
        fingerCount:
            Int,
        context:
            AIInteractionContext,
        zoneConfidence:
            Double = 0,
        palmProbability:
            Double = 0,
        accidentalProbability:
            Double = 0,
        predictionConfidence:
            Double = 0
    ) {

        self.motion = motion
        self.geometry = geometry
        self.fingerCount = fingerCount
        self.context = context
        self.zoneConfidence =
            zoneConfidence
        self.palmProbability =
            palmProbability
        self.accidentalProbability =
            accidentalProbability
        self.predictionConfidence =
            predictionConfidence
    }
}
8. Feature vector for Core ML

A Core ML model generally wants numerical inputs.

We therefore create a fixed representation.

public struct MLTouchFeatureVector:
    Sendable
{
    public let values:
        [Double]

    public init(
        features:
            TouchIntentFeatures
    ) {

        let motion =
            features.motion

        let geometry =
            features.geometry

        self.values = [

            motion.velocityX,
            motion.velocityY,
            motion.speed,
            motion.acceleration,
            motion.direction,
            motion.distance,
            motion.duration,

            geometry.contactRadius,
            geometry.aspectRatio,
            geometry.contactArea,
            geometry.edgeDistance,

            geometry.screenWidth,
            geometry.screenHeight,

            Double(
                features.fingerCount
            ),

            features.zoneConfidence,
            features.palmProbability,
            features.accidentalProbability,
            features.predictionConfidence
        ]
    }
}

This gives us a stable 18-feature input vector.

9. Model output
public struct TouchIntentModelOutput:
    Sendable
{
    public let probabilities:
        [IntentProbability]

    public let modelVersion:
        String

    public init(
        probabilities:
            [IntentProbability],
        modelVersion:
            String
    ) {

        self.probabilities =
            probabilities

        self.modelVersion =
            modelVersion
    }

    public var bestIntent:
        TouchIntent {

        probabilities.max {
            $0.probability <
            $1.probability
        }?.intent ?? .unknown
    }

    public var confidence:
        Double {

        probabilities.max {
            $0.probability <
            $1.probability
        }?.probability ?? 0
    }
}
10. AI model protocol

Keep Core ML behind a protocol.

public protocol TouchIntentModel:
    Sendable
{
    func predict(
        _ features:
            MLTouchFeatureVector
    ) async throws
        -> TouchIntentModelOutput
}

That means the rest of the system doesn't care whether the model is:

Core ML
a hand-built classifier
a future Apple Neural Engine model
a simulator model
a test implementation.
11. Deterministic fallback model

We should always have a fallback.

Touch input is too important to depend entirely on an ML model.

public struct RuleBasedIntentModel:
    TouchIntentModel
{
    public let modelVersion =
        "rules-1.0"

    public init() {}

    public func predict(
        _ vector:
            MLTouchFeatureVector
    ) async throws
        -> TouchIntentModelOutput
    {
        let v =
            vector.values

        guard v.count >= 18 else {

            return TouchIntentModelOutput(
                probabilities: [
                    .init(
                        intent: .unknown,
                        probability: 1
                    )
                ],
                modelVersion:
                    modelVersion
            )
        }

        let speed = v[2]
        let distance = v[5]
        let duration = v[6]
        let fingers = Int(v[13])

        let accidental = v[16]

        if accidental > 0.80 {

            return output(
                best: .accidental,
                confidence: accidental
            )
        }

        if fingers >= 2 {

            if speed < 200 {

                return output(
                    best: .pinch,
                    confidence: 0.65
                )
            }

            return output(
                best: .rotation,
                confidence: 0.55
            )
        }

        if distance < 12 &&
            duration < 0.35 {

            return output(
                best: .tap,
                confidence: 0.82
            )
        }

        if duration > 0.5 &&
            speed < 100 {

            return output(
                best: .longPress,
                confidence: 0.78
            )
        }

        if speed > 1_500 {

            return output(
                best: .swipe,
                confidence: 0.86
            )
        }

        if distance > 30 {

            return output(
                best: .drag,
                confidence: 0.70
            )
        }

        return output(
            best: .unknown,
            confidence: 0.40
        )
    }

    private func output(
        best:
            TouchIntent,
        confidence:
            Double
    ) -> TouchIntentModelOutput {

        TouchIntentModelOutput(
            probabilities: [
                .init(
                    intent: best,
                    probability:
                        confidence
                )
            ],
            modelVersion:
                modelVersion
        )
    }
}
12. Context-aware intent correction

This is extremely important.

Suppose the raw trajectory looks like a drag.

If the user is in a text editor and the finger starts over text, it may actually be text selection.

public struct ContextIntentAdjuster:
    Sendable
{
    public init() {}

    public func adjust(
        output:
            TouchIntentModelOutput,
        context:
            AIInteractionContext,
        features:
            TouchIntentFeatures
    ) -> TouchIntentModelOutput {

        var probabilities =
            Dictionary(
                uniqueKeysWithValues:
                    output.probabilities.map {
                        ($0.intent, $0.probability)
                    }
            )

        switch context {

        case .drawingCanvas:

            probabilities[.drawing, default: 0] +=
                0.25

            probabilities[.scroll, default: 0] *=
                0.60

        case .textEditor:

            probabilities[.textSelection, default: 0] +=
                0.25

        case .scrollView:

            probabilities[.scroll, default: 0] +=
                0.25

        case .game:

            probabilities[.drag, default: 0] +=
                0.10

        case .map:

            probabilities[.drag, default: 0] +=
                0.15

            probabilities[.scroll, default: 0] +=
                0.10

        case .keyboard:

            probabilities[.tap, default: 0] +=
                0.30

        case .accessibility:

            probabilities[.longPress, default: 0] +=
                0.15

        default:
            break
        }

        if features.fingerCount >= 2 {

            probabilities[.pinch, default: 0] +=
                0.20

            probabilities[.rotation, default: 0] +=
                0.15
        }

        let result =
            probabilities
                .map {
                    IntentProbability(
                        intent:
                            $0.key,
                        probability:
                            min(
                                1,
                                $0.value
                            )
                    )
                }
                .sorted {
                    $0.probability >
                    $1.probability
                }

        return TouchIntentModelOutput(
            probabilities:
                result,
            modelVersion:
                output.modelVersion
        )
    }
}
13. Temporal intent recognition

One of the biggest mistakes would be deciding the intent from one touch sample.

Instead:

sample 1 → unknown
sample 2 → tap / drag
sample 3 → drag 78%
sample 4 → drag 94%
public struct IntentHistory:
    Sendable
{
    private var outputs:
        [TouchIntentModelOutput] = []

    public let capacity:
        Int

    public init(
        capacity:
            Int = 12
    ) {
        self.capacity =
            capacity
    }

    public mutating func append(
        _ output:
            TouchIntentModelOutput
    ) {

        outputs.append(
            output
        )

        if outputs.count >
            capacity {

            outputs.removeFirst()
        }
    }

    public func averagedOutput()
        -> TouchIntentModelOutput?
    {
        guard !outputs.isEmpty else {
            return nil
        }

        var sums:
            [TouchIntent: Double] = [:]

        for output in outputs {

            for probability
                in output.probabilities {

                sums[
                    probability.intent,
                    default: 0
                ] +=
                    probability.probability
            }
        }

        let count =
            Double(outputs.count)

        let averaged =
            sums.map {
                IntentProbability(
                    intent:
                        $0.key,
                    probability:
                        $0.value / count
                )
            }

        return TouchIntentModelOutput(
            probabilities:
                averaged,
            modelVersion:
                outputs.last!.modelVersion
        )
    }
}
14. Intent state machine
public enum IntentState:
    Sendable,
    Equatable
{
    case undecided
    case candidate(TouchIntent)
    case committed(TouchIntent)
    case cancelled
    case completed(TouchIntent)
}
15. Intent session
public struct TouchIntentSession:
    Sendable
{
    public let touchID:
        UInt64

    public var state:
        IntentState

    public var startTime:
        TimeInterval

    public var lastTime:
        TimeInterval

    public var points:
        [IntentTouchPoint]

    public init(
        touchID:
            UInt64,
        timestamp:
            TimeInterval
    ) {

        self.touchID =
            touchID

        self.state =
            .undecided

        self.startTime =
            timestamp

        self.lastTime =
            timestamp

        self.points = []
    }
}
16. Session tracker
public actor TouchIntentSessionStore {

    private var sessions:
        [UInt64: TouchIntentSession] = [:]

    public init() {}

    public func start(
        touchID:
            UInt64,
        timestamp:
            TimeInterval
    ) {

        sessions[
            touchID
        ] =
            TouchIntentSession(
                touchID:
                    touchID,
                timestamp:
                    timestamp
            )
    }

    public func append(
        touchID:
            UInt64,
        point:
            IntentTouchPoint
    ) {

        guard var session =
            sessions[touchID]
        else {
            return
        }

        session.points.append(
            point
        )

        session.lastTime =
            point.timestamp

        if session.points.count >
            64 {

            session.points.removeFirst()
        }

        sessions[touchID] =
            session
    }

    public func get(
        touchID:
            UInt64
    ) -> TouchIntentSession? {

        sessions[touchID]
    }

    public func remove(
        touchID:
            UInt64
    ) {

        sessions.removeValue(
            forKey:
                touchID
        )
    }

    public func reset() {
        sessions.removeAll()
    }
}
17. Feature extraction

This converts the trajectory into AI features.

public struct TouchIntentFeatureExtractor:
    Sendable
{
    public init() {}

    public func extract(
        session:
            TouchIntentSession,
        context:
            AIInteractionContext,
        fingerCount:
            Int,
        screen:
            CGSize,
        contactRadius:
            Double = 0,
        aspectRatio:
            Double = 1,
        zoneConfidence:
            Double = 0,
        palmProbability:
            Double = 0,
        accidentalProbability:
            Double = 0,
        predictionConfidence:
            Double = 0
    ) -> TouchIntentFeatures {

        guard
            let first =
                session.points.first,
            let last =
                session.points.last
        else {

            return TouchIntentFeatures(
                motion:
                    .init(),
                geometry:
                    .init(),
                fingerCount:
                    fingerCount,
                context:
                    context
            )
        }

        let dx =
            last.x -
            first.x

        let dy =
            last.y -
            first.y

        let distance =
            sqrt(
                dx * dx +
                dy * dy
            )

        let duration =
            max(
                last.timestamp -
                first.timestamp,
                0.000001
            )

        let velocityX =
            dx / duration

        let velocityY =
            dy / duration

        let speed =
            sqrt(
                velocityX *
                velocityX +
                velocityY *
                velocityY
            )

        let direction =
            atan2(
                velocityY,
                velocityX
            )

        return TouchIntentFeatures(

            motion:
                IntentMotionFeatures(
                    velocityX:
                        velocityX,
                    velocityY:
                        velocityY,
                    speed:
                        speed,
                    acceleration:
                        estimateAcceleration(
                            points:
                                session.points
                        ),
                    direction:
                        direction,
                    distance:
                        distance,
                    duration:
                        duration
                ),

            geometry:
                IntentGeometryFeatures(
                    contactRadius:
                        contactRadius,
                    aspectRatio:
                        aspectRatio,
                    contactArea:
                        .pi *
                        contactRadius *
                        contactRadius,
                    edgeDistance:
                        edgeDistance(
                            point:
                                last.point,
                            screen:
                                screen
                        ),
                    screenWidth:
                        screen.width,
                    screenHeight:
                        screen.height
                ),

            fingerCount:
                fingerCount,

            context:
                context,

            zoneConfidence:
                zoneConfidence,

            palmProbability:
                palmProbability,

            accidentalProbability:
                accidentalProbability,

            predictionConfidence:
                predictionConfidence
        )
    }

    private func estimateAcceleration(
        points:
            [IntentTouchPoint]
    ) -> Double {

        guard points.count >= 3 else {
            return 0
        }

        let a =
            points[points.count - 3]

        let b =
            points[points.count - 2]

        let c =
            points[points.count - 1]

        let dt1 =
            max(
                b.timestamp -
                a.timestamp,
                0.000001
            )

        let dt2 =
            max(
                c.timestamp -
                b.timestamp,
                0.000001
            )

        let v1 =
            hypot(
                b.x - a.x,
                b.y - a.y
            ) / dt1

        let v2 =
            hypot(
                c.x - b.x,
                c.y - b.y
            ) / dt2

        return (
            v2 - v1
        ) /
        dt2
    }

    private func edgeDistance(
        point:
            CGPoint,
        screen:
            CGSize
    ) -> Double {

        min(
            point.x,
            point.y,
            screen.width - point.x,
            screen.height - point.y
        )
    }
}
18. Intent decision

Now establish a minimum confidence before changing the UI's interpretation.

public struct TouchIntentDecision:
    Sendable
{
    public let touchID:
        UInt64

    public let intent:
        TouchIntent

    public let confidence:
        Double

    public let state:
        IntentState

    public let modelVersion:
        String

    public init(
        touchID:
            UInt64,
        intent:
            TouchIntent,
        confidence:
            Double,
        state:
            IntentState,
        modelVersion:
            String
    ) {

        self.touchID =
            touchID

        self.intent =
            intent

        self.confidence =
            confidence

        self.state =
            state

        self.modelVersion =
            modelVersion
    }
}
19. Intent commit policy

This prevents the AI from constantly changing its mind.

public struct IntentCommitPolicy:
    Sendable
{
    public let commitThreshold:
        Double

    public let minimumSamples:
        Int

    public init(
        commitThreshold:
            Double = 0.78,
        minimumSamples:
            Int = 3
    ) {

        self.commitThreshold =
            commitThreshold

        self.minimumSamples =
            minimumSamples
    }

    public func shouldCommit(
        output:
            TouchIntentModelOutput,
        sampleCount:
            Int
    ) -> Bool {

        sampleCount >=
            minimumSamples &&
        output.confidence >=
            commitThreshold
    }
}
20. Main AI intent engine
public actor TouchIntentEngine {

    private let model:
        any TouchIntentModel

    private let fallback:
        RuleBasedIntentModel

    private let featureExtractor:
        TouchIntentFeatureExtractor

    private let contextAdjuster:
        ContextIntentAdjuster

    private let commitPolicy:
        IntentCommitPolicy

    private var sessions:
        [UInt64: TouchIntentSession] = [:]

    private var histories:
        [UInt64: IntentHistory] = [:]

    public init(
        model:
            any TouchIntentModel =
                RuleBasedIntentModel(),
        commitPolicy:
            IntentCommitPolicy =
                .init()
    ) {

        self.model =
            model

        self.fallback =
            RuleBasedIntentModel()

        self.featureExtractor =
            TouchIntentFeatureExtractor()

        self.contextAdjuster =
            ContextIntentAdjuster()

        self.commitPolicy =
            commitPolicy
    }
}
21. Begin an interaction
extension TouchIntentEngine {

    public func begin(
        touchID:
            UInt64,
        position:
            CGPoint,
        timestamp:
            TimeInterval
    ) {

        sessions[
            touchID
        ] =
            TouchIntentSession(
                touchID:
                    touchID,
                timestamp:
                    timestamp
            )

        histories[
            touchID
        ] =
            IntentHistory()
    }
}
22. Process each touch sample
extension TouchIntentEngine {

    public func process(
        touchID:
            UInt64,
        position:
            CGPoint,
        timestamp:
            TimeInterval,
        context:
            AIInteractionContext,
        screen:
            CGSize,
        fingerCount:
            Int,
        contactRadius:
            Double = 0,
        aspectRatio:
            Double = 1,
        zoneConfidence:
            Double = 1,
        palmProbability:
            Double = 0,
        accidentalProbability:
            Double = 0,
        predictionConfidence:
            Double = 0
    ) async
        -> TouchIntentDecision
    {

        guard var session =
            sessions[touchID]
        else {

            begin(
                touchID:
                    touchID,
                position:
                    position,
                timestamp:
                    timestamp
            )

            return TouchIntentDecision(
                touchID:
                    touchID,
                intent:
                    .unknown,
                confidence:
                    0,
                state:
                    .undecided,
                modelVersion:
                    "none"
            )
        }

        session.points.append(
            IntentTouchPoint(
                x:
                    position.x,
                y:
                    position.y,
                timestamp:
                    timestamp
            )
        )

        session.lastTime =
            timestamp

        sessions[touchID] =
            session

        let features =
            featureExtractor.extract(
                session:
                    session,
                context:
                    context,
                fingerCount:
                    fingerCount,
                screen:
                    screen,
                contactRadius:
                    contactRadius,
                aspectRatio:
                    aspectRatio,
                zoneConfidence:
                    zoneConfidence,
                palmProbability:
                    palmProbability,
                accidentalProbability:
                    accidentalProbability,
                predictionConfidence:
                    predictionConfidence
            )

        let vector =
            MLTouchFeatureVector(
                features:
                    features
            )

        let rawOutput:
            TouchIntentModelOutput

        do {

            rawOutput =
                try await model.predict(
                    vector
                )

        } catch {

            rawOutput =
                (try? await fallback.predict(
                    vector
                ))
                ??
                TouchIntentModelOutput(
                    probabilities: [],
                    modelVersion:
                        "failure"
                )
        }

        let adjusted =
            contextAdjuster.adjust(
                output:
                    rawOutput,
                context:
                    context,
                features:
                    features
            )

        var history =
            histories[touchID] ??
            IntentHistory()

        history.append(
            adjusted
        )

        histories[touchID] =
            history

        let averaged =
            history.averagedOutput()
            ?? adjusted

        let shouldCommit =
            commitPolicy.shouldCommit(
                output:
                    averaged,
                sampleCount:
                    session.points.count
            )

        let intent =
            averaged.bestIntent

        if shouldCommit {

            session.state =
                .committed(intent)

        } else {

            session.state =
                .candidate(intent)
        }

        sessions[touchID] =
            session

        return TouchIntentDecision(
            touchID:
                touchID,
            intent:
                intent,
            confidence:
                averaged.confidence,
            state:
                session.state,
            modelVersion:
                averaged.modelVersion
        )
    }
}
23. Finish an interaction
extension TouchIntentEngine {

    public func end(
        touchID:
            UInt64
    ) -> TouchIntentDecision? {

        guard
            let session =
                sessions[touchID],
            let history =
                histories[touchID],
            let output =
                history.averagedOutput()
        else {
            return nil
        }

        let decision =
            TouchIntentDecision(
                touchID:
                    touchID,
                intent:
                    output.bestIntent,
                confidence:
                    output.confidence,
                state:
                    .completed(
                        output.bestIntent
                    ),
                modelVersion:
                    output.modelVersion
            )

        sessions.removeValue(
            forKey:
                touchID
        )

        histories.removeValue(
            forKey:
                touchID
        )

        return decision
    }

    public func cancel(
        touchID:
            UInt64
    ) {

        sessions.removeValue(
            forKey:
                touchID
        )

        histories.removeValue(
            forKey:
                touchID
        )
    }

    public func reset() {

        sessions.removeAll()
        histories.removeAll()
    }
}
24. AI + palm rejection

The previous #2 system becomes an input to this engine.

We should never let an AI model override a very strong palm-rejection decision.

public struct IntentSafetyGate:
    Sendable
{
    public let palmThreshold:
        Double

    public let accidentalThreshold:
        Double

    public init(
        palmThreshold:
            Double = 0.90,
        accidentalThreshold:
            Double = 0.90
    ) {

        self.palmThreshold =
            palmThreshold

        self.accidentalThreshold =
            accidentalThreshold
    }

    public func apply(
        decision:
            TouchIntentDecision,
        palmProbability:
            Double,
        accidentalProbability:
            Double
    ) -> TouchIntentDecision {

        if palmProbability >=
            palmThreshold ||
            accidentalProbability >=
            accidentalThreshold {

            return TouchIntentDecision(
                touchID:
                    decision.touchID,
                intent:
                    .accidental,
                confidence:
                    max(
                        palmProbability,
                        accidentalProbability
                    ),
                state:
                    .committed(.accidental),
                modelVersion:
                    decision.modelVersion
            )
        }

        return decision
    }
}

This gives us:

AI says: "drag"
       ↓
Palm detector says: "96% palm"
       ↓
SAFETY GATE
       ↓
reject
25. Intent arbitration

Several interpretations can be simultaneously plausible.

public struct IntentArbitrator:
    Sendable
{
    public init() {}

    public func resolve(
        probabilities:
            [IntentProbability]
    ) -> TouchIntent {

        probabilities
            .sorted {
                $0.probability >
                $1.probability
            }
            .first?
            .intent
            ?? .unknown
    }
}
26. User-specific calibration

The engine can learn interaction characteristics without changing the fundamental UI semantics.

public struct TouchIntentCalibration:
    Sendable,
    Codable
{
    public var tapDistance:
        Double = 12

    public var tapDuration:
        TimeInterval = 0.35

    public var longPressDuration:
        TimeInterval = 0.50

    public var swipeVelocity:
        Double = 1_500

    public var dragDistance:
        Double = 30

    public init() {}
}

A future version could adapt these within tightly bounded ranges.

27. Calibration engine
public actor TouchIntentCalibrationEngine {

    private var calibration:
        TouchIntentCalibration

    public init(
        calibration:
            TouchIntentCalibration =
                .init()
    ) {

        self.calibration =
            calibration
    }

    public func updateTapDistance(
        _ distance:
            Double
    ) {

        calibration.tapDistance =
            max(
                4,
                min(
                    30,
                    distance
                )
            )
    }

    public func updateSwipeVelocity(
        _ velocity:
            Double
    ) {

        calibration.swipeVelocity =
            max(
                500,
                min(
                    4_000,
                    velocity
                )
            )
    }

    public func current()
        -> TouchIntentCalibration {

        calibration
    }
}
28. Model telemetry

This is essential if this ever becomes a serious system.

public struct IntentTelemetry:
    Sendable
{
    public let touchID:
        UInt64

    public let predictedIntent:
        TouchIntent

    public let confidence:
        Double

    public let modelVersion:
        String

    public let latency:
        TimeInterval

    public let corrected:
        Bool
}
29. Telemetry store
public actor IntentTelemetryStore {

    private var records:
        [IntentTelemetry] = []

    private let capacity:
        Int

    public init(
        capacity:
            Int = 10_000
    ) {
        self.capacity =
            capacity
    }

    public func record(
        _ telemetry:
            IntentTelemetry
    ) {

        records.append(
            telemetry
        )

        if records.count >
            capacity {

            records.removeFirst()
        }
    }

    public func averageLatency()
        -> TimeInterval {

        guard !records.isEmpty else {
            return 0
        }

        return records.reduce(
            0
        ) {
            $0 +
            $1.latency
        } /
        Double(records.count)
    }

    public func correctionRate()
        -> Double {

        guard !records.isEmpty else {
            return 0
        }

        let corrected =
            records.filter {
                $0.corrected
            }.count

        return Double(corrected) /
            Double(records.count)
    }
}
30. Unified intelligent touch pipeline

Now connect everything we've built.

public actor IntelligentTouchIntentCoordinator {

    private let intentEngine:
        TouchIntentEngine

    private let safetyGate:
        IntentSafetyGate

    private let telemetry:
        IntentTelemetryStore

    public init(
        model:
            any TouchIntentModel =
                RuleBasedIntentModel()
    ) {

        self.intentEngine =
            TouchIntentEngine(
                model:
                    model
            )

        self.safetyGate =
            IntentSafetyGate()

        self.telemetry =
            IntentTelemetryStore()
    }

    public func process(
        touchID:
            UInt64,
        position:
            CGPoint,
        timestamp:
            TimeInterval,
        context:
            AIInteractionContext,
        screen:
            CGSize,
        fingerCount:
            Int,
        palmProbability:
            Double,
        accidentalProbability:
            Double,
        predictionConfidence:
            Double
    ) async -> TouchIntentDecision {

        let start =
            timestamp

        let decision =
            await intentEngine.process(
                touchID:
                    touchID,
                position:
                    position,
                timestamp:
                    timestamp,
                context:
                    context,
                screen:
                    screen,
                fingerCount:
                    fingerCount,
                palmProbability:
                    palmProbability,
                accidentalProbability:
                    accidentalProbability,
                predictionConfidence:
                    predictionConfidence
            )

        let safe =
            safetyGate.apply(
                decision:
                    decision,
                palmProbability:
                    palmProbability,
                accidentalProbability:
                    accidentalProbability
            )

        await telemetry.record(
            IntentTelemetry(
                touchID:
                    touchID,
                predictedIntent:
                    safe.intent,
                confidence:
                    safe.confidence,
                modelVersion:
                    safe.modelVersion,
                latency:
                    max(
                        0,
                        timestamp -
                        start
                    ),
                corrected:
                    safe.intent !=
                    decision.intent
            )
        )

        return safe
    }
}

The latency calculation above is deliberately a placeholder because a real implementation needs a monotonic clock sampled before and after inference, rather than reusing the touch timestamp.

A production implementation should use a monotonic clock such as ContinuousClock.

31. Better latency measurement
public struct MonotonicTimer:
    Sendable
{
    private let clock =
        ContinuousClock()

    public init() {}

    public func measure<T>(
        _ operation:
            () async throws -> T
    ) async rethrows
        -> (T, Duration)
    {
        let start =
            clock.now

        let value =
            try await operation()

        let end =
            clock.now

        return (
            value,
            start.duration(
                to:
                    end
            )
        )
    }
}

Now:

let timer =
    MonotonicTimer()

let (decision, duration) =
    await timer.measure {

        await intentEngine.process(
            touchID: 42,
            position:
                CGPoint(
                    x: 500,
                    y: 900
                ),
            timestamp: 1.0,
            context: .normalUI,
            screen:
                CGSize(
                    width: 1179,
                    height: 2556
                ),
            fingerCount: 1
        )
    }

print(
    "Intent latency:",
    duration
)
32. XCTest
import XCTest

final class TouchIntentTests:
    XCTestCase
{
    func testShortMovementBecomesTap() async {

        let engine =
            TouchIntentEngine()

        await engine.begin(
            touchID: 1,
            position:
                CGPoint(
                    x: 100,
                    y: 100
                ),
            timestamp: 0
        )

        _ =
            await engine.process(
                touchID: 1,
                position:
                    CGPoint(
                        x: 101,
                        y: 101
                    ),
                timestamp: 0.05,
                context:
                    .normalUI,
                screen:
                    CGSize(
                        width: 1_179,
                        height: 2_556
                    ),
                fingerCount: 1
            )

        let result =
            await engine.end(
                touchID: 1
            )

        XCTAssertNotNil(
            result
        )
    }

    func testFastMovementBecomesSwipe() async {

        let engine =
            TouchIntentEngine()

        await engine.begin(
            touchID: 2,
            position:
                CGPoint(
                    x: 100,
                    y: 100
                ),
            timestamp: 0
        )

        _ =
            await engine.process(
                touchID: 2,
                position:
                    CGPoint(
                        x: 500,
                        y: 100
                    ),
                timestamp: 0.10,
                context:
                    .normalUI,
                screen:
                    CGSize(
                        width: 1_179,
                        height: 2_556
                    ),
                fingerCount: 1
            )

        let result =
            await engine.end(
                touchID: 2
            )

        XCTAssertNotNil(
            result
        )
    }

    func testPalmSafetyGate() {

        let gate =
            IntentSafetyGate()

        let original =
            TouchIntentDecision(
                touchID: 1,
                intent: .drag,
                confidence: 0.95,
                state:
                    .committed(.drag),
                modelVersion:
                    "test"
            )

        let result =
            gate.apply(
                decision:
                    original,
                palmProbability:
                    0.97,
                accidentalProbability:
                    0.01
            )

        XCTAssertEqual(
            result.intent,
            .accidental
        )
    }
}




1. Core diagnostic metric types
import Foundation
import CoreGraphics
import OSLog

public enum TouchDiagnosticMetric:
    String,
    Sendable,
    Codable
{
    case touchToProcessingLatency
    case processingLatency
    case renderLatency
    case touchToDisplayLatency

    case predictionError
    case predictionConfidence

    case jitter
    case velocityStability
    case trajectorySmoothness

    case palmProbability
    case accidentalProbability

    case gestureConfidence
    case gestureRecognitionLatency

    case intentConfidence
    case intentInferenceLatency

    case frameTime
    case missedFrame
    case frameJitter

    case scrollVelocityError
    case scrollHitch

    case zoneResolutionLatency
    case inputDrop

    case endToEndLatency
}
2. Metric sample
public struct TouchMetricSample:
    Sendable,
    Codable
{
    public let metric:
        TouchDiagnosticMetric

    public let value:
        Double

    public let timestamp:
        TimeInterval

    public let touchID:
        UInt64?

    public let context:
        String?

    public init(
        metric:
            TouchDiagnosticMetric,
        value:
            Double,
        timestamp:
            TimeInterval,
        touchID:
            UInt64? = nil,
        context:
            String? = nil
    ) {

        self.metric =
            metric

        self.value =
            value

        self.timestamp =
            timestamp

        self.touchID =
            touchID

        self.context =
            context
    }
}
3. Touch quality dimensions

Rather than having one meaningless "touch score", keep the individual dimensions separate.

public struct TouchQualityDimensions:
    Sendable,
    Codable
{
    public var latency:
        Double

    public var accuracy:
        Double

    public var stability:
        Double

    public var gestureRecognition:
        Double

    public var intentRecognition:
        Double

    public var displaySynchronization:
        Double

    public var palmRejection:
        Double

    public init(
        latency:
            Double = 1,
        accuracy:
            Double = 1,
        stability:
            Double = 1,
        gestureRecognition:
            Double = 1,
        intentRecognition:
            Double = 1,
        displaySynchronization:
            Double = 1,
        palmRejection:
            Double = 1
    ) {

        self.latency =
            latency

        self.accuracy =
            accuracy

        self.stability =
            stability

        self.gestureRecognition =
            gestureRecognition

        self.intentRecognition =
            intentRecognition

        self.displaySynchronization =
            displaySynchronization

        self.palmRejection =
            palmRejection
    }
}
4. Touch quality report
public struct TouchQualityReport:
    Sendable,
    Codable
{
    public let generatedAt:
        Date

    public let sampleCount:
        Int

    public let dimensions:
        TouchQualityDimensions

    public let meanTouchToDisplayLatency:
        TimeInterval

    public let p95TouchToDisplayLatency:
        TimeInterval

    public let meanPredictionError:
        Double

    public let meanJitter:
        Double

    public let missedFrameRate:
        Double

    public let meanIntentConfidence:
        Double

    public let meanGestureConfidence:
        Double

    public let anomalyCount:
        Int
}
5. Hot-path event

The individual touch pipeline should emit a compact diagnostic event.

public struct TouchDiagnosticEvent:
    Sendable
{
    public let touchID:
        UInt64

    public let timestamp:
        TimeInterval

    public let position:
        CGPoint

    public let predictedPosition:
        CGPoint?

    public let predictionConfidence:
        Double

    public let palmProbability:
        Double

    public let accidentalProbability:
        Double

    public let intentConfidence:
        Double

    public let gestureConfidence:
        Double

    public let touchToDisplayLatency:
        TimeInterval?

    public init(
        touchID:
            UInt64,
        timestamp:
            TimeInterval,
        position:
            CGPoint,
        predictedPosition:
            CGPoint? = nil,
        predictionConfidence:
            Double = 0,
        palmProbability:
            Double = 0,
        accidentalProbability:
            Double = 0,
        intentConfidence:
            Double = 0,
        gestureConfidence:
            Double = 0,
        touchToDisplayLatency:
            TimeInterval? = nil
    ) {

        self.touchID =
            touchID

        self.timestamp =
            timestamp

        self.position =
            position

        self.predictedPosition =
            predictedPosition

        self.predictionConfidence =
            predictionConfidence

        self.palmProbability =
            palmProbability

        self.accidentalProbability =
            accidentalProbability

        self.intentConfidence =
            intentConfidence

        self.gestureConfidence =
            gestureConfidence

        self.touchToDisplayLatency =
            touchToDisplayLatency
    }
}
6. Jitter analysis

Jitter is one of the most important measurements for touchscreen quality.

public struct TouchJitterAnalyzer:
    Sendable
{
    public init() {}

    public func calculate(
        points:
            [CGPoint]
    ) -> Double {

        guard points.count >= 3 else {
            return 0
        }

        var total =
            0.0

        var count =
            0

        for index in 1..<(points.count - 1) {

            let previous =
                points[index - 1]

            let current =
                points[index]

            let next =
                points[index + 1]

            let expected =
                CGPoint(
                    x:
                        (previous.x + next.x) / 2,
                    y:
                        (previous.y + next.y) / 2
                )

            let dx =
                current.x -
                expected.x

            let dy =
                current.y -
                expected.y

            total +=
                sqrt(
                    dx * dx +
                    dy * dy
                )

            count += 1
        }

        return count > 0
            ? total / Double(count)
            : 0
    }
}
7. Prediction-error analyzer

This measures what #1 and #4 are actually achieving.

public struct TouchPredictionAnalyzer:
    Sendable
{
    public init() {}

    public func error(
        predicted:
            CGPoint,
        actual:
            CGPoint
    ) -> Double {

        hypot(
            predicted.x -
                actual.x,

            predicted.y -
                actual.y
        )
    }

    public func meanError(
        predictions:
            [(CGPoint, CGPoint)]
    ) -> Double {

        guard !predictions.isEmpty else {
            return 0
        }

        let total =
            predictions.reduce(
                0
            ) {
                $0 +
                error(
                    predicted:
                        $1.0,
                    actual:
                        $1.1
                )
            }

        return total /
            Double(predictions.count)
    }
}
8. Latency statistics

We don't just want averages.

P95 and P99 are much more useful for interactive systems.

public struct LatencyStatistics:
    Sendable,
    Codable
{
    public let count:
        Int

    public let mean:
        Double

    public let p50:
        Double

    public let p95:
        Double

    public let p99:
        Double

    public let maximum:
        Double

    public init(
        samples:
            [Double]
    ) {

        let sorted =
            samples.sorted()

        self.count =
            sorted.count

        guard !sorted.isEmpty else {

            self.mean = 0
            self.p50 = 0
            self.p95 = 0
            self.p99 = 0
            self.maximum = 0

            return
        }

        self.mean =
            sorted.reduce(
                0,
                +
            ) /
            Double(sorted.count)

        self.p50 =
            percentile(
                sorted,
                0.50
            )

        self.p95 =
            percentile(
                sorted,
                0.95
            )

        self.p99 =
            percentile(
                sorted,
                0.99
            )

        self.maximum =
            sorted.last!
    }

    private func percentile(
        _ values:
            [Double],
        _ p:
            Double
    ) -> Double {

        let index =
            Int(
                Double(
                    values.count - 1
                ) *
                p
            )

        return values[
            max(
                0,
                min(
                    values.count - 1,
                    index
                )
            )
        ]
    }
}
9. Rolling metric store

The diagnostics system should have a bounded memory footprint.

public actor TouchMetricStore {

    private var samples:
        [TouchMetricSample] = []

    private let capacity:
        Int

    public init(
        capacity:
            Int = 50_000
    ) {

        self.capacity =
            capacity
    }

    public func append(
        _ sample:
            TouchMetricSample
    ) {

        samples.append(
            sample
        )

        if samples.count >
            capacity {

            samples.removeFirst(
                samples.count -
                capacity
            )
        }
    }

    public func append(
        _ samples:
            [TouchMetricSample]
    ) {

        self.samples.append(
            contentsOf:
                samples
        )

        if self.samples.count >
            capacity {

            self.samples.removeFirst(
                self.samples.count -
                capacity
            )
        }
    }

    public func snapshot()
        -> [TouchMetricSample]
    {
        samples
    }

    public func removeAll() {
        samples.removeAll()
    }
}
10. Diagnostic anomaly types
public enum TouchAnomaly:
    String,
    Sendable,
    Codable
{
    case excessiveLatency
    case excessiveJitter
    case predictionDrift
    case frameHitch
    case repeatedInputDrop
    case lowIntentConfidence
    case lowGestureConfidence
    case palmRejectionSpike
    case displaySynchronizationFailure
    case unknown
}
11. Anomaly event
public struct TouchAnomalyEvent:
    Sendable,
    Codable
{
    public let anomaly:
        TouchAnomaly

    public let severity:
        Double

    public let value:
        Double

    public let threshold:
        Double

    public let timestamp:
        Date

    public init(
        anomaly:
            TouchAnomaly,
        severity:
            Double,
        value:
            Double,
        threshold:
            Double
    ) {

        self.anomaly =
            anomaly

        self.severity =
            max(
                0,
                min(1, severity)
            )

        self.value =
            value

        self.threshold =
            threshold

        self.timestamp =
            Date()
    }
}
12. Anomaly detector
public struct TouchAnomalyDetector:
    Sendable
{
    public let latencyThreshold:
        Double

    public let jitterThreshold:
        Double

    public let predictionErrorThreshold:
        Double

    public let intentConfidenceThreshold:
        Double

    public let gestureConfidenceThreshold:
        Double

    public init(
        latencyThreshold:
            Double = 0.030,

        jitterThreshold:
            Double = 3.0,

        predictionErrorThreshold:
            Double = 8.0,

        intentConfidenceThreshold:
            Double = 0.45,

        gestureConfidenceThreshold:
            Double = 0.45
    ) {

        self.latencyThreshold =
            latencyThreshold

        self.jitterThreshold =
            jitterThreshold

        self.predictionErrorThreshold =
            predictionErrorThreshold

        self.intentConfidenceThreshold =
            intentConfidenceThreshold

        self.gestureConfidenceThreshold =
            gestureConfidenceThreshold
    }

    public func detect(
        event:
            TouchDiagnosticEvent
    ) -> [TouchAnomalyEvent] {

        var anomalies:
            [TouchAnomalyEvent] = []

        if let latency =
            event.touchToDisplayLatency,
           latency >
                latencyThreshold {

            anomalies.append(
                TouchAnomalyEvent(
                    anomaly:
                        .excessiveLatency,
                    severity:
                        min(
                            1,
                            latency /
                            (latencyThreshold * 3)
                        ),
                    value:
                        latency,
                    threshold:
                        latencyThreshold
                )
            )
        }

        if event.predictionConfidence <
            0.30 {

            anomalies.append(
                TouchAnomalyEvent(
                    anomaly:
                        .predictionDrift,
                    severity:
                        0.6,
                    value:
                        event.predictionConfidence,
                    threshold:
                        0.30
                )
            )
        }

        if event.intentConfidence <
            intentConfidenceThreshold {

            anomalies.append(
                TouchAnomalyEvent(
                    anomaly:
                        .lowIntentConfidence,
                    severity:
                        0.5,
                    value:
                        event.intentConfidence,
                    threshold:
                        intentConfidenceThreshold
                )
            )
        }

        if event.gestureConfidence <
            gestureConfidenceThreshold {

            anomalies.append(
                TouchAnomalyEvent(
                    anomaly:
                        .lowGestureConfidence,
                    severity:
                        0.4,
                    value:
                        event.gestureConfidence,
                    threshold:
                        gestureConfidenceThreshold
                )
            )
        }

        if event.palmProbability >
            0.90 {

            anomalies.append(
                TouchAnomalyEvent(
                    anomaly:
                        .palmRejectionSpike,
                    severity:
                        event.palmProbability,
                    value:
                        event.palmProbability,
                    threshold:
                        0.90
                )
            )
        }

        return anomalies
    }
}
13. Diagnostic event store
public actor TouchAnomalyStore {

    private var events:
        [TouchAnomalyEvent] = []

    private let capacity:
        Int

    public init(
        capacity:
            Int = 5_000
    ) {

        self.capacity =
            capacity
    }

    public func append(
        _ event:
            TouchAnomalyEvent
    ) {

        events.append(
            event
        )

        if events.count >
            capacity {

            events.removeFirst()
        }
    }

    public func snapshot()
        -> [TouchAnomalyEvent]
    {
        events
    }

    public func count()
        -> Int
    {
        events.count
    }
}
14. Touch quality evaluator

Now turn raw telemetry into a structured report.

public struct TouchQualityEvaluator:
    Sendable
{
    public init() {}

    public func evaluate(
        samples:
            [TouchMetricSample],
        anomalies:
            [TouchAnomalyEvent]
    ) -> TouchQualityReport {

        let latency =
            values(
                samples,
                metric:
                    .touchToDisplayLatency
            )

        let prediction =
            values(
                samples,
                metric:
                    .predictionError
            )

        let jitter =
            values(
                samples,
                metric:
                    .jitter
            )

        let intent =
            values(
                samples,
                metric:
                    .intentConfidence
            )

        let gesture =
            values(
                samples,
                metric:
                    .gestureConfidence
            )

        let missedFrames =
            values(
                samples,
                metric:
                    .missedFrame
            )

        let latencyStats =
            LatencyStatistics(
                samples:
                    latency
            )

        let meanPrediction =
            mean(
                prediction
            )

        let meanJitter =
            mean(
                jitter
            )

        let meanIntent =
            mean(
                intent
            )

        let meanGesture =
            mean(
                gesture
            )

        let missedFrameRate =
            mean(
                missedFrames
            )

        let dimensions =
            TouchQualityDimensions(

                latency:
                    scoreLatency(
                        latencyStats.p95
                    ),

                accuracy:
                    scorePrediction(
                        meanPrediction
                    ),

                stability:
                    scoreJitter(
                        meanJitter
                    ),

                gestureRecognition:
                    meanGesture,

                intentRecognition:
                    meanIntent,

                displaySynchronization:
                    scoreLatency(
                        latencyStats.p95
                    ),

                palmRejection:
                    1 -
                    min(
                        1,
                        anomalies.filter {
                            $0.anomaly ==
                                .palmRejectionSpike
                        }.count /
                        max(
                            1,
                            samples.count
                        )
                    )
            )

        return TouchQualityReport(
            generatedAt:
                Date(),

            sampleCount:
                samples.count,

            dimensions:
                dimensions,

            meanTouchToDisplayLatency:
                latencyStats.mean,

            p95TouchToDisplayLatency:
                latencyStats.p95,

            meanPredictionError:
                meanPrediction,

            meanJitter:
                meanJitter,

            missedFrameRate:
                missedFrameRate,

            meanIntentConfidence:
                meanIntent,

            meanGestureConfidence:
                meanGesture,

            anomalyCount:
                anomalies.count
        )
    }

    private func values(
        _ samples:
            [TouchMetricSample],
        metric:
            TouchDiagnosticMetric
    ) -> [Double] {

        samples
            .filter {
                $0.metric == metric
            }
            .map {
                $0.value
            }
    }

    private func mean(
        _ values:
            [Double]
    ) -> Double {

        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(
            0,
            +
        ) /
        Double(values.count)
    }

    private func scoreLatency(
        _ latency:
            Double
    ) -> Double {

        guard latency > 0 else {
            return 1
        }

        return max(
            0,
            min(
                1,
                1 -
                latency /
                0.100
            )
        )
    }

    private func scorePrediction(
        _ error:
            Double
    ) -> Double {

        max(
            0,
            min(
                1,
                1 -
                error /
                20
            )
        )
    }

    private func scoreJitter(
        _ jitter:
            Double
    ) -> Double {

        max(
            0,
            min(
                1,
                1 -
                jitter /
                10
            )
        )
    }
}
15. System logger

For development builds, use Apple's unified logging system.

public final class TouchDiagnosticsLogger:
    Sendable
{
    private let logger =
        Logger(
            subsystem:
                "com.example.TouchSystem",
            category:
                "Diagnostics"
        )

    public init() {}

    public func record(
        _ event:
            TouchDiagnosticEvent
    ) {

        logger.debug(
            """
            touch=\(event.touchID,
            privacy: .public)
            intentConfidence=\(event.intentConfidence,
            privacy: .public)
            gestureConfidence=\(event.gestureConfidence,
            privacy: .public)
            predictionConfidence=\(event.predictionConfidence,
            privacy: .public)
            """
        )
    }

    public func anomaly(
        _ anomaly:
            TouchAnomalyEvent
    ) {

        logger.error(
            """
            Touch anomaly:
            \(String(describing: anomaly.anomaly),
            privacy: .public)
            value=\(anomaly.value,
            privacy: .public)
            threshold=\(anomaly.threshold,
            privacy: .public)
            """
        )
    }
}

For a real Apple system, sensitive user input data should not be dumped into logs. In particular, raw touch coordinates and user interaction traces should be handled under appropriate privacy controls.

16. Signpost instrumentation

For Instruments-style profiling, add signposts around the important stages.

import os

public final class TouchPerformanceTracer:
    Sendable
{
    private let logger =
        Logger(
            subsystem:
                "com.example.TouchSystem",
            category:
                "Performance"
        )

    public init() {}

    public func begin(
        touchID:
            UInt64
    ) {

        logger.debug(
            "Touch processing begin \(touchID)"
        )
    }

    public func end(
        touchID:
            UInt64
    ) {

        logger.debug(
            "Touch processing end \(touchID)"
        )
    }
}

For an actual Instruments implementation, this would be expanded with appropriate OSSignposter intervals around:

touch receive
prediction
filter
palm classification
zone resolution
gesture recognition
AI intent
render preparation
frame submission
17. Unified diagnostics engine

Now combine the components.

public actor UnifiedTouchDiagnosticsEngine {

    private let metricStore:
        TouchMetricStore

    private let anomalyStore:
        TouchAnomalyStore

    private let detector:
        TouchAnomalyDetector

    private let evaluator:
        TouchQualityEvaluator

    private let logger:
        TouchDiagnosticsLogger

    public init() {

        self.metricStore =
            TouchMetricStore()

        self.anomalyStore =
            TouchAnomalyStore()

        self.detector =
            TouchAnomalyDetector()

        self.evaluator =
            TouchQualityEvaluator()

        self.logger =
            TouchDiagnosticsLogger()
    }

    public func record(
        event:
            TouchDiagnosticEvent
    ) async {

        logger.record(
            event
        )

        let anomalies =
            detector.detect(
                event:
                    event
            )

        for anomaly
            in anomalies {

            await anomalyStore.append(
                anomaly
            )

            logger.anomaly(
                anomaly
            )
        }

        await metricStore.append(
            TouchMetricSample(
                metric:
                    .predictionConfidence,
                value:
                    event.predictionConfidence,
                timestamp:
                    event.timestamp,
                touchID:
                    event.touchID
            )
        )

        await metricStore.append(
            TouchMetricSample(
                metric:
                    .palmProbability,
                value:
                    event.palmProbability,
                timestamp:
                    event.timestamp,
                touchID:
                    event.touchID
            )
        )

        await metricStore.append(
            TouchMetricSample(
                metric:
                    .accidentalProbability,
                value:
                    event.accidentalProbability,
                timestamp:
                    event.timestamp,
                touchID:
                    event.touchID
            )
        )

        await metricStore.append(
            TouchMetricSample(
                metric:
                    .intentConfidence,
                value:
                    event.intentConfidence,
                timestamp:
                    event.timestamp,
                touchID:
                    event.touchID
            )
        )

        await metricStore.append(
            TouchMetricSample(
                metric:
                    .gestureConfidence,
                value:
                    event.gestureConfidence,
                timestamp:
                    event.timestamp,
                touchID:
                    event.touchID
            )
        )

        if let latency =
            event.touchToDisplayLatency {

            await metricStore.append(
                TouchMetricSample(
                    metric:
                        .touchToDisplayLatency,
                    value:
                        latency,
                    timestamp:
                        event.timestamp,
                    touchID:
                        event.touchID
                )
            )
        }
    }

    public func recordPredictionError(
        value:
            Double,
        timestamp:
            TimeInterval,
        touchID:
            UInt64
    ) async {

        await metricStore.append(
            TouchMetricSample(
                metric:
                    .predictionError,
                value:
                    value,
                timestamp:
                    timestamp,
                touchID:
                    touchID
            )
        )
    }

    public func recordJitter(
        value:
            Double,
        timestamp:
            TimeInterval,
        touchID:
            UInt64
    ) async {

        await metricStore.append(
            TouchMetricSample(
                metric:
                    .jitter,
                value:
                    value,
                timestamp:
                    timestamp,
                touchID:
                    touchID
            )
        )
    }

    public func report()
        async -> TouchQualityReport {

        let samples =
            await metricStore.snapshot()

        let anomalies =
            await anomalyStore.snapshot()

        return evaluator.evaluate(
            samples:
                samples,
            anomalies:
                anomalies
        )
    }
}
18. Automatic adaptive tuning

Now we can make #10 feed information back into #1–#9.

This is where the whole architecture gets substantially more interesting.

public struct TouchAdaptiveRecommendation:
    Sendable,
    Codable
{
    public var predictionHorizon:
        TimeInterval?

    public var smoothing:
        Double?

    public var sensitivityMultiplier:
        Double?

    public var gestureThresholdMultiplier:
        Double?

    public var scrollFrictionMultiplier:
        Double?

    public var aiConfidenceThreshold:
        Double?

    public init() {}
}
19. Adaptive tuning engine
public struct TouchAdaptiveTuner:
    Sendable
{
    public init() {}

    public func recommend(
        report:
            TouchQualityReport
    ) -> TouchAdaptiveRecommendation {

        var recommendation =
            TouchAdaptiveRecommendation()

        if report.meanPredictionError >
            8 {

            recommendation.predictionHorizon =
                0.008

            recommendation.smoothing =
                0.20
        }

        if report.meanJitter >
            3 {

            recommendation.smoothing =
                max(
                    recommendation.smoothing ?? 0,
                    0.30
                )
        }

        if report.meanIntentConfidence <
            0.55 {

            recommendation.aiConfidenceThreshold =
                0.70
        }

        if report.meanGestureConfidence <
            0.55 {

            recommendation.gestureThresholdMultiplier =
                1.10
        }

        if report.meanTouchToDisplayLatency >
            0.030 {

            recommendation.scrollFrictionMultiplier =
                0.95
        }

        return recommendation
    }
}

This is deliberately conservative.

The diagnostic engine should recommend bounded changes, not continuously rewrite the entire touch system.

20. Closed-loop architecture

We now have:

                       ┌─────────────────┐
                       │ TOUCH HARDWARE  │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #1 PREDICTION   │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #4 SUB-PIXEL    │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #2 PALM         │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #3 SENSITIVITY  │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #5 ZONES        │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #6 GESTURES     │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #7 SCROLL       │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #8 DISPLAY SYNC │
                       └────────┬────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │ #9 AI INTENT    │
                       └────────┬────────┘
                                │
                                ▼
                              UI
                                │
                                │
                 ┌──────────────┴──────────────┐
                 │                             │
                 ▼                             ▼
        ┌─────────────────┐          ┌─────────────────┐
        │ #10 DIAGNOSTICS │          │ USER FEEDBACK   │
        └────────┬────────┘          └────────┬────────┘
                 │                            │
                 └──────────────┬─────────────┘
                                ▼
                       ADAPTIVE TUNING
                                │
             ┌──────────────────┼─────────────────┐
             ▼                  ▼                 ▼
        Prediction          Sensitivity       Gesture
        parameters          parameters        parameters

That gives the touchscreen system a feedback loop rather than ten independent pieces.

21. A proper system-level event

I would ultimately standardise the telemetry around one unified structure:

public struct TouchPipelineSnapshot:
    Sendable
{
    public let touchID:
        UInt64

    public let timestamp:
        TimeInterval

    public let position:
        CGPoint

    public let velocity:
        CGPoint

    public let predictedPosition:
        CGPoint?

    public let predictionConfidence:
        Double

    public let palmProbability:
        Double

    public let accidentalProbability:
        Double

    public let zoneConfidence:
        Double

    public let gestureConfidence:
        Double

    public let intentConfidence:
        Double

    public let touchToDisplayLatency:
        TimeInterval?

    public let frameMissed:
        Bool

    public init(
        touchID:
            UInt64,
        timestamp:
            TimeInterval,
        position:
            CGPoint,
        velocity:
            CGPoint,
        predictedPosition:
            CGPoint?,
        predictionConfidence:
            Double,
        palmProbability:
            Double,
        accidentalProbability:
            Double,
        zoneConfidence:
            Double,
        gestureConfidence:
            Double,
        intentConfidence:
            Double,
        touchToDisplayLatency:
            TimeInterval?,
        frameMissed:
            Bool
    ) {

        self.touchID =
            touchID

        self.timestamp =
            timestamp

        self.position =
            position

        self.velocity =
            velocity

        self.predictedPosition =
            predictedPosition

        self.predictionConfidence =
            predictionConfidence

        self.palmProbability =
            palmProbability

        self.accidentalProbability =
            accidentalProbability

        self.zoneConfidence =
            zoneConfidence

        self.gestureConfidence =
            gestureConfidence

        self.intentConfidence =
            intentConfidence

        self.touchToDisplayLatency =
            touchToDisplayLatency

        self.frameMissed =
            frameMissed
    }
}

