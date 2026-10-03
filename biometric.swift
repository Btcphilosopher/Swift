```swift
import SwiftUI
import LocalAuthentication

// ============================================================
// MARK: - Authentication State
// ============================================================

enum FingerprintState {
    case idle
    case scanning
    case success
    case failure
}


// ============================================================
// MARK: - Fingerprint Animation View
// ============================================================

struct FingerprintAnimation: View {

    @Binding var state: FingerprintState

    @State private var scanProgress: CGFloat = 0
    @State private var pulse = false
    @State private var glow = false
    @State private var rotation: Double = 0

    var body: some View {

        ZStack {

            // ------------------------------------------------
            // Outer glow
            // ------------------------------------------------

            Circle()
                .stroke(
                    Color.primary.opacity(
                        glow ? 0.18 : 0.05
                    ),
                    lineWidth: 2
                )
                .frame(
                    width: 190,
                    height: 190
                )
                .scaleEffect(
                    pulse ? 1.06 : 1.0
                )
                .animation(
                    .easeInOut(
                        duration: 1.3
                    )
                    .repeatForever(
                        autoreverses: true
                    ),
                    value: pulse
                )

            // ------------------------------------------------
            // Fingerprint
            // ------------------------------------------------

            FingerprintShape()

                .trim(
                    from: 0,
                    to: state == .scanning
                        ? scanProgress
                        : state == .success
                            ? 1
                            : 0.85
                )

                .stroke(
                    fingerprintColor,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                .frame(
                    width: 150,
                    height: 170
                )

                .shadow(
                    color: fingerprintColor.opacity(
                        glow ? 0.7 : 0.15
                    ),
                    radius: 12
                )

                .scaleEffect(
                    state == .success ? 1.04 : 1
                )

                .animation(
                    .easeInOut(
                        duration: 0.45
                    ),
                    value: state
                )

            // ------------------------------------------------
            // Scanning beam
            // ------------------------------------------------

            if state == .scanning {

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                fingerprintColor.opacity(0.8),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: 150,
                        height: 2
                    )
                    .offset(
                        y: scanLinePosition
                    )
                    .blur(
                        radius: 1
                    )
            }

            // ------------------------------------------------
            // Success ring
            // ------------------------------------------------

            if state == .success {

                Circle()
                    .stroke(
                        Color.green,
                        lineWidth: 4
                    )
                    .frame(
                        width: 178,
                        height: 178
                    )
                    .scaleEffect(
                        pulse ? 1.08 : 0.95
                    )
                    .opacity(
                        pulse ? 0.35 : 0.8
                    )
            }

            // ------------------------------------------------
            // Failure ring
            // ------------------------------------------------

            if state == .failure {

                Circle()
                    .stroke(
                        Color.red,
                        lineWidth: 3
                    )
                    .frame(
                        width: 178,
                        height: 178
                    )
                    .transition(
                        .scale.combined(
                            with: .opacity
                        )
                    )
            }
        }

        .onAppear {

            pulse = true
            glow = true

            if state == .scanning {
                startScan()
            }
        }

        .onChange(of: state) { _, newState in

            switch newState {

            case .scanning:
                startScan()

            case .success:
                successAnimation()

            case .failure:
                failureAnimation()

            case .idle:
                resetAnimation()
            }
        }
    }


    // ========================================================
    // MARK: - Appearance
    // ========================================================

    private var fingerprintColor: Color {

        switch state {

        case .idle:
            return .primary

        case .scanning:
            return .blue

        case .success:
            return .green

        case .failure:
            return .red
        }
    }


    // ========================================================
    // MARK: - Scan Position
    // ========================================================

    private var scanLinePosition: CGFloat {

        let range: CGFloat = 130

        return -range / 2 +
            scanProgress * range
    }


    // ========================================================
    // MARK: - Scan
    // ========================================================

    private func startScan() {

        scanProgress = 0

        withAnimation(
            .linear(
                duration: 1.8
            )
            .repeatForever(
                autoreverses: false
            )
        ) {
            scanProgress = 1
        }
    }


    // ========================================================
    // MARK: - Success
    // ========================================================

    private func successAnimation() {

        scanProgress = 1

        withAnimation(
            .spring(
                response: 0.4,
                dampingFraction: 0.55
            )
        ) {
            pulse = true
        }
    }


    // ========================================================
    // MARK: - Failure
    // ========================================================

    private func failureAnimation() {

        withAnimation(
            .easeInOut(
                duration: 0.08
            )
            .repeatCount(
                4,
                autoreverses: true
            )
        ) {
            rotation = 5
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.5
        ) {

            withAnimation {
                rotation = 0
            }
        }
    }


    // ========================================================
    // MARK: - Reset
    // ========================================================

    private func resetAnimation() {

        scanProgress = 0
        rotation = 0
    }
}


// ============================================================
// MARK: - Fingerprint Shape
// ============================================================

struct FingerprintShape: Shape {

    func path(
        in rect: CGRect
    ) -> Path {

        var path = Path()

        let cx = rect.midX
        let cy = rect.midY

        let width = rect.width
        let height = rect.height

        // Outer fingerprint arcs

        for i in 0..<8 {

            let inset =
                CGFloat(i) * 7

            let ellipseRect =
                CGRect(
                    x: rect.minX + inset,
                    y: rect.minY + inset,
                    width: width - inset * 2,
                    height: height - inset * 2
                )

            path.addArc(
                center: CGPoint(
                    x: cx,
                    y: cy
                ),
                radius: min(
                    ellipseRect.width,
                    ellipseRect.height
                ) / 2,
                startAngle: .degrees(200),
                endAngle: .degrees(340),
                clockwise: false
            )
        }

        // Central fingerprint spiral

        let center =
            CGPoint(
                x: cx,
                y: cy + 10
            )

        let radii: [CGFloat] = [
            42,
            34,
            26,
            18,
            10
        ]

        for radius in radii {

            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(205),
                endAngle: .degrees(520),
                clockwise: false
            )
        }

        return path
    }
}


// ============================================================
// MARK: - Biometric Controller
// ============================================================

@MainActor
final class TouchIDController: ObservableObject {

    @Published var state: FingerprintState = .idle
    @Published var message = "Touch ID"

    func authenticate() {

        state = .scanning
        message = "Place your finger on Touch ID"

        let context =
            LAContext()

        var error: NSError?

        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        ) else {

            state = .failure
            message = "Touch ID unavailable"
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason:
                "Authenticate to continue"
        ) { [weak self] success, error in

            Task { @MainActor in

                guard let self else {
                    return
                }

                if success {

                    self.state = .success
                    self.message = "Authenticated"

                } else {

                    self.state = .failure

                    self.message =
                        error?.localizedDescription
                        ?? "Authentication failed"
                }
            }
        }
    }

    func reset() {

        state = .idle
        message = "Touch ID"
    }
}


// ============================================================
// MARK: - Full Authentication Screen
// ============================================================

struct TouchIDAuthenticationView: View {

    @StateObject
    private var controller =
        TouchIDController()

    var body: some View {

        ZStack {

            Color(
                UIColor.systemBackground
            )
            .ignoresSafeArea()

            VStack(
                spacing: 32
            ) {

                Spacer()

                FingerprintAnimation(
                    state:
                        $controller.state
                )

                VStack(
                    spacing: 8
                ) {

                    Text(
                        controller.message
                    )
                    .font(
                        .title3.weight(
                            .medium
                        )
                    )

                    Text(
                        subtitle
                    )
                    .font(
                        .subheadline
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer()

                if controller.state == .failure {

                    Button(
                        "Try Again"
                    ) {
                        controller.authenticate()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )

                } else if controller.state == .idle {

                    Button(
                        "Authenticate"
                    ) {
                        controller.authenticate()
                    }
                    .buttonStyle(
                        .borderedProminent
                    )
                }

                Spacer()
                    .frame(
                        height: 40
                    )
            }
            .padding(24)
        }
    }


    private var subtitle: String {

        switch controller.state {

        case .idle:
            return "Use Touch ID to continue"

        case .scanning:
            return "Verifying your fingerprint"

        case .success:
            return "Identity verified"

        case .failure:
            return "Authentication was unsuccessful"
        }
    }
}


// ============================================================
// MARK: - Preview
// ============================================================

#Preview {

    TouchIDAuthenticationView()
}
```

### The important Apple distinction

This gives you the **animation and authentication flow**, but the actual biometric operation remains inside `LocalAuthentication`:

```text
Your Swift UI
     ↓
TouchIDController
     ↓
LocalAuthentication
     ↓
Secure Enclave / Touch ID
     ↓
success / failure
```

Your application **never receives the fingerprint itself**. That's exactly what you want architecturally.

For an Apple-native version, I'd take this further with **three animation layers**:

```text
             FINGERPRINT
                  │
       ┌──────────┼──────────┐
       ↓          ↓          ↓
   Scan beam    Pulse     Fingerprint
                         line drawing
       │          │          │
       └──────────┼──────────┘
                  ↓
           Authentication
                  ↓
       ┌──────────┴──────────┐
       ↓                     ↓
    SUCCESS                 FAIL
       │                     │
   green expansion       red vibration
```

And for Face ID devices, the same animation system could become a unified:

**`AppleBiometricAnimation`**

that automatically switches between a fingerprint glyph for Touch ID and a Face ID-style facial scanning animation, while `LocalAuthentication` handles the actual authentication.

