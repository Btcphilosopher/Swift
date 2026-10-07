Bezelfreeidisplay

Swift — BezelFreeDisplay.swift
import SwiftUI

// MARK: - Display Geometry

struct DisplayGeometry {
    let width: Double
    let height: Double
    let cornerRadius: Double

    let topOcclusion: Double
    let bottomOcclusion: Double
    let leftOcclusion: Double
    let rightOcclusion: Double

    let interactionMargin: Double

    var safeRect: CGRect {
        CGRect(
            x: leftOcclusion + interactionMargin,
            y: topOcclusion + interactionMargin,
            width: width
                - leftOcclusion
                - rightOcclusion
                - interactionMargin * 2,
            height: height
                - topOcclusion
                - bottomOcclusion
                - interactionMargin * 2
        )
    }
}

// MARK: - Display Zones

enum DisplayZone {
    case center
    case edge
    case corner
    case occluded
    case interactionSafe
}

// MARK: - Bezel-Free Engine

final class BezelFreeEngine: ObservableObject {

    @Published var geometry: DisplayGeometry

    init(width: Double,
         height: Double,
         cornerRadius: Double = 42,
         topOcclusion: Double = 0,
         bottomOcclusion: Double = 0,
         leftOcclusion: Double = 0,
         rightOcclusion: Double = 0) {

        geometry = DisplayGeometry(
            width: width,
            height: height,
            cornerRadius: cornerRadius,
            topOcclusion: topOcclusion,
            bottomOcclusion: bottomOcclusion,
            leftOcclusion: leftOcclusion,
            rightOcclusion: rightOcclusion,
            interactionMargin: 18
        )
    }

    func zone(x: Double, y: Double) -> DisplayZone {

        let edge = 40.0

        if x < geometry.leftOcclusion ||
           x > geometry.width - geometry.rightOcclusion ||
           y < geometry.topOcclusion ||
           y > geometry.height - geometry.bottomOcclusion {
            return .occluded
        }

        let horizontalEdge =
            x < edge ||
            x > geometry.width - edge

        let verticalEdge =
            y < edge ||
            y > geometry.height - edge

        if horizontalEdge && verticalEdge {
            return .corner
        }

        if horizontalEdge || verticalEdge {
            return .edge
        }

        if geometry.safeRect.contains(CGPoint(x: x, y: y)) {
            return .interactionSafe
        }

        return .center
    }

    func edgeDistance(x: Double, y: Double) -> Double {

        let distances = [
            x,
            geometry.width - x,
            y,
            geometry.height - y
        ]

        return distances.min() ?? 0
    }

    func interactionRadius(x: Double, y: Double) -> Double {

        let distance = edgeDistance(x: x, y: y)

        // Controls near the physical edge become easier to hit.
        return max(
            22,
            min(44, 44 - distance * 0.12)
        )
    }
}
SwiftUI interface
import SwiftUI

struct BezelFreeView: View {

    @StateObject private var engine =
        BezelFreeEngine(
            width: 1179,
            height: 2556,
            cornerRadius: 45
        )

    @State private var brightness = 0.72
    @State private var time = Date()

    var body: some View {

        GeometryReader { proxy in

            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {

                // Full physical display
                Color.black
                    .ignoresSafeArea()

                // Main visual field
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.black,
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea()

                // Main content
                VStack(spacing: 0) {

                    HStack {

                        Text("AUREOM")
                            .font(
                                .system(
                                    size: 13,
                                    weight: .medium,
                                    design: .monospaced
                                )
                            )

                        Spacer()

                        Text("DISPLAY")
                            .font(
                                .system(
                                    size: 13,
                                    weight: .regular,
                                    design: .monospaced
                                )
                            )
                            .opacity(0.5)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 12)

                    Spacer()

                    VStack(spacing: 8) {

                        Text(currentTime)
                            .font(
                                .system(
                                    size: 72,
                                    weight: .thin,
                                    design: .rounded
                                )
                            )
                            .monospacedDigit()

                        Text("CONTINUOUS SURFACE")
                            .font(
                                .system(
                                    size: 11,
                                    weight: .medium,
                                    design: .monospaced
                                )
                            )
                            .tracking(3)
                            .opacity(0.45)
                    }

                    Spacer()

                    HStack {

                        EdgeButton(
                            systemImage: "minus",
                            action: {
                                brightness =
                                    max(0, brightness - 0.05)
                            }
                        )

                        Spacer()

                        VStack(spacing: 5) {

                            Text(
                                "\(Int(brightness * 100))%"
                            )
                            .font(
                                .system(
                                    size: 13,
                                    design: .monospaced
                                )
                            )

                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 120, height: 3)
                                .overlay(alignment: .leading) {

                                    Capsule()
                                        .fill(Color.white)
                                        .frame(
                                            width: 120 * brightness,
                                            height: 3
                                        )
                                }
                        }

                        Spacer()

                        EdgeButton(
                            systemImage: "plus",
                            action: {
                                brightness =
                                    min(1, brightness + 0.05)
                            }
                        )
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
                }

                // Edge information layer
                EdgeInformation(width: width, height: height)
            }
        }
        .ignoresSafeArea()
    }

    private var currentTime: String {

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        return formatter.string(from: time)
    }
}
Edge UI
struct EdgeInformation: View {

    let width: CGFloat
    let height: CGFloat

    var body: some View {

        ZStack {

            // Left edge
            VStack {

                Spacer()

                Text("◉")
                    .font(.system(size: 10))
                    .padding(.leading, 8)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right edge
            VStack {

                Text("72")
                    .font(
                        .system(
                            size: 10,
                            design: .monospaced
                        )
                    )
                    .padding(.trailing, 8)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Bottom edge
            HStack {

                Text("LTE")
                Spacer()
                Text("BAT 91%")
            }
            .font(
                .system(
                    size: 9,
                    design: .monospaced
                )
            )
            .opacity(0.35)
            .padding(.horizontal, 16)
            .frame(
                maxHeight: .infinity,
                alignment: .bottom
            )
            .padding(.bottom, 4)
        }
        .allowsHitTesting(false)
    }
}
Adaptive edge button
struct EdgeButton: View {

    let systemImage: String
    let action: () -> Void

    var body: some View {

        Button(action: action) {

            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
Julia — display_engine.jl

This is the mathematical side of the system.

module BezelFreeDisplay

export DisplaySurface,
       safe_region,
       edge_distance,
       interaction_radius,
       visual_pressure,
       optimal_position

struct DisplaySurface
    width::Float64
    height::Float64
    corner_radius::Float64

    top_occlusion::Float64
    bottom_occlusion::Float64
    left_occlusion::Float64
    right_occlusion::Float64
end


function safe_region(d::DisplaySurface)

    x = d.left_occlusion
    y = d.top_occlusion

    width =
        d.width -
        d.left_occlusion -
        d.right_occlusion

    height =
        d.height -
        d.top_occlusion -
        d.bottom_occlusion

    return (
        x = x,
        y = y,
        width = width,
        height = height
    )
end


function edge_distance(
    d::DisplaySurface,
    x::Float64,
    y::Float64
)

    return minimum([
        x,
        d.width - x,
        y,
        d.height - y
    ])
end


function interaction_radius(
    d::DisplaySurface,
    x::Float64,
    y::Float64
)

    distance = edge_distance(d, x, y)

    # Larger hit targets near the physical edge.
    return clamp(
        44.0 - distance * 0.12,
        22.0,
        44.0
    )
end


function visual_pressure(
    x1::Float64,
    y1::Float64,
    importance1::Float64,
    x2::Float64,
    y2::Float64,
    importance2::Float64
)

    distance = hypot(
        x1 - x2,
        y1 - y2
    )

    return (
        importance1 *
        importance2
    ) / max(distance^2, 1.0)
end


function optimal_position(
    d::DisplaySurface,
    candidates
)

    best_position = nothing
    best_score = Inf

    for candidate in candidates

        x = candidate.x
        y = candidate.y

        score = 0.0

        # Penalise proximity to dangerous edges.
        edge = edge_distance(d, x, y)

        if edge < 25
            score += 1000
        end

        # Penalise corners.
        if x < 40 || x > d.width - 40
            score += 100
        end

        if y < 40 || y > d.height - 40
            score += 100
        end

        if score < best_score
            best_score = score
            best_position = candidate
        end
    end

    return best_position
end

end
Julia test
using .BezelFreeDisplay

display = DisplaySurface(
    1179.0,
    2556.0,
    45.0,
    0.0,
    0.0,
    0.0,
    0.0
)

println(
    safe_region(display)
)

println(
    edge_distance(
        display,
        30.0,
        500.0
    )
)

println(
    interaction_radius(
        display,
        30.0,
        500.0
    )
    
    
    
    1. Julia — live layout server

Save as layout_server.jl.

using Sockets
using JSON3

struct DisplaySurface
    width::Float64
    height::Float64
    corner_radius::Float64
    top_occlusion::Float64
    bottom_occlusion::Float64
    left_occlusion::Float64
    right_occlusion::Float64
end

function edge_distance(d, x, y)
    minimum([
        x - d.left_occlusion,
        d.width - d.right_occlusion - x,
        y - d.top_occlusion,
        d.height - d.bottom_occlusion - y
    ])
end

function interaction_radius(d, x, y)

    edge = max(
        edge_distance(d, x, y),
        0.0
    )

    # Controls become physically easier to hit
    # as they approach the display edge.
    clamp(
        44.0 - edge * 0.10,
        28.0,
        52.0
    )
end

function solve_layout(request)

    d = DisplaySurface(
        Float64(request["width"]),
        Float64(request["height"]),
        Float64(request["cornerRadius"]),
        Float64(request["topOcclusion"]),
        Float64(request["bottomOcclusion"]),
        Float64(request["leftOcclusion"]),
        Float64(request["rightOcclusion"])
    )

    elements = request["elements"]

    output = []

    for element in elements

        role = String(element["role"])
        importance = Float64(element["importance"])

        # Normalised coordinates.
        u = Float64(element["u"])
        v = Float64(element["v"])

        x = u * d.width
        y = v * d.height

        # Physical edge distance.
        edge = edge_distance(d, x, y)

        # Dynamic interaction radius.
        radius = interaction_radius(
            d,
            x,
            y
        )

        # Edge-aware scale.
        scale = if edge < 50
            1.10
        elseif edge < 100
            1.04
        else
            1.0
        end

        # Semantic role changes layout behaviour.
        if role == "navigation"
            y = d.height - 70
        elseif role == "status"
            y = 32
        elseif role == "primary"
            y = d.height * 0.72
        end

        push!(
            output,
            Dict(
                "id" => String(element["id"]),
                "x" => x,
                "y" => y,
                "scale" => scale,
                "radius" => radius,
                "edgeDistance" => edge,
                "importance" => importance
            )
        )
    end

    return Dict(
        "width" => d.width,
        "height" => d.height,
        "elements" => output
    )
end


function handle_connection(socket)

    while isopen(socket)

        line = try
            readline(socket)
        catch
            break
        end

        isempty(strip(line)) && continue

        try

            request = JSON3.read(line)

            result = solve_layout(request)

            println(
                socket,
                JSON3.write(result)
            )

            flush(socket)

        catch error

            println(
                socket,
                JSON3.write(
                    Dict(
                        "error" =>
                            string(error)
                    )
                )
            )

            flush(socket)
        end
    end

    close(socket)
end


server = listen(
    ip"127.0.0.1",
    48731
)

println(
    "Bezel-Free Julia Engine running on 127.0.0.1:48731"
)

while true

    socket = accept(server)

    @async handle_connection(socket)

end

Run:

julia layout_server.jl
2. Swift — Julia connection

Create JuliaLayoutEngine.swift.

import Foundation
import Network

struct LayoutElement: Codable {
    let id: String
    let role: String
    let importance: Double
    let u: Double
    let v: Double
}

struct LayoutRequest: Codable {

    let width: Double
    let height: Double

    let cornerRadius: Double

    let topOcclusion: Double
    let bottomOcclusion: Double
    let leftOcclusion: Double
    let rightOcclusion: Double

    let elements: [LayoutElement]
}

struct SolvedElement: Codable {

    let id: String

    let x: Double
    let y: Double

    let scale: Double
    let radius: Double

    let edgeDistance: Double
    let importance: Double
}

struct LayoutResponse: Codable {

    let width: Double
    let height: Double

    let elements: [SolvedElement]
}

Now the actual network engine:

final class JuliaLayoutEngine: ObservableObject {

    @Published var layout: LayoutResponse?

    private var connection: NWConnection?

    private let queue =
        DispatchQueue(
            label: "aureom.julia.layout"
        )

    init() {

        connection = NWConnection(
            host: "127.0.0.1",
            port: 48731,
            using: .tcp
        )

        connection?.start(
            queue: queue
        )
    }

    func solve(
        request: LayoutRequest
    ) {

        guard let connection else {
            return
        }

        do {

            let encoder =
                JSONEncoder()

            let data =
                try encoder.encode(request)

            var packet = data
            packet.append(
                UInt8(ascii: "\n")
            )

            connection.send(
                content: packet,
                completion: .contentProcessed { [weak self] error in

                    if let error {
                        print(
                            "Julia error:",
                            error
                        )
                        return
                    }

                    self?.receive()
                }
            )

        } catch {

            print(
                "Encoding error:",
                error
            )
        }
    }

    private func receive() {

        connection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, _, error in

            guard
                let self,
                let data,
                error == nil
            else {
                return
            }

            do {

                let response =
                    try JSONDecoder()
                        .decode(
                            LayoutResponse.self,
                            from: data
                        )

                DispatchQueue.main.async {

                    self.layout =
                        response
                }

            } catch {

                print(
                    "Julia response error:",
                    error
                )
            }
        }
    }
}
3. SwiftUI now becomes Julia-driven

This is the important part.

SwiftUI no longer decides where the interface goes.

Julia does.

import SwiftUI

struct AureomDisplayView: View {

    @StateObject private var julia =
        JuliaLayoutEngine()

    var body: some View {

        GeometryReader { geometry in

            ZStack {

                Color.black
                    .ignoresSafeArea()

                if let layout = julia.layout {

                    ForEach(
                        layout.elements,
                        id: \.id
                    ) { element in

                        JuliaDrivenElement(
                            element: element
                        )
                        .position(
                            x: element.x,
                            y: element.y
                        )
                        .scaleEffect(
                            element.scale
                        )
                    }
                }

            }
            .onAppear {

                solve(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
            }

            .onChange(
                of: geometry.size
            ) { _, newSize in

                solve(
                    width: newSize.width,
                    height: newSize.height
                )
            }
        }
        .ignoresSafeArea()
    }

    private func solve(
        width: CGFloat,
        height: CGFloat
    ) {

        let elements = [

            LayoutElement(
                id: "clock",
                role: "primary",
                importance: 1.0,
                u: 0.5,
                v: 0.5
            ),

            LayoutElement(
                id: "status",
                role: "status",
                importance: 0.4,
                u: 0.5,
                v: 0.05
            ),

            LayoutElement(
                id: "navigation",
                role: "navigation",
                importance: 0.8,
                u: 0.5,
                v: 0.95
            )
        ]

        let request =
            LayoutRequest(

                width: width,
                height: height,

                cornerRadius: 45,

                topOcclusion: 0,
                bottomOcclusion: 0,
                leftOcclusion: 0,
                rightOcclusion: 0,

                elements: elements
            )

        julia.solve(
            request: request
        )
    }
}
4. The actual UI objects
struct JuliaDrivenElement: View {

    let element: SolvedElement

    var body: some View {

        switch element.id {

        case "clock":

            Text(
                Date.now,
                style: .time
            )
            .font(
                .system(
                    size: 72,
                    weight: .thin,
                    design: .rounded
                )
            )
            .monospacedDigit()

        case "status":

            Text("AUREOM • DISPLAY")
                .font(
                    .system(
                        size: 11,
                        weight: .medium,
                        design: .monospaced
                    )
                )
                .tracking(2)

        case "navigation":

            HStack(spacing: 45) {

                Image(
                    systemName: "chevron.left"
                )

                Image(
                    systemName: "circle"
                )

                Image(
                    systemName: "chevron.right"
                )
            }
            .font(
                .system(
                    size: 18,
                    weight: .medium
                )
            )

        default:

            EmptyView()
        }
    }
}

Now the hierarchy is genuinely:

                DISPLAY
                   │
                   ▼
             Swift Geometry
                   │
                   ▼
             LayoutRequest
                   │
                   ▼
          ┌─────────────────┐
          │      JULIA      │
          │                 │
          │ geometry        │
          │ edge detection  │
          │ ergonomics      │
          │ optimisation    │
          │ semantic layout │
          └────────┬────────┘
                   │
             LayoutResponse
                   │
                   ▼
                SwiftUI
                   │
                   ▼
             Metal / GPU
                   │
                   ▼
           PHYSICAL DISPLAY
5. Make it actually continuous

The next change is to stop solving only on rotation/resize.

For example, feed the finger position into Julia.

Swift:

let touch = LayoutTouch(
    x: location.x,
    y: location.y
)

Julia:

function touch_attraction(
    element_x,
    element_y,
    touch_x,
    touch_y
)

    distance = hypot(
        element_x - touch_x,
        element_y - touch_y
    )

    return exp(
        -distance / 180.0
    )
end







1. Edge-aware touch system

Swift can determine where the finger is and classify the interaction:

enum SurfaceRegion {
    case center
    case topEdge
    case bottomEdge
    case leftEdge
    case rightEdge
    case corner
}

Then:

func surfaceRegion(
    point: CGPoint,
    size: CGSize
) -> SurfaceRegion {

    let edge: CGFloat = 40

    if point.x < edge {
        return .leftEdge
    }

    if point.x > size.width - edge {
        return .rightEdge
    }

    if point.y < edge {
        return .topEdge
    }

    if point.y > size.height - edge {
        return .bottomEdge
    }

    return .center
}

That allows the UI to behave differently depending on where on the physical surface you touch.

2. Edge gestures

Instead of conventional buttons:

← swipe
→ swipe
↑ swipe
↓ swipe

Swift can turn the physical edges into navigation controls.

DragGesture(minimumDistance: 15)
    .onEnded { gesture in

        let dx = gesture.translation.width
        let dy = gesture.translation.height

        if abs(dx) > abs(dy) {

            if dx > 0 {
                navigateBack()
            } else {
                navigateForward()
            }

        } else {

            if dy > 0 {
                openControlCentre()
            } else {
                openNotifications()
            }
        }
    }
3. Dynamic hitboxes

A bezel-free interface shouldn't necessarily have tiny visual buttons.

Swift can have:

struct HitRegion {

    var visualSize: CGFloat
    var interactionSize: CGFloat
}

So something visually 20 px wide could have a 52 px invisible touch field.

Julia could continuously optimise that interaction radius.

4. Thumb-reach modelling

Swift can track the approximate interaction area and send it to Julia.

struct UserReach {

    var x: CGFloat
    var y: CGFloat

    var confidence: Double
}

Julia then determines:

Where should the controls move?
How large should they become?
Which controls should disappear?
Which controls should move toward the thumb?

This could produce an interface that physically reorganises itself around the user's hand.

5. Proximity-aware UI

If the device has appropriate proximity/depth sensing, Swift could create:

enum InteractionDistance {
    case far
    case approaching
    case near
    case touching
}

Then:

hand far away
    ↓
minimal UI

hand approaching
    ↓
controls appear

hand near
    ↓
controls enlarge

touch
    ↓
full interaction

That would be extremely interesting for a bezel-free device.

6. Haptic geometry

Swift can connect display geometry to haptics.

func feedback(
    intensity: CGFloat
) {

    let generator =
        UIImpactFeedbackGenerator(
            style: .medium
        )

    generator.prepare()
    generator.impactOccurred(
        intensity: intensity
    )
}

You could make the physical edge feel like a boundary even though there isn't a visible bezel.

7. Continuous edge indicators

Instead of icons:

[ WiFi ] [ Battery ] [ Time ]

you could create continuous edge information.

For example:

struct EdgeSignal {

    let value: Double
    let thickness: CGFloat
}

Battery:

100% ━━━━━━━━━━━━━━━━━
 50% ━━━━━━━━━
 10% ━━

The display edge itself becomes a status indicator.

8. Physics-based UI

Swift can give elements mass, velocity and spring behaviour.

struct UIPhysics {

    var position: CGPoint
    var velocity: CGVector

    var mass: CGFloat
    var damping: CGFloat
    var spring: CGFloat
}

Then controls don't simply jump:

position A
     ↓
physical movement
     ↓
position B

They behave more like objects on a surface.

9. Julia-controlled animation

Julia could calculate:

position
velocity
acceleration
scale
opacity
rotation

Swift then interpolates the result:

withAnimation(
    .interactiveSpring(
        response: 0.28,
        dampingFraction: 0.82
    )
) {
    position = solution.position
}

This gives you mathematically generated UI motion.

10. Orientation-aware display

Swift can monitor device orientation and send it to Julia:

enum SurfaceOrientation {
    case portrait
    case landscape
    case invertedPortrait
    case invertedLandscape
}

Julia then recalculates the entire interface.

So rotating the device doesn't merely rotate the UI.

The UI gets re-solved.

11. Light-aware UI

Using ambient-light information, you could create:

struct DisplayEnvironment {

    var ambientLux: Double
    var motion: Double
    var proximity: Double
}

Julia could then optimise:

brightness
contrast
text size
edge intensity
animation speed
visual density

For example:

dark environment
→ minimal bright UI

bright environment
→ stronger contrast

moving user
→ fewer small controls

stationary user
→ richer interface
12. Eye/attention-aware UI

If eye tracking is available, Swift can provide Julia with:

struct GazePoint {

    var x: Double
    var y: Double
    var confidence: Double
}

Julia could calculate an attention field.

The interface could subtly move important information toward where you're actually looking.

13. Display topology

This is the really futuristic one.

Instead of assuming:

CGRect

you could define:

struct DisplayTopology {

    let surface: SurfaceModel

    let curvature: CurvatureModel

    let occlusions: [Occlusion]

    let interactionZones: [InteractionZone]
}

The software no longer thinks:

"I have an iPhone rectangle."

It thinks:

"I have a physical computational surface."

That could accommodate:

curved screens
folding screens
wraparound displays
automotive displays
unusual aspect ratios
transparent displays
multi-surface devices
And I'd add a Swift SurfaceView

Something like:

SurfaceView {

    SurfaceText(
        "12:48",
        role: .primary
    )

    SurfaceControl(
        icon: "wifi",
        role: .status
    )

    SurfaceNavigation(
        direction: .horizontal
    )
}

The programmer describes what something is, rather than where it goes.

Then:

Swift
  ↓
semantic UI
  ↓
Julia
  ↓
geometry optimisation
  ↓
Swift
  ↓
Metal
  ↓
physical display
The end result

You could essentially create your own framework:

AureomSurfaceKit

with modules such as:

AureomSurfaceKit
│
├── SurfaceGeometry
├── SurfaceTouch
├── SurfaceGesture
├── SurfacePhysics
├── SurfaceHaptics
├── SurfaceAnimation
├── SurfaceEnvironment
├── SurfaceOrientation
├── SurfaceTopology
├── SurfaceAccessibility
├── SurfaceRendering
└── JuliaLayoutBridge




