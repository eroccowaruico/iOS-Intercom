import type { Env, ClientMessage, ServerMessage, PeerInfo } from './types'

export class SignalingRoom {
    constructor(private state: DurableObjectState, private env: Env) {}

    async fetch(request: Request): Promise<Response> {
        const url = new URL(request.url)
        const participantId = url.searchParams.get('participantId')
        const displayName = url.searchParams.get('displayName') ?? participantId ?? 'Unknown'

        if (!participantId) {
            return new Response('Missing participantId', { status: 400 })
        }
        if (request.headers.get('Upgrade') !== 'websocket') {
            return new Response('Expected WebSocket upgrade', { status: 426 })
        }

        const { 0: client, 1: server } = new WebSocketPair()

        // Hibernation API: runtime calls webSocketMessage/webSocketClose on this class instance.
        // Tags: [participantId, displayName] — both stored so we can reconstruct PeerInfo without storage reads.
        this.state.acceptWebSocket(server, [participantId, displayName])

        // Send existing participants before yielding client socket
        const existing = this.activePeers().filter(p => p.id !== participantId)
        for (const peer of existing) {
            server.send(send({ type: 'peerJoined', peer }))
        }
        server.send(send({ type: 'joined', peer: { id: participantId, displayName } }))

        // Notify others
        this.broadcastExcept({ type: 'peerJoined', peer: { id: participantId, displayName } }, participantId)

        return new Response(null, { status: 101, webSocket: client })
    }

    webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): void {
        const [senderId] = this.state.getTags(ws)
        if (!senderId) return

        let msg: ClientMessage
        try {
            msg = JSON.parse(typeof message === 'string' ? message : new TextDecoder().decode(message))
        } catch {
            ws.send(send({ type: 'error', message: 'Invalid JSON' }))
            return
        }

        switch (msg.type) {
            case 'offer':
            case 'answer':
            case 'candidate': {
                const [targetWs] = this.state.getWebSockets(msg.to)
                if (targetWs) targetWs.send(send({ ...msg, from: senderId } as ServerMessage))
                break
            }
            case 'appData': {
                const forward: ServerMessage = { type: 'appData', from: senderId, namespace: msg.namespace, payload: msg.payload }
                if (msg.to) {
                    const [targetWs] = this.state.getWebSockets(msg.to)
                    targetWs?.send(send(forward))
                } else {
                    this.broadcastExcept(forward, senderId)
                }
                break
            }
        }
    }

    webSocketClose(ws: WebSocket): void {
        const [participantId] = this.state.getTags(ws)
        if (!participantId) return
        this.broadcastExcept({ type: 'peerLeft', peerId: participantId }, participantId)
    }

    webSocketError(ws: WebSocket): void {
        this.webSocketClose(ws)
    }

    private activePeers(): PeerInfo[] {
        return this.state.getWebSockets().map(ws => {
            const [id, displayName] = this.state.getTags(ws)
            return { id, displayName: displayName ?? id }
        })
    }

    private broadcastExcept(msg: ServerMessage, excludeId?: string): void {
        const json = send(msg)
        for (const ws of this.state.getWebSockets()) {
            const [id] = this.state.getTags(ws)
            if (id !== excludeId) {
                try { ws.send(json) } catch { /* disconnected */ }
            }
        }
    }
}

function send(msg: ServerMessage): string {
    return JSON.stringify(msg)
}
