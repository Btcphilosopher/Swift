```swift
//
//  ThreeDMeasurementEngine.swift
//
//  iOS 3D measurement foundation
//
//  Uses:
//    ARKit
//    RealityKit
//    SceneKit
//    CoreGraphics
//
//  Architecture:
//
//  Camera / LiDAR
//        ↓
//  ARSession
//        ↓
//  World Tracking
//        ↓
//  Depth
//        ↓
//  Feature Points
//        ↓
//  3D Geometry
//        ↓
//  Measurements
//
//  Suitable for:
//    - distance measurement
//    - point-to-point measurement
//    - room dimensions
//    - object dimensions
//    - plane detection
//    - height measurements
//    - area estimation
//    - volume estimation
//

import Foundation
import ARKit
import RealityKit
import UIKit
import simd

// MARK: - 3D Point

struct MeasurementPoint: Identifiable {

    let id = UUID()

    let position: SIMD3<Float>

    let timestamp: TimeInterval

    init(
        position: SIMD3<Float>,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.position = position
        self.timestamp = timestamp
    }
}


// MARK: - Measurement Result

struct MeasurementResult {

    let start: MeasurementPoint
    let end: MeasurementPoint

    var distanceMeters: Float {

        simd_distance(
            start.position,
            end.position
        )
    }

    var distanceCentimeters: Float {

        distanceMeters * 100
    }

    var distanceMillimeters: Float {

        distanceMeters * 1000
    }

    var distanceInches: Float {

        distanceMeters * 39.3701
    }

    var distanceFeet: Float {

        distanceMeters * 3.28084
    }
}


// MARK: - 3D Plane

struct DetectedPlane {

    let identifier: UUID

    let center: SIMD3<Float>

    let extent: SIMD2<Float>

    let alignment: ARPlaneAnchor.Alignment

    var areaSquareMeters: Float {

        extent.x * extent.y
    }
}


// MARK: - Bounding Box

struct BoundingBox3D {

    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>

    var width: Float {

        maximum.x - minimum.x
    }

    var height: Float {

        maximum.y - minimum.y
    }

    var depth: Float {

        maximum.z - minimum.z
    }

    var volume: Float {

        abs(width * height * depth)
    }
}


// MARK: - Measurement State

enum MeasurementMode {

    case idle
    case scanning
    case measuring
    case completed
}


// MARK: - 3D Measurement Engine

final class ThreeDMeasurementEngine:
    NSObject,
    ObservableObject,
    ARSessionDelegate {

    @Published
    private(set) var mode: MeasurementMode = .idle

    @Published
    private(set) var currentPoint: MeasurementPoint?

    @Published
    private(set) var measurement: MeasurementResult?

    @Published
    private(set) var planes: [DetectedPlane] = []

    @Published
    private(set) var trackingState: ARCamera.TrackingState = .notAvailable

    @Published
    private(set) var featurePointCount: Int = 0

    private let session = ARSession()

    private(set) var latestFrame: ARFrame?

    override init() {

        super.init()

        session.delegate = self
    }


    // MARK: Start Scanning

    func start() {

        let configuration = ARWorldTrackingConfiguration()

        configuration.planeDetection = [
            .horizontal,
            .vertical
        ]

        if ARWorldTrackingConfiguration.supportsFrameSemantics(
            .sceneDepth
        ) {

            configuration.frameSemantics.insert(
                .sceneDepth
            )
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(
            .smoothedSceneDepth
        ) {

            configuration.frameSemantics.insert(
                .smoothedSceneDepth
            )
        }

        session.run(
            configuration,
            options: [
                .resetTracking,
                .removeExistingAnchors
            ]
        )

        mode = .scanning
    }


    // MARK: Stop

    func stop() {

        session.pause()

        mode = .idle
    }


    // MARK: Access AR Session

    func getSession() -> ARSession {

        session
    }


    // MARK: Place First Point

    func placeFirstPoint(
        _ point: SIMD3<Float>
    ) {

        currentPoint = MeasurementPoint(
            position: point
        )

        measurement = nil

        mode = .measuring
    }


    // MARK: Place Second Point

    func placeSecondPoint(
        _ point: SIMD3<Float>
    ) {

        guard let first = currentPoint else {

            placeFirstPoint(point)

            return
        }

        let second = MeasurementPoint(
            position: point
        )

        measurement = MeasurementResult(
            start: first,
            end: second
        )

        mode = .completed
    }


    // MARK: Reset

    func resetMeasurement() {

        currentPoint = nil

        measurement = nil

        mode = .scanning
    }


    // MARK: Camera Position

    func cameraPosition() -> SIMD3<Float>? {

        guard
            let frame = latestFrame
        else {
            return nil
        }

        let transform =
            frame.camera.transform

        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }


    // MARK: ARSession Delegate

    func session(
        _ session: ARSession,
        didUpdate frame: ARFrame
    ) {

        latestFrame = frame

        featurePointCount =
            frame.rawFeaturePoints?.points.count ?? 0
    }


    func session(
        _ session: ARSession,
        cameraDidChangeTrackingState camera: ARCamera
    ) {

        DispatchQueue.main.async {

            self.trackingState =
                camera.trackingState
        }
    }


    func session(
        _ session: ARSession,
        didAdd anchors: [ARAnchor]
    ) {

        updatePlanes()
    }


    func session(
        _ session: ARSession,
        didUpdate anchors: [ARAnchor]
    ) {

        updatePlanes()
    }


    private func updatePlanes() {

        let detected = session.currentFrame?
            .anchors
            .compactMap { anchor -> DetectedPlane? in

                guard
                    let plane =
                        anchor as? ARPlaneAnchor
                else {
                    return nil
                }

                return DetectedPlane(
                    identifier: plane.identifier,
                    center: SIMD3<Float>(
                        plane.transform.columns.3.x,
                        plane.transform.columns.3.y,
                        plane.transform.columns.3.z
                    ),
                    extent: plane.planeExtent,
                    alignment: plane.alignment
                )
            }

        DispatchQueue.main.async {

            self.planes = detected ?? []
        }
    }
}


// MARK: - Raycast Measurement

extension ThreeDMeasurementEngine {

    func worldPoint(
        from screenPoint: CGPoint,
        in view: ARView
    ) -> SIMD3<Float>? {

        let results =
            view.raycast(
                from: screenPoint,
                allowing: .estimatedPlane,
                alignment: .any
            )

        guard
            let result = results.first
        else {
            return nil
        }

        let transform =
            result.worldTransform

        return SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }
}


// MARK: - Distance Formatter

struct MeasurementFormatter {

    static func meters(
        _ value: Float
    ) -> String {

        if value < 1 {

            return String(
                format: "%.0f cm",
                value * 100
            )
        }

        return String(
            format: "%.2f m",
            value
        )
    }


    static func imperial(
        _ value: Float
    ) -> String {

        let totalInches =
            value * 39.3701

        let feet =
            Int(totalInches / 12)

        let inches =
            totalInches.truncatingRemainder(
                dividingBy: 12
            )

        return String(
            format: "%d ft %.1f in",
            feet,
            inches
        )
    }
}


// MARK: - Depth Sampler

final class DepthSampler {

    func depthMap(
        from frame: ARFrame
    ) -> CVPixelBuffer? {

        if let depth =
            frame.smoothedSceneDepth {

            return depth.depthMap
        }

        if let depth =
            frame.sceneDepth {

            return depth.depthMap
        }

        return nil
    }


    func sampleDepth(
        frame: ARFrame,
        x: Int,
        y: Int
    ) -> Float? {

        guard
            let depthMap =
                depthMap(from: frame)
        else {
            return nil
        }

        CVPixelBufferLockBaseAddress(
            depthMap,
            .readOnly
        )

        defer {

            CVPixelBufferUnlockBaseAddress(
                depthMap,
                .readOnly
            )
        }

        let width =
            CVPixelBufferGetWidth(depthMap)

        let height =
            CVPixelBufferGetHeight(depthMap)

        guard
            x >= 0,
            x < width,
            y >= 0,
            y < height
        else {
            return nil
        }

        guard
            let base =
                CVPixelBufferGetBaseAddress(depthMap)
        else {
            return nil
        }

        let bytesPerRow =
            CVPixelBufferGetBytesPerRow(depthMap)

        let row =
            base
                .advanced(
                    by: y * bytesPerRow
                )
                .assumingMemoryBound(
                    to: Float32.self
                )

        let value = row[x]

        guard
            value.isFinite,
            value > 0
        else {
            return nil
        }

        return value
    }
}


// MARK: - 3D Point Cloud

struct PointCloud {

    var points: [SIMD3<Float>] = []

    var count: Int {

        points.count
    }

    func boundingBox() -> BoundingBox3D? {

        guard
            let first = points.first
        else {
            return nil
        }

        var minimum = first
        var maximum = first

        for point in points {

            minimum = simd_min(
                minimum,
                point
            )

            maximum = simd_max(
                maximum,
                point
            )
        }

        return BoundingBox3D(
            minimum: minimum,
            maximum: maximum
        )
    }
}


// MARK: - Point Cloud Analyzer

final class PointCloudAnalyzer {

    func boundingBox(
        points: [SIMD3<Float>]
    ) -> BoundingBox3D? {

        guard
            let first = points.first
        else {
            return nil
        }

        var minPoint = first
        var maxPoint = first

        for point in points {

            minPoint = simd_min(
                minPoint,
                point
            )

            maxPoint = simd_max(
                maxPoint,
                point
            )
        }

        return BoundingBox3D(
            minimum: minPoint,
            maximum: maxPoint
        )
    }


    func center(
        points: [SIMD3<Float>]
    ) -> SIMD3<Float>? {

        guard !points.isEmpty else {
            return nil
        }

        var total =
            SIMD3<Float>(0, 0, 0)

        for point in points {

            total += point
        }

        return total /
            Float(points.count)
    }
}


// MARK: - Measurement Statistics

struct MeasurementStatistics {

    let samples: [Float]

    var mean: Float {

        guard !samples.isEmpty else {
            return 0
        }

        return samples.reduce(
            0,
            +
        ) / Float(samples.count)
    }

    var minimum: Float {

        samples.min() ?? 0
    }

    var maximum: Float {

        samples.max() ?? 0
    }

    var range: Float {

        maximum - minimum
    }

    var standardDeviation: Float {

        guard samples.count > 1 else {
            return 0
        }

        let average = mean

        let variance =
            samples.reduce(
                0
            ) {

                partial,
                value in

                partial +
                pow(
                    value - average,
                    2
                )
            }
            /
            Float(samples.count - 1)

        return sqrt(variance)
    }
}


// MARK: - Accuracy Estimator

struct MeasurementAccuracyEstimator {

    static func confidence(
        samples: [Float]
    ) -> Float {

        guard
            samples.count >= 2
        else {
            return 0.2
        }

        let statistics =
            MeasurementStatistics(
                samples: samples
            )

        let variation =
            statistics.standardDeviation

        if variation < 0.002 {

            return 0.99
        }

        if variation < 0.005 {

            return 0.95
        }

        if variation < 0.01 {

            return 0.85
        }

        if variation < 0.02 {

            return 0.70
        }

        return 0.40
    }
}
```

### How I would turn this into a serious measurement system

The next layer would be a **measurement pipeline**:

```text
             iPhone / iPad
                   │
             RGB Camera
                   │
             LiDAR Sensor
                   │
                   ▼
              ARKit
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
     Depth       Planes     Features
       │           │           │
       └───────────┼───────────┘
                   ▼
             3D Point Cloud
                   │
          ┌────────┴────────┐
          ▼                 ▼
     Geometry             Objects
     Analysis            Detection
          │                 │
          └────────┬────────┘
                   ▼
          Measurement Engine
                   │
       ┌───────────┼───────────┐
       ▼           ▼           ▼
    Length       Area        Volume
       │           │           │
       └───────────┼───────────┘
                   ▼
             Confidence
                   │
                   ▼
              Final Result
```

The particularly useful addition would be **multi-frame averaging**. Instead of measuring a line once, the engine could measure the same two points over 20–50 frames and statistically reject noisy depth readings. That would make the system substantially more stable.

For example:

```text
Frame 1    2.417 m
Frame 2    2.421 m
Frame 3    2.416 m
...
Frame 40   2.419 m

                  ↓

Estimated distance
      2.419 m

Confidence
      97.4%
```

And this is where your earlier **Julia optimisation idea** fits very naturally: Swift/ARKit handles the sensor and real-time geometry, while Julia can perform **point-cloud registration, outlier rejection, geometric fitting, uncertainty estimation and optimisation**.


