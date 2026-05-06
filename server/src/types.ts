export interface Env {
    SIGNALING_ROOM: DurableObjectNamespace
    CLOUDFLARE_SFU_APP_ID: string
    CLOUDFLARE_SFU_APP_SECRET: string
    CLOUDFLARE_TURN_KEY_ID: string
    CLOUDFLARE_TURN_API_TOKEN: string
}

// ── HTTP ──────────────────────────────────────────────────────────────────────

export interface SessionRequest {
    roomId: string
    participantId: string
    displayName: string
}

export interface SessionResponse {
    sessionId: string
    participantToken: string
    sfuEndpoint: string
    iceServers: IceServer[]
    signalingUrl: string
}

export interface IceServer {
    urls: string[]
    username?: string
    credential?: string
}

// ── WebSocket: client → server ────────────────────────────────────────────────

export type ClientMessage =
    | { type: 'offer';     to: string;        sdp: string }
    | { type: 'answer';    to: string;        sdp: string }
    | { type: 'candidate'; to: string;        sdp: string; sdpMid: string | null; sdpMLineIndex: number }
    | { type: 'appData';   to: string | null; namespace: string; payload: string }

// ── WebSocket: server → client ────────────────────────────────────────────────

export type ServerMessage =
    | { type: 'joined';     peer: PeerInfo }
    | { type: 'peerJoined'; peer: PeerInfo }
    | { type: 'peerLeft';   peerId: string }
    | { type: 'offer';      from: string; sdp: string }
    | { type: 'answer';     from: string; sdp: string }
    | { type: 'candidate';  from: string; sdp: string; sdpMid: string | null; sdpMLineIndex: number }
    | { type: 'appData';    from: string; namespace: string; payload: string }
    | { type: 'error';      message: string }

export interface PeerInfo {
    id: string
    displayName: string
}
