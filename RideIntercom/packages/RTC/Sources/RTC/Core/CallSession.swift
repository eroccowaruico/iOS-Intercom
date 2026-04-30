import Foundation

public struct CallStartRequest: Equatable, Sendable {
    public var sessionID: String
    public var localPeer: PeerDescriptor
    public var expectedPeers: [PeerDescriptor]
    public var credential: RTCCredential?
    public var configuration: CallRouteConfiguration
    public var audioFormat: AudioFormatDescriptor

    public init(
        sessionID: String,
        localPeer: PeerDescriptor,
        expectedPeers: [PeerDescriptor] = [],
        credential: RTCCredential? = nil,
        configuration: CallRouteConfiguration = CallRouteConfiguration(),
        audioFormat: AudioFormatDescriptor = AudioFormatDescriptor()
    ) {
        self.sessionID = sessionID
        self.localPeer = localPeer
        self.expectedPeers = expectedPeers
        self.credential = credential
        self.configuration = configuration.normalized()
        self.audioFormat = audioFormat
    }
}

public protocol CallSession: AnyObject {
    var events: AsyncStream<CallSessionEvent> { get }

    func prepare(_ request: CallStartRequest) async
    func startConnection() async
    func stopConnection() async
    func startMedia() async
    func stopMedia() async
    func sendAudioFrame(_ frame: AudioFrame) async
    func sendApplicationData(_ message: ApplicationDataMessage) async
    func setLocalMute(_ muted: Bool) async
    func setOutputMute(_ muted: Bool) async
    func setRemoteOutputVolume(peerID: PeerID, volume: Float) async
}
