1. A common device model
import Foundation

enum AppleDeviceType: String, Codable {
    case iPhone
    case iPad
    case mac
    case watch
    case appleTV
    case visionPro
}

struct AppleDevice: Identifiable, Codable, Hashable {
    let id: UUID
    let type: AppleDeviceType
    let name: String

    var capabilities: Set<DeviceCapability>

    var isReachable: Bool
    var lastSeen: Date
}

enum DeviceCapability: String, Codable, Hashable {
    case touch
    case keyboard
    case trackpad
    case pencil
    case camera
    case microphone
    case largeDisplay
    case smallDisplay
    case cellular
    case haptics
    case applePay
    case externalDisplay
}

Now the application can reason about capabilities rather than device names.

For example:

if device.capabilities.contains(.largeDisplay) {
    // Send desktop UI
}

if device.capabilities.contains(.pencil) {
    // Enable Apple Pencil workflow
}

That is much more powerful than simply saying:

if device.type == .iPad
2. A universal event system

I'd make every device communicate through the same event abstraction.

enum EcosystemEvent: Codable {

    case documentChanged(
        documentID: UUID
    )

    case playbackChanged(
        mediaID: String,
        position: TimeInterval
    )

    case activityChanged(
        activityID: String
    )

    case clipboardChanged(
        identifier: UUID
    )

    case deviceBecameAvailable(
        deviceID: UUID
    )

    case deviceDisconnected(
        deviceID: UUID
    )

    case requestHandoff(
        activityID: String
    )
}

Then:

actor EcosystemEventBus {

    private var handlers:
        [UUID: (EcosystemEvent) async -> Void] = [:]

    func subscribe(
        _ handler: @escaping (EcosystemEvent) async -> Void
    ) -> UUID {

        let id = UUID()

        handlers[id] = handler

        return id
    }

    func publish(
        _ event: EcosystemEvent
    ) async {

        for handler in handlers.values {
            await handler(event)
        }
    }

    func unsubscribe(
        _ id: UUID
    ) {
        handlers.removeValue(forKey: id)
    }
}

Now the rest of the application doesn't need to know whether an event came from an iPhone, Mac, Watch or iPad.

3. Automatic device capability matching

This is where it starts becoming interesting.

Suppose you're editing a document on an iPhone.

The interoperability layer sees:

iPhone
   │
   └── editing document
          │
          ▼
       Interop Core
          │
          ├── Mac available?
          │       YES
          │
          ├── large display?
          │       YES
          │
          ├── keyboard?
          │       YES
          │
          └── same application?
                  YES

It can expose a continuation opportunity:

struct ContinuationOpportunity {

    let source: AppleDevice
    let destination: AppleDevice

    let activityID: String

    var score: Double {
        var value = 0.0

        if destination.capabilities.contains(.largeDisplay) {
            value += 0.4
        }

        if destination.capabilities.contains(.keyboard) {
            value += 0.3
        }

        if destination.isReachable {
            value += 0.3
        }

        return value
    }
}

The score isn't a user-facing ranking; it's simply an internal capability-selection mechanism for deciding which device can execute a particular continuation.

4. Handoff layer

Apple's NSUserActivity is specifically designed to represent the state of an activity and make it available to another device.

I'd wrap it:

import Foundation

final class EcosystemHandoff {

    private var currentActivity:
        NSUserActivity?

    func begin(
        activityType: String,
        title: String,
        contentID: String,
        state: [String: Any]
    ) {

        let activity =
            NSUserActivity(
                activityType: activityType
            )

        activity.title = title

        activity.targetContentIdentifier =
            contentID

        activity.userInfo = state

        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true

        activity.becomeCurrent()

        currentActivity = activity
    }

    func update(
        state: [String: Any]
    ) {

        currentActivity?.addUserInfoEntries(
            from: state
        )

        currentActivity?.needsSave = true
    }

    func end() {

        currentActivity?.resignCurrent()
        currentActivity = nil
    }
}

For a document editor:

handoff.begin(
    activityType: "com.example.editor.document",
    title: "Editing Aureum",
    contentID: document.id.uuidString,
    state: [
        "documentID": document.id.uuidString,
        "cursor": 1842,
        "page": 17
    ]
)

The Mac could then reconstruct the editing environment.

Apple specifically requires the participating apps to share the same developer Team ID when using Handoff across platforms.

5. Nearby device communication

For devices that are physically close, I'd add a peer layer using MultipeerConnectivity.

Apple's framework supports nearby discovery plus message, stream and resource/file communication, using Wi-Fi/Bluetooth-related transports depending on platform.

Conceptually:

import MultipeerConnectivity

final class NearbyDeviceNetwork: NSObject {

    private let serviceType =
        "appleinterop"

    private let peerID =
        MCPeerID(
            displayName:
                Host.current().localizedName
                ?? "AppleDevice"
        )

    private lazy var session =
        MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )

    private lazy var advertiser =
        MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )

    private lazy var browser =
        MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: serviceType
        )

    override init() {
        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {

        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()

        session.disconnect()
    }

    func send(
        _ data: Data
    ) throws {

        guard !session.connectedPeers.isEmpty else {
            return
        }

        try session.send(
            data,
            toPeers: session.connectedPeers,
            with: .reliable
        )
    }
}

extension NearbyDeviceNetwork:
    MCSessionDelegate {

    func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        print(
            "Peer:",
            peerID.displayName,
            state
        )
    }

    func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        print(
            "Received:",
            data.count,
            "bytes"
        )
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}

extension NearbyDeviceNetwork:
    MCNearbyServiceAdvertiserDelegate {

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler:
            @escaping (Bool, MCSession?) -> Void
    ) {

        invitationHandler(true, session)
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {}
}

extension NearbyDeviceNetwork:
    MCNearbyServiceBrowserDelegate {

    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String : String]?
    ) {

        browser.invitePeer(
            peerID,
            to: session,
            withContext: nil,
            timeout: 10
        )
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {}

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {}
}

For a production application, you'd put explicit authentication/authorization around invitations rather than automatically accepting every peer.

6. Watch gets its own transport

For Apple Watch, I'd use WatchConnectivity rather than trying to force everything through the generic peer layer.

Apple provides background transfers, file transfers, user-info transfers and live messaging between an iOS app and its paired watchOS app.

So the architecture becomes:

                   Interop Core
                       │
        ┌──────────────┼───────────────┐
        │              │               │
        ▼              ▼               ▼
     CloudKit       Handoff       Nearby Network
        │              │               │
        │              │               │
     ┌──┴──┐       ┌───┴───┐       ┌───┴────┐
     │     │       │       │       │        │
   iPhone iPad    Mac    iPhone    iPad     Mac
     │
     ▼
   Watch
     │
 WatchConnectivity
7. One unified AppleInterop API

The application developer shouldn't have to think about all those transports.

I'd expose something like:

@MainActor
final class AppleInterop {

    let devices = DeviceRegistry()

    let events = EcosystemEventBus()

    let handoff = EcosystemHandoff()

    let sync = AppleDeviceSync()

    let nearby = NearbyDeviceNetwork()

    func start() {

        nearby.start()
    }

    func stop() {

        nearby.stop()
    }

    func publish(
        _ event: EcosystemEvent
    ) async {

        await events.publish(event)
    }
}

Then your application becomes beautifully simple:

let ecosystem = AppleInterop()

ecosystem.start()

await ecosystem.publish(
    .documentChanged(
        documentID: document.id
    )
)
