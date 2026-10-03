```swift
import SwiftUI
import Combine

// ============================================================
// MARK: - Screensaver Modes
// ============================================================

public enum ScreensaverMode: String, CaseIterable {
    case ambient
    case gradient
    case particles
    case geometry
    case clock
    case stars
    case aurora
}


// ============================================================
// MARK: - Screensaver Configuration
// ============================================================

public struct ScreensaverConfiguration {

    public var mode: ScreensaverMode = .ambient

    /// Seconds before screensaver becomes active.
    public var idleTimeout: TimeInterval = 60

    /// Animation speed.
    public var animationSpeed: Double = 0.15

    /// Number of particles.
    public var particleCount: Int = 80

    /// Prevent static elements remaining in one location.
    public var burnInProtection: Bool = true

    /// Allow screen to dim during screensaver.
    public var allowDimming: Bool = true

    /// Show clock.
    public var showClock: Bool = true

    public init() {}
}


// ============================================================
// MARK: - Particle
// ============================================================

public struct ScreensaverParticle:
    Identifiable
{

    public let id = UUID()

    public var x: CGFloat
    public var y: CGFloat

    public var velocityX: CGFloat
    public var velocityY: CGFloat

    public var radius: CGFloat
    public var opacity: Double

    public var phase: Double
}


// ============================================================
// MARK: - Particle Engine
// ============================================================

@MainActor
public final class ScreensaverParticleEngine:
    ObservableObject
{

    @Published
    public private(set) var particles:
        [ScreensaverParticle] = []

    private var timer:
        Timer?

    public init(
        count: Int
    ) {

        particles =
            (0..<count).map { _ in

                ScreensaverParticle(

                    x: .random(
                        in: 0...1
                    ),

                    y: .random(
                        in: 0...1
                    ),

                    velocityX: .random(
                        in: -0.0008...0.0008
                    ),

                    velocityY: .random(
                        in: -0.0008...0.0008
                    ),

                    radius: .random(
                        in: 1...5
                    ),

                    opacity: .random(
                        in: 0.1...0.7
                    ),

                    phase: .random(
                        in: 0...Double.pi * 2
                    )
                )
            )
    }

    public func start(
        speed: Double = 1
    ) {

        stop()

        timer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30.0,
            repeats: true
        ) { [weak self] _ in

            guard let self else {
                return
            }

            Task { @MainActor in
                self.update(
                    speed: speed
                )
            }
        }
    }

    public func stop() {

        timer?.invalidate()
        timer = nil
    }

    private func update(
        speed: Double
    ) {

        for index in particles.indices {

            particles[index].x +=
                particles[index].velocityX *
                speed

            particles[index].y +=
                particles[index].velocityY *
                speed

            if particles[index].x < 0 {
                particles[index].x = 1
            }

            if particles[index].x > 1 {
                particles[index].x = 0
            }

            if particles[index].y < 0 {
                particles[index].y = 1
            }

            if particles[index].y > 1 {
                particles[index].y = 0
            }
        }
    }
}


// ============================================================
// MARK: - Animated Gradient
// ============================================================

public struct AnimatedGradientView:
    View
{

    @State private var phase: CGFloat = 0

    let speed: Double

    public init(
        speed: Double = 0.1
    ) {
        self.speed = speed
    }

    public var body: some View {

        GeometryReader { geometry in

            ZStack {

                LinearGradient(
                    colors: [
                        Color.black,
                        Color.blue.opacity(0.55),
                        Color.purple.opacity(0.35),
                        Color.black
                    ],
                    startPoint: UnitPoint(
                        x: 0 + phase,
                        y: 0
                    ),
                    endPoint: UnitPoint(
                        x: 1 + phase,
                        y: 1
                    )
                )

                RadialGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear
                    ],
                    center: UnitPoint(
                        x: 0.5 +
                        sin(phase) * 0.25,
                        y: 0.5 +
                        cos(phase) * 0.25
                    ),
                    startRadius: 20,
                    endRadius:
                        max(
                            geometry.size.width,
                            geometry.size.height
                        )
                )
            }
            .ignoresSafeArea()
            .onAppear {

                withAnimation(
                    .linear(
                        duration:
                            30 / speed
                    )
                    .repeatForever(
                        autoreverses: false
                    )
                ) {

                    phase = 1
                }
            }
        }
    }
}


// ============================================================
// MARK: - Particle Screensaver
// ============================================================

public struct ParticleScreensaver:
    View
{

    @StateObject private var engine:
        ScreensaverParticleEngine

    let speed: Double

    public init(
        count: Int = 80,
        speed: Double = 1
    ) {

        _engine =
            StateObject(
                wrappedValue:
                    ScreensaverParticleEngine(
                        count: count
                    )
            )

        self.speed = speed
    }

    public var body: some View {

        GeometryReader { geometry in

            ZStack {

                Color.black

                ForEach(
                    engine.particles
                ) { particle in

                    Circle()
                        .fill(
                            Color.white.opacity(
                                particle.opacity
                            )
                        )
                        .frame(
                            width: particle.radius,
                            height: particle.radius
                        )
                        .position(

                            x:
                                particle.x *
                                geometry.size.width,

                            y:
                                particle.y *
                                geometry.size.height
                        )
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {

            engine.start(
                speed: speed
            )
        }
        .onDisappear {

            engine.stop()
        }
    }
}


// ============================================================
// MARK: - Aurora
// ============================================================

public struct AuroraScreensaver:
    View
{

    @State private var phase: Double = 0

    public var body: some View {

        GeometryReader { geometry in

            ZStack {

                Color.black

                ForEach(
                    0..<7,
                    id: \.self
                ) { index in

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.green.opacity(0.0),
                                    Color.green.opacity(0.15),
                                    Color.blue.opacity(0.20),
                                    Color.purple.opacity(0.05),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(
                            width:
                                geometry.size.width *
                                0.45,

                            height:
                                geometry.size.height *
                                1.2
                        )
                        .rotationEffect(
                            .degrees(
                                -25 +
                                Double(index) * 8
                            )
                        )
                        .offset(
                            x:
                                sin(
                                    phase +
                                    Double(index)
                                ) *
                                120,

                            y:
                                cos(
                                    phase * 0.7 +
                                    Double(index)
                                ) *
                                40
                        )
                        .blur(
                            radius: 35
                        )
                }
            }
            .ignoresSafeArea()
            .onAppear {

                withAnimation(
                    .linear(
                        duration: 40
                    )
                    .repeatForever(
                        autoreverses: true
                    )
                ) {

                    phase = Double.pi * 2
                }
            }
        }
    }
}


// ============================================================
// MARK: - Geometric Screensaver
// ============================================================

public struct GeometryScreensaver:
    View
{

    @State private var rotation: Double = 0

    public var body: some View {

        ZStack {

            Color.black
                .ignoresSafeArea()

            GeometryReader { geometry in

                ZStack {

                    ForEach(
                        0..<12,
                        id: \.self
                    ) { index in

                        RoundedRectangle(
                            cornerRadius: 30
                        )
                        .stroke(
                            Color.white.opacity(
                                0.12
                            ),
                            lineWidth: 1
                        )
                        .frame(
                            width:
                                geometry.size.width *
                                (
                                    0.15 +
                                    Double(index) *
                                    0.06
                                )
                        )
                        .rotationEffect(
                            .degrees(
                                rotation +
                                Double(index) * 15
                            )
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
            }
        }
        .onAppear {

            withAnimation(
                .linear(
                    duration: 60
                )
                .repeatForever(
                    autoreverses: false
                )
            ) {

                rotation = 360
            }
        }
    }
}


// ============================================================
// MARK: - Clock
// ============================================================

public struct ScreensaverClock:
    View
{

    @State private var date = Date()

    private let timer =
        Timer.publish(
            every: 1,
            on: .main,
            in: .common
        )
        .autoconnect()

    public var body: some View {

        Text(date, style: .time)
            .font(
                .system(
                    size: 72,
                    weight: .ultraLight,
                    design: .rounded
                )
            )
            .foregroundStyle(
                .white.opacity(0.85)
            )
            .onReceive(timer) { value in
                date = value
            }
    }
}


// ============================================================
// MARK: - Burn-In Protection
// ============================================================

@MainActor
public final class BurnInProtection:
    ObservableObject
{

    @Published
    public private(set) var offset:
        CGSize = .zero

    private var timer:
        Timer?

    public init() {}

    public func start() {

        stop()

        timer = Timer.scheduledTimer(
            withTimeInterval: 30,
            repeats: true
        ) { [weak self] _ in

            guard let self else {
                return
            }

            Task { @MainActor in

                self.offset = CGSize(

                    width: .random(
                        in: -20...20
                    ),

                    height: .random(
                        in: -20...20
                    )
                )
            }
        }
    }

    public func stop() {

        timer?.invalidate()
        timer = nil
    }
}


// ============================================================
// MARK: - Master Screensaver
// ============================================================

public struct AppleScreensaver:
    View
{

    public let configuration:
        ScreensaverConfiguration

    @StateObject private var burnProtection =
        BurnInProtection()

    public init(
        configuration:
            ScreensaverConfiguration =
            ScreensaverConfiguration()
    ) {

        self.configuration =
            configuration
    }

    public var body: some View {

        ZStack {

            content

            if configuration.showClock {

                VStack {

                    Spacer()

                    ScreensaverClock()
                        .padding(.bottom, 50)
                }
            }
        }
        .offset(
            burnProtection.offset
        )
        .onAppear {

            if configuration.burnInProtection {
                burnProtection.start()
            }
        }
        .onDisappear {

            burnProtection.stop()
        }
    }

    @ViewBuilder
    private var content: some View {

        switch configuration.mode {

        case .ambient:

            AnimatedGradientView(
                speed:
                    configuration.animationSpeed
            )

        case .gradient:

            AnimatedGradientView(
                speed:
                    configuration.animationSpeed
            )

        case .particles:

            ParticleScreensaver(
                count:
                    configuration.particleCount,

                speed:
                    configuration.animationSpeed
            )

        case .geometry:

            GeometryScreensaver()

        case .stars:

            ParticleScreensaver(
                count:
                    configuration.particleCount / 2,

                speed:
                    configuration.animationSpeed * 0.4
            )

        case .aurora:

            AuroraScreensaver()

        case .clock:

            ZStack {

                Color.black
                    .ignoresSafeArea()

                ScreensaverClock()
            }
        }
    }
}


// ============================================================
// MARK: - Idle Detection
// ============================================================

@MainActor
public final class ScreensaverController:
    ObservableObject
{

    @Published
    public private(set) var isActive = false

    @Published
    public private(set) var lastInteraction =
        Date()

    private let timeout:
        TimeInterval

    private var timer:
        Timer?

    public init(
        timeout: TimeInterval = 60
    ) {

        self.timeout = timeout

        startMonitoring()
    }

    public func interaction() {

        lastInteraction = Date()

        if isActive {
            deactivate()
        }
    }

    private func startMonitoring() {

        timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in

            guard let self else {
                return
            }

            Task { @MainActor in

                if Date().timeIntervalSince(
                    self.lastInteraction
                ) >= self.timeout {

                    self.activate()
                }
            }
        }
    }

    public func activate() {

        isActive = true
    }

    public func deactivate() {

        isActive = false
        lastInteraction = Date()
    }

    deinit {

        timer?.invalidate()
    }
}


// ============================================================
// MARK: - Example Application
// ============================================================

public struct ScreensaverDemoView:
    View
{

    @StateObject private var controller =
        ScreensaverController(
            timeout: 30
        )

    public init() {}

    public var body: some View {

        ZStack {

            if controller.isActive {

                AppleScreensaver(
                    configuration:
                        ScreensaverConfiguration()
                )
                .transition(
                    .opacity
                )

            } else {

                VStack(spacing: 20) {

                    Image(
                        systemName:
                            "sparkles"
                    )
                    .font(
                        .system(size: 60)
                    )

                    Text(
                        "Screensaver Ready"
                    )
                    .font(
                        .largeTitle
                    )

                    Text(
                        "Interact with the device to continue."
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
                .onTapGesture {

                    controller.interaction()
                }
            }
        }
        .onTapGesture {

            controller.interaction()
        }
    }
}


// ============================================================
// MARK: - App Entry Point
// ============================================================

@main
struct ScreensaverDemoApp:
    App
{

    var body: some Scene {

        WindowGroup {

            ScreensaverDemoView()
        }
    }
}
```


