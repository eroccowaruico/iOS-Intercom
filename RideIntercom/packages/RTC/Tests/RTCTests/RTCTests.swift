import Foundation
import Testing
@testable import RTC

@Test func codecIdentifiersMatchAudioCodecRawValues() {
    #expect(AudioCodecIdentifier.pcm16.rawValue == "pcm16")
    #expect(AudioCodecIdentifier.mpeg4AACELDv2.rawValue == "mpeg4AACELDv2")
    #expect(AudioCodecIdentifier.opus.rawValue == "opus")
}

@Test func applicationDataAndPacketAudioUseDifferentWirePayloads() throws {
    let message = ApplicationDataMessage(namespace: "rideintercom.presence", payload: Data([1, 2, 3]), delivery: .reliable)
    let appPayload = try MultipeerPayloadBuilder.makeApplicationDataPayload(message)
    let appWire = try MultipeerPayloadBuilder.decode(appPayload.data, credential: nil)

    let request = makeRequest()
    let sequencer = PacketAudioSequencer(
        sessionID: request.sessionID,
        senderID: request.localPeer.id,
        codecID: .pcm16,
        codecRegistry: .packetAudioDefault
    )
    let frame = AudioFrame(sequenceNumber: 7, samples: [0.0, 0.5, -0.5])

    let audioPayload = try MultipeerPayloadBuilder.makePacketAudioPayload(try sequencer.makeEnvelope(from: frame), credential: nil)
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

@Test func runtimeStatusApplicationDataRoundTripsThroughPackageNamespace() throws {
    let status = RTCRuntimeStatus(
        reason: .connectionStarted,
        generatedAt: 123,
        sessionID: "session",
        localPeer: PeerDescriptor(id: PeerID(rawValue: "local"), displayName: "Local"),
        expectedPeers: [PeerDescriptor(id: PeerID(rawValue: "remote"), displayName: "Remote")],
        connectionState: .connected,
        isMediaStarted: false,
        localMute: false,
        outputMute: false,
        remoteOutputVolumes: [
            RTCPeerOutputVolume(peerID: PeerID(rawValue: "remote"), volume: 0.75),
        ],
        routeSnapshot: ActiveRouteSnapshot(
            activeRoute: .multipeer,
            mediaRoute: .multipeer,
            availableRoutes: [.multipeer],
            isHandoverInProgress: false
        ),
        routes: [
            RTCRouteRuntimeStatus(
                route: .multipeer,
                state: .connected,
                isAvailable: true,
                availabilityReason: nil,
                capabilities: RouteCapabilities(
                    supportsLocalDiscovery: true,
                    supportsOfflineOperation: true,
                    supportsRouteManagedMedia: false,
                    supportsAppManagedPacketAudio: true,
                    supportsReliableApplicationData: true,
                    supportsUnreliableApplicationData: true,
                    requiresSignaling: false,
                    supportedAudioCodecs: [.pcm16],
                    backendName: "test"
                ),
                mediaOwnership: .appManagedPacketAudio,
                isActiveRoute: true,
                isMediaRoute: true,
                selectedAudioCodec: .pcm16
            ),
        ],
        packageReports: [
            RTCRuntimePackageReport(
                package: "Codec",
                kind: "runtime",
                generatedAt: 122,
                payload: Data([1, 2, 3])
            ),
        ],
        configuration: CallRouteConfiguration(),
        audioFormat: AudioFormatDescriptor(),
        audioCodecConfiguration: AudioCodecConfiguration()
    )

    let message = try RTCRuntimeStatusTransport.makeMessage(status)
    let decoded = try RTCRuntimeStatusTransport.decode(message)

    #expect(message.namespace == RTCRuntimeStatusTransport.namespace)
    #expect(message.delivery == .unreliable)
    #expect(decoded == status)
}

@Test func packetAudioUsesSelectedCodecFromRegistry() throws {
    let codecID = AudioCodecIdentifier.mpeg4AACELDv2
    let registry = AudioCodecRegistry(codecs: [makeAppBridgeStyleCodec(identifier: codecID), PCM16AudioCodec()])
    let request = makeRequest(
        credential: nil,
        audioCodecConfiguration: AudioCodecConfiguration(preferredCodecs: [codecID, .pcm16])
    )
    let session = try MultipeerPacketMediaSession(
        request: request,
        codecRegistry: registry,
        receiveConfiguration: PacketAudioReceiveConfiguration(playoutDelay: 0)
    )
    session.isActive = true

    let sentFrame = AudioFrame(sequenceNumber: 3, samples: [0.1, -0.25, 0.5])
    let payload = try #require(try session.makePayload(from: sentFrame))
    let message = try MultipeerPayloadBuilder.decode(payload.data, credential: nil)

    guard case .packetAudio(let envelope) = message else {
        Issue.record("Expected packet audio payload")
        return
    }

    let report = try #require(try session.accept(
        envelope,
        from: PeerID(rawValue: "remote"),
        receivedAt: 10
    ))
    let received = try #require(report.readyFrames.first)
    #expect(envelope.frame.codec == codecID)
    #expect(envelope.frame.format == sentFrame.format)
    #expect(envelope.frame.sampleCount == sentFrame.samples.count)
    #expect(received.frame == sentFrame)
}

@Test func packetAudioRejectsUnsupportedCodecPreference() throws {
    let request = makeRequest(
        audioCodecConfiguration: AudioCodecConfiguration(preferredCodecs: [.opus])
    )

    do {
        _ = try MultipeerPacketMediaSession(request: request, codecRegistry: .packetAudioDefault)
        Issue.record("Expected unsupported codec error")
    } catch AudioCodecError.noMutuallySupportedCodec(let preferred, let supported) {
        #expect(preferred == [.opus])
        #expect(supported == [.pcm16])
    }
}

@Test func packetAudioReceiveBufferDrainsFramesAfterDelayInStableOrder() {
    var buffer = PacketAudioReceiveBuffer(configuration: PacketAudioReceiveConfiguration(
        playoutDelay: 0.08,
        packetLifetime: 1.0
    ))

    buffer.enqueue(makeFilteredPacketAudioFrame(peerID: "remote", sequenceNumber: 2), receivedAt: 10.00)
    buffer.enqueue(makeFilteredPacketAudioFrame(peerID: "remote", sequenceNumber: 1), receivedAt: 10.01)

    #expect(buffer.drainReadyFrames(now: 10.05).isEmpty)

    let ready = buffer.drainReadyFrames(now: 10.10)

    #expect(ready.map(\.frame.sequenceNumber) == [1, 2])
    #expect(buffer.queuedFrameCount == 0)
}

@Test func packetAudioReceiveFilterDropsDuplicateFramesBeforeJitterBuffer() throws {
    let request = makeRequest()
    let sequencer = PacketAudioSequencer(
        sessionID: request.sessionID,
        senderID: request.localPeer.id,
        codecID: .pcm16,
        codecRegistry: .packetAudioDefault
    )
    let envelope = try sequencer.makeEnvelope(from: AudioFrame(sequenceNumber: 1, samples: [0.4]))
    var filter = PacketAudioReceiveFilter(sessionID: request.sessionID, codecRegistry: .packetAudioDefault)

    let first = try filter.accept(envelope, from: PeerID(rawValue: "remote"))
    let duplicate = try filter.accept(envelope, from: PeerID(rawValue: "remote"))

    #expect(first?.received.frame.sequenceNumber == 1)
    #expect(duplicate == nil)
}

@Test func packetAudioReceiveBufferDropsExpiredFrames() {
    var buffer = PacketAudioReceiveBuffer(configuration: PacketAudioReceiveConfiguration(
        playoutDelay: 0.01,
        packetLifetime: 0.50
    ))

    buffer.enqueue(makeFilteredPacketAudioFrame(peerID: "remote", sequenceNumber: 1), receivedAt: 20.00)
    buffer.enqueue(makeFilteredPacketAudioFrame(peerID: "remote", sequenceNumber: 2), receivedAt: 20.00)

    let report = buffer.drain(now: 20.60)

    #expect(report.readyFrames.isEmpty)
    #expect(report.expiredFrameCount == 2)
    #expect(report.receivedFrameCount == 2)
    #expect(report.droppedFrameCount == 2)
    #expect(report.queuedFrameCount == 0)
    #expect(buffer.queuedFrameCount == 0)
    #expect(buffer.droppedFrameCount == 2)
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
    #expect(multipeer.sentApplicationData.filter { $0.namespace == "test" }.count == 1)
    #expect(webRTC.prepareCount == 0)
    #expect(webRTC.startConnectionCount == 0)
    #expect(webRTC.sentApplicationData.isEmpty)
}

@Test func routeManagerBroadcastsRuntimeStatusWhenConnectionStarts() async throws {
    let multipeer = FakeRoute(kind: .multipeer, supportsPacketAudio: true)
    let configuration = CallRouteConfiguration(enabledRoutes: [.multipeer], preferredRoute: .multipeer)
    let request = makeRequest(
        configuration: configuration,
        audioCodecConfiguration: AudioCodecConfiguration(preferredCodecs: [.pcm16])
    )
    let manager = RouteManager(routes: [multipeer], configuration: configuration)

    await manager.prepare(request)
    await manager.startConnection()

    let messages = multipeer.sentApplicationData.filter { $0.namespace == RTCRuntimeStatusTransport.namespace }
    let firstMessage = try #require(messages.first)
    let status = try #require(try RTCRuntimeStatusTransport.decode(firstMessage))
    #expect(status.reason == .connectionStarted)
    #expect(status.sessionID == request.sessionID)
    #expect(status.localPeer == request.localPeer)
    #expect(status.configuration == configuration)
    #expect(status.audioCodecConfiguration == request.audioCodecConfiguration)
    #expect(status.routes.first?.selectedAudioCodec == .pcm16)
}

@Test func routeManagerCanAttachPackageRuntimeReportsToBroadcastStatus() async throws {
    let multipeer = FakeRoute(kind: .multipeer, supportsPacketAudio: true)
    let manager = RouteManager(
        routes: [multipeer],
        configuration: CallRouteConfiguration(enabledRoutes: [.multipeer], preferredRoute: .multipeer)
    )
    let report = RTCRuntimePackageReport(
        package: "AudioMixer",
        kind: "snapshot",
        generatedAt: 10,
        payload: Data([9])
    )

    await manager.prepare(makeRequest())
    await manager.startConnection()
    await manager.updateRuntimePackageReports([report])

    let statuses = try multipeer.sentApplicationData
        .filter { $0.namespace == RTCRuntimeStatusTransport.namespace }
        .compactMap { try RTCRuntimeStatusTransport.decode($0) }
    let status = try #require(statuses.last)
    #expect(status.reason == .packageReportsChanged)
    #expect(status.packageReports == [report])
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

private func makeRequest(
    configuration: CallRouteConfiguration = CallRouteConfiguration(),
    credential: RTCCredential? = RTCCredential.derived(groupID: "test-group", secret: "secret"),
    audioCodecConfiguration: AudioCodecConfiguration = AudioCodecConfiguration()
) -> CallStartRequest {
    CallStartRequest(
        sessionID: "test-session",
        localPeer: PeerDescriptor(id: PeerID(rawValue: "local"), displayName: "Local"),
        credential: credential,
        configuration: configuration,
        audioCodecConfiguration: audioCodecConfiguration
    )
}

private func makeCloudflareConfiguration() -> CloudflareRealtimeConfiguration {
    CloudflareRealtimeConfiguration(
        sfuEndpoint: URL(string: "https://realtime.cloudflare.test")!,
        roomID: "test-room",
        participantToken: "test-token"
    )
}

private func makeFilteredPacketAudioFrame(
    peerID: String,
    sequenceNumber: UInt64
) -> FilteredPacketAudioFrame {
    FilteredPacketAudioFrame(
        received: ReceivedAudioFrame(
            peerID: PeerID(rawValue: peerID),
            frame: AudioFrame(sequenceNumber: sequenceNumber, samples: [Float(sequenceNumber)])
        )
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
            requiresSignaling: kind == .webRTC,
            supportedAudioCodecs: supportsPacketAudio ? [.pcm16] : [.routeManaged]
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

private func makeAppBridgeStyleCodec(identifier: AudioCodecIdentifier) -> AnyAudioFrameCodec {
    AnyAudioFrameCodec(
        identifier: identifier,
        encode: { frame in
            let payload = try JSONEncoder().encode(Array(frame.samples.reversed()))
            return EncodedAudioFrame(
                sequenceNumber: frame.sequenceNumber,
                codec: identifier,
                format: frame.format,
                capturedAt: frame.capturedAt,
                sampleCount: frame.samples.count,
                payload: payload
            )
        },
        decode: { frame in
            guard frame.codec == identifier else {
                throw AudioCodecError.unsupportedCodec(frame.codec)
            }
            let reversedSamples = try JSONDecoder().decode([Float].self, from: frame.payload)
            return AudioFrame(
                sequenceNumber: frame.sequenceNumber,
                format: frame.format,
                capturedAt: frame.capturedAt,
                samples: Array(reversedSamples.reversed())
            )
        }
    )
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
