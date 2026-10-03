enum CallTransport {
    case wifi
    case cellular
    case ethernet
}

enum CallNetworkPolicy {
    case internetFirst
    case cellularFirst
    case wifiOnly
    case automatic
}

struct CallNetworkState {
    var wifiAvailable: Bool
    var cellularAvailable: Bool

    var wifiLatency: Double
    var wifiJitter: Double
    var wifiPacketLoss: Double

    var cellularLatency: Double
    var cellularJitter: Double
    var cellularPacketLoss: Double

    var preferredTransport: CallTransport
}

final class SystemCallTransportManager {

    var policy: CallNetworkPolicy = .internetFirst

    func selectTransport(
        state: CallNetworkState
    ) -> CallTransport {

        switch policy {

        case .wifiOnly:
            return .wifi

        case .internetFirst:

            if state.wifiAvailable &&
               state.wifiPacketLoss < 2.0 &&
               state.wifiJitter < 30 {

                return .wifi
            }

            return .cellular

        case .cellularFirst:

            if state.cellularAvailable {
                return .cellular
            }

            return .wifi

        case .automatic:

            if state.wifiAvailable &&
               state.wifiPacketLoss <
               state.cellularPacketLoss {

                return .wifi
            }

            return .cellular
        }
    }
}
