import Foundation
import Testing
@testable import RTC

@Test func applicationDataAndPacketAudioUseDifferentWirePayloads() throws {
    let message = ApplicationDataMessage(namespace: "rideintercom.presence", payload: Data([1, 2, 3]), delivery: .reliable)
    let appPayload = try MultipeerPayloadBuilder.makeApplicationDataPayload(message)
    let appWire = try MultipeerPayloadBuilder.decode(appPayload.data, credential: nil)

    let request = makeRequest()
    let sequencer = PacketAudioSequencer(sessionID: request.sessionID, senderID: request.localPeer.id)
    let frame = AudioFrame(sequenceNumber: 7, samples: [0.0, 0.5, -0.5])

    let audioPayload = try MultipeerPayloadBuilder.makePacketAudioPayload(sequencer.makeEnvelope(from: frame), credential: nil)
    let audioWire = try MultipeerPayloadBuilder.decode(audioPayload.data, credential: nil)

    #expect(appPayload.mode == .reliable)
    #expect(audioPayload.mode == .unreliable)

    guard case .applicationData(let decodedMessage) = appWire else {
        Issue.record("Expected application data payload")
        return
    }

    guard case .packetAudio(let decodedEnvelope) = audioWire else {
        Issue.record("Expected packet audio payload")
        return
    }

    #expect(decodedMessage == message)
    #expect(decodedEnvelope.frame.sequenceNumber == frame.sequenceNumber)
}

@Test func routeManagerFiltersOptedOutRoutes() async {
    let multipeer = FakeRoute(kind: .multipeer)
    let webRTC = FakeRoute(kind: .webRTC)

    let configuration = CallRouteConfiguration(
        enabledRoutes: [.multipeer],
        preferredRoute: .multipeer,
        selectionMode: .singleRoute
    )

    let manager = RouteManager(routes: [multipeer, webRTC], configuration: configuration)

    await manager.prepare(makeRequest(configuration: configuration))
    await manager.startConnection()
    await manager.sendApplicationData(ApplicationDataMessage(namespace: "test", payload: Data([9])))

    #expect(multipeer.prepareCount == 1)
    #expect(multipeer.startConnectionCount == 1)
    #expect(multipeer.sentApplicationData.count == 1)
    #expect(webRTC.prepareCount == 0)
    #expect(webRTC.startConnectionCount == 0)
    #expect(webRTC.sentApplicationData.isEmpty)
}

@Test func routeManagerAutomaticallyFallsBackToWebRTC() async {
    let multipeer = FakeRoute(kind: .multipeer)
    let webRTC = FakeRoute(kind: .webRTC)

    let configuration = CallRouteConfiguration(
        enabledRoutes: [.multipeer, .webRTC],
        preferredRoute: .multipeer,
        selectionMode: .automaticFallback,
        fallbackDelay: 0.01
    )

    let manager = RouteManager(routes: [multipeer, webRTC], configuration: configuration)

    await manager.prepare(makeRequest(configuration: configuration))
    await manager.startConnection()
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(multipeer.startConnectionCount == 1)
    #expect(webRTC.startConnectionCount >= 1)
}

@Test func routeManagerForwardsAudioOnlyToMediaRoute() async {
    let multipeer = FakeRoute(kind: .multipeer, supportsPacketAudio: true)
    let webRTC = FakeRoute(kind: .webRTC, supportsPacketAudio: false)

    let configuration = CallRouteConfiguration(enabledRoutes: [.multipeer, .webRTC], preferredRoute: .multipeer)
    let manager = RouteManager(routes: [multipeer, webRTC], configuration: configuration)

    await manager.prepare(makeRequest(configuration: configuration))
    await manager.startConnection()
    await manager.startMedia()
    await manager.sendAudioFrame(AudioFrame(sequenceNumber: 1, samples: [0.2]))

    #expect(multipeer.sentAudioFrames.count == 1)
    #expect(webRTC.sentAudioFrames.isEmpty)
}

@Test func webRTCRouteSendsOfferWhenRemotePeerJoins() async {
    let signaling = FakeWebRTCSignalingClient()
    let engine = FakeWebRTCEngine()
    let route = WebRTCInternetRoute(
        cloudflareConfiguration: makeCloudflareConfiguration(),
        signalingClient: signaling,
        engine: engine
    )

    await route.prepare(makeRequest())
    await route.startConnection()
    signaling.yield(.remotePeerJoined(PeerDescriptor(id: PeerID(rawValue: "remote"), displayName: "Remote")))
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(engine.createdPeerIDs == [PeerID(rawValue: "remote")])
    #expect(signaling.sentOffers.count == 1)
    #expect(signaling.sentOffers.first?.0 == WebRTCSessionDescription(kind: .offer, sdp: "offer-remote"))
    #expect(signaling.sentOffers.first?.1 == PeerID(rawValue: "remote"))
}

@Test func webRTCRouteForwardsLocalIceCandidatesToSignaling() async {
    let signaling = FakeWebRTCSignalingClient()
    let engine = FakeWebRTCEngine()
    let route = WebRTCInternetRoute(
        cloudflareConfiguration: makeCloudflareConfiguration(),
        signalingClient: signaling,
        engine: engine
    )
    _ = route

    let candidate = WebRTCIceCandidate(sdp: "candidate", sdpMid: "0", sdpMLineIndex: 0)
    engine.yield(.localIceCandidate(candidate, peerID: PeerID(rawValue: "remote")))
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(signaling.sentCandidates.count == 1)
    #expect(signaling.sentCandidates.first?.0 == candidate)
    #expect(signaling.sentCandidates.first?.1 == PeerID(rawValue: "remote"))
}

@Test func webRTCRouteCreatesPeerConnectionAndAnswersIncomingOffer() async {
    let signaling = FakeWebRTCSignalingClient()
    let engine = FakeWebRTCEngine()
    let route = WebRTCInternetRoute(
        cloudflareConfiguration: makeCloudflareConfiguration(),
        signalingClient: signaling,
        engine: engine
    )
    _ = route

    let peerID = PeerID(rawValue: "remote-offerer")
    let offer = WebRTCSessionDescription(kind: .offer, sdp: "remote-offer")
    signaling.yield(.offer(offer, from: peerID))
    try? await Task.sleep(nanoseconds: 50_000_000)

    #expect(engine.createdPeerIDs == [peerID])
    #expect(engine.acceptedOffers.count == 1)
    #expect(engine.acceptedOffers.first?.0 == offer)
    #expect(engine.acceptedOffers.first?.1 == peerID)
    #expect(signaling.sentAnswers.count == 1)
    #expect(signaling.sentAnswers.first?.0 == WebRTCSessionDescription(kind: .answer, sdp: "answer-remote-offerer"))
    #expect(signaling.sentAnswers.first?.1 == peerID)
}

private func makeRequest(configuration: CallRouteConfiguration = CallRouteConfiguration()) -> CallStartRequest {
    CallStartRequest(
        sessionID: "test-session",
        localPeer: PeerDescriptor(id: PeerID(rawValue: "local"), displayName: "Local"),
        credential: RTCCredential.derived(groupID: "test-group", secret: "secret"),
        configuration: configuration
    )
}

private func makeCloudflareConfiguration() -> CloudflareRealtimeConfiguration {
    CloudflareRealtimeConfiguration(
        sfuEndpoint: URL(string: "https://realtime.cloudflare.test")!,
        roomID: "test-room",
        participantToken: "test-token"
    )
}

private final class FakeRoute: RTCCallRoute {
    let kind: RouteKind
    let capabilities: RouteCapabilities
    let mediaOwnership: AudioMediaOwnership
    var events: AsyncStream<RouteEvent> { eventSource.stream }

    private let eventSource = EventSource<RouteEvent>()
    private(set) var prepareCount = 0
    private(set) var startConnectionCount = 0
    private(set) var startMediaCount = 0
    private(set) var sentApplicationData: [ApplicationDataMessage] = []
    private(set) var sentAudioFrames: [AudioFrame] = []

    init(kind: RouteKind, supportsPacketAudio: Bool = false) {
        self.kind = kind
        self.capabilities = RouteCapabilities(
            supportsLocalDiscovery: kind == .multipeer,
            supportsOfflineOperation: kind == .multipeer,
            supportsRouteManagedMedia: kind == .webRTC,
            supportsAppManagedPacketAudio: supportsPacketAudio,
            supportsReliableApplicationData: true,
            supportsUnreliableApplicationData: true,
            requiresSignaling: kind == .webRTC
        )
        self.mediaOwnership = supportsPacketAudio ? .appManagedPacketAudio : .routeManagedMediaStream
    }

    func prepare(_ request: CallStartRequest) async {
        prepareCount += 1
    }

    func startConnection() async {
        startConnectionCount += 1
    }

    func stopConnection() async {}

    func startMedia() async {
        startMediaCount += 1
    }

    func stopMedia() async {}

    func sendAudioFrame(_ frame: AudioFrame) async {
        sentAudioFrames.append(frame)
    }

    func sendApplicationData(_ message: ApplicationDataMessage) async {
        sentApplicationData.append(message)
    }

    func setLocalMute(_ muted: Bool) async {}
    func setOutputMute(_ muted: Bool) async {}
    func setRemoteOutputVolume(peerID: PeerID, volume: Float) async {}
}

private final class FakeWebRTCEngine: NativeWebRTCEngine {
    override var isAvailable: Bool { true }
    override var events: AsyncStream<WebRTCEngineEvent> { eventSource.stream }

    private let eventSource = EventSource<WebRTCEngineEvent>()
    private(set) var createdPeerIDs: [PeerID] = []
    private(set) var acceptedOffers: [(WebRTCSessionDescription, PeerID)] = []

    override func createPeerConnection(for peer: PeerDescriptor) async {
        createdPeerIDs.append(peer.id)
    }

    override func makeOffer(for peerID: PeerID) async -> WebRTCSessionDescription? {
        WebRTCSessionDescription(kind: .offer, sdp: "offer-\(peerID.rawValue)")
    }

    override func acceptOffer(_ offer: WebRTCSessionDescription, from peerID: PeerID) async -> WebRTCSessionDescription? {
        acceptedOffers.append((offer, peerID))
        return WebRTCSessionDescription(kind: .answer, sdp: "answer-\(peerID.rawValue)")
    }

    func yield(_ event: WebRTCEngineEvent) {
        eventSource.yield(event)
    }
}

private final class FakeWebRTCSignalingClient: WebRTCSignalingClient {
    var events: AsyncStream<WebRTCSignalingEvent> { eventSource.stream }

    private let eventSource = EventSource<WebRTCSignalingEvent>()
    private(set) var sentOffers: [(WebRTCSessionDescription, PeerID)] = []
    private(set) var sentAnswers: [(WebRTCSessionDescription, PeerID)] = []
    private(set) var sentCandidates: [(WebRTCIceCandidate, PeerID)] = []
    private(set) var sentApplicationData: [(ApplicationDataMessage, PeerID?)] = []

    func yield(_ event: WebRTCSignalingEvent) {
        eventSource.yield(event)
    }

    func connect(_ request: WebRTCSignalingConnectRequest) async {
        eventSource.yield(.connected)
    }

    func disconnect() async {
        eventSource.yield(.disconnected)
    }

    func sendOffer(_ offer: WebRTCSessionDescription, to peerID: PeerID) async {
        sentOffers.append((offer, peerID))
    }

    func sendAnswer(_ answer: WebRTCSessionDescription, to peerID: PeerID) async {
        sentAnswers.append((answer, peerID))
    }

    func sendCandidate(_ candidate: WebRTCIceCandidate, to peerID: PeerID) async {
        sentCandidates.append((candidate, peerID))
    }

    func sendApplicationData(_ message: ApplicationDataMessage, to peerID: PeerID?) async {
        sentApplicationData.append((message, peerID))
    }
}
