import Foundation

public final class RouteManager: CallSession {
    public var events: AsyncStream<CallSessionEvent> { eventSource.stream }

    private let eventSource = EventSource<CallSessionEvent>()
    private var routes: [RouteKind: RTCCallRoute]
    private var routeTasks: [Task<Void, Never>] = []
    private var configuration: CallRouteConfiguration
    private var request: CallStartRequest?
    private var activeRoute: RouteKind?
    private var mediaRoute: RouteKind?
    private var availableRoutes: Set<RouteKind> = []
    private var isMediaStarted = false
    private var fallbackTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var handoverTask: Task<Void, Never>?

    public init(routes: [RTCCallRoute], configuration: CallRouteConfiguration = CallRouteConfiguration()) {
        let normalizedConfiguration = configuration.normalized()
        self.configuration = normalizedConfiguration
        self.routes = Dictionary(
            uniqueKeysWithValues: routes
                .filter { normalizedConfiguration.enabledRoutes.contains($0.kind) }
                .map { ($0.kind, $0) }
        )
        bindRouteEvents()
    }

    public convenience init(routeFactories: [AnyRouteFactory], configuration: CallRouteConfiguration = CallRouteConfiguration()) {
        let normalizedConfiguration = configuration.normalized()
        self.init(
            routes: routeFactories
                .filter { normalizedConfiguration.enabledRoutes.contains($0.kind) }
                .map { $0.make() },
            configuration: normalizedConfiguration
        )
    }

    deinit {
        routeTasks.forEach { $0.cancel() }
        fallbackTask?.cancel()
        restoreTask?.cancel()
        handoverTask?.cancel()
    }

    public func prepare(_ request: CallStartRequest) async {
        let normalizedRequest = CallStartRequest(
            sessionID: request.sessionID,
            localPeer: request.localPeer,
            expectedPeers: request.expectedPeers,
            credential: request.credential,
            configuration: request.configuration.normalized(),
            audioFormat: request.audioFormat
        )

        self.request = normalizedRequest
        self.configuration = normalizedRequest.configuration
        self.routes = routes.filter { configuration.enabledRoutes.contains($0.key) }
        emit(.stateChanged(.preparing))

        guard !routes.isEmpty else {
            emit(.error(.noEnabledRoute))
            emit(.stateChanged(.failed))
            return
        }

        for route in routes.values {
            await route.prepare(normalizedRequest)
        }

        emitRouteSnapshot()
    }

    public func startConnection() async {
        guard let request else {
            emit(.error(.connectionFailed(configuration.preferredRoute, "prepare must be called before startConnection")))
            return
        }

        emit(.stateChanged(.connecting))

        if configuration.keepsPreferredRouteInStandby {
            for standbyKind in configuration.enabledRoutes where standbyKind != configuration.preferredRoute {
                await routes[standbyKind]?.startConnection()
            }
        }

        guard let preferredRoute = routes[configuration.preferredRoute] else {
            emit(.error(.routeUnavailable(configuration.preferredRoute)))
            await activateFirstAvailableRoute(excluding: nil)
            return
        }

        activeRoute = preferredRoute.kind
        mediaRoute = preferredRoute.kind
        emitRouteSnapshot()
        await preferredRoute.startConnection()
        scheduleFallbackIfNeeded(for: request)
    }

    public func stopConnection() async {
        cancelTimers()
        for route in routes.values {
            await route.stopMedia()
            await route.stopConnection()
        }
        activeRoute = nil
        mediaRoute = nil
        availableRoutes.removeAll()
        isMediaStarted = false
        emitRouteSnapshot()
        emit(.stateChanged(.disconnected))
    }

    public func startMedia() async {
        guard !isMediaStarted else { return }
        isMediaStarted = true
        if let route = activeRoute.flatMap({ routes[$0] }) {
            mediaRoute = route.kind
            await route.startMedia()
            emitRouteSnapshot()
        }
    }

    public func stopMedia() async {
        guard isMediaStarted else { return }
        isMediaStarted = false
        if let route = mediaRoute.flatMap({ routes[$0] }) {
            await route.stopMedia()
        }
        mediaRoute = activeRoute
        emitRouteSnapshot()
    }

    public func sendAudioFrame(_ frame: AudioFrame) async {
        guard let route = mediaRoute.flatMap({ routes[$0] }), route.capabilities.supportsAppManagedPacketAudio else { return }
        await route.sendAudioFrame(frame)
    }

    public func sendApplicationData(_ message: ApplicationDataMessage) async {
        guard let route = activeRoute.flatMap({ routes[$0] }) else { return }
        guard route.supports(message.delivery) else {
            emit(.error(.unsupportedApplicationDataDelivery(route.kind, message.delivery)))
            return
        }
        await route.sendApplicationData(message)
    }

    public func setLocalMute(_ muted: Bool) async {
        for route in routes.values {
            await route.setLocalMute(muted)
        }
    }

    public func setOutputMute(_ muted: Bool) async {
        for route in routes.values {
            await route.setOutputMute(muted)
        }
    }

    public func setRemoteOutputVolume(peerID: PeerID, volume: Float) async {
        for route in routes.values {
            await route.setRemoteOutputVolume(peerID: peerID, volume: volume)
        }
    }

    private func bindRouteEvents() {
        routeTasks.forEach { $0.cancel() }
        routeTasks = routes.values.map { route in
            Task { [weak self, weak route] in
                guard let route else { return }
                for await event in route.events {
                    await self?.handle(event)
                }
            }
        }
    }

    private func handle(_ event: RouteEvent) async {
        switch event {
        case .stateChanged(let kind, let state):
            await handleRouteState(kind: kind, state: state)
        case .availabilityChanged(let availability):
            if availability.isAvailable {
                availableRoutes.insert(availability.route)
            } else {
                availableRoutes.remove(availability.route)
            }
            emit(.routeAvailabilityChanged([availability]))
            emitRouteSnapshot()
        case .membersChanged(_, let members):
            emit(.membersChanged(members))
        case .receivedApplicationData(_, let data):
            emit(.receivedApplicationData(data))
        case .receivedAudioFrame(_, let frame):
            emit(.receivedAudioFrame(frame))
        case .metricsChanged(let metrics):
            emit(.metricsChanged(metrics))
        case .error(_, let error):
            emit(.error(error))
        }
    }

    private func handleRouteState(kind: RouteKind, state: RouteConnectionState) async {
        switch state {
        case .connected, .authenticated, .mediaReady:
            availableRoutes.insert(kind)
            if activeRoute == kind {
                fallbackTask?.cancel()
                fallbackTask = nil
                emit(.stateChanged(state == .mediaReady ? .mediaReady : .connected))
            } else if shouldRestorePreferredRoute(from: kind) {
                scheduleRestoreToPreferredRoute()
            }
        case .failed, .disconnected:
            availableRoutes.remove(kind)
            if activeRoute == kind {
                await failover(from: kind)
            }
        default:
            break
        }
        emitRouteSnapshot()
    }

    private func shouldRestorePreferredRoute(from kind: RouteKind) -> Bool {
        configuration.selectionMode == .automaticFallbackAndRestore
            && kind == configuration.preferredRoute
            && activeRoute != configuration.preferredRoute
            && routes[kind] != nil
    }

    private func scheduleFallbackIfNeeded(for request: CallStartRequest) {
        fallbackTask?.cancel()
        guard configuration.selectionMode != .singleRoute,
              configuration.enabledRoutes.count > 1,
              activeRoute == configuration.preferredRoute else { return }

        fallbackTask = Task { [weak self] in
            let delay = UInt64(max(0, request.configuration.fallbackDelay) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.activateFallbackRoute()
        }
    }

    private func scheduleRestoreToPreferredRoute() {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(max(0, configuration.restoreProbeDuration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self.handover(to: self.configuration.preferredRoute)
        }
    }

    private func activateFallbackRoute() async {
        guard activeRoute == configuration.preferredRoute else { return }
        await activateFirstAvailableRoute(excluding: activeRoute)
    }

    private func activateFirstAvailableRoute(excluding excludedRoute: RouteKind?) async {
        guard let nextRoute = routes.values.first(where: { $0.kind != excludedRoute }) else {
            emit(.stateChanged(.failed))
            emit(.error(.noEnabledRoute))
            return
        }
        await handover(to: nextRoute.kind)
    }

    private func failover(from routeKind: RouteKind) async {
        guard configuration.selectionMode != .singleRoute else {
            emit(.stateChanged(.failed))
            return
        }
        await activateFirstAvailableRoute(excluding: routeKind)
    }

    private func handover(to nextKind: RouteKind) async {
        guard let nextRoute = routes[nextKind], activeRoute != nextKind else { return }
        let previousKind = activeRoute
        let previousRoute = previousKind.flatMap { routes[$0] }

        activeRoute = nextKind
        emitRouteSnapshot(isHandoverInProgress: true)
        await nextRoute.startConnection()

        if isMediaStarted {
            await nextRoute.startMedia()
            mediaRoute = nextKind
            let delay = UInt64(max(0, configuration.handoverFadeDuration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            await previousRoute?.stopMedia()
        }

        if previousKind != configuration.preferredRoute || !configuration.keepsFallbackRouteWarm {
            await previousRoute?.stopConnection()
        }

        emitRouteSnapshot(isHandoverInProgress: false)
    }

    private func cancelTimers() {
        fallbackTask?.cancel()
        restoreTask?.cancel()
        handoverTask?.cancel()
        fallbackTask = nil
        restoreTask = nil
        handoverTask = nil
    }

    private func emitRouteSnapshot(isHandoverInProgress: Bool = false) {
        emit(.routeChanged(ActiveRouteSnapshot(
            activeRoute: activeRoute,
            mediaRoute: mediaRoute,
            availableRoutes: availableRoutes,
            isHandoverInProgress: isHandoverInProgress
        )))
    }

    private func emit(_ event: CallSessionEvent) {
        eventSource.yield(event)
    }
}

private extension RTCCallRoute {
    func supports(_ delivery: ApplicationDataDelivery) -> Bool {
        switch delivery {
        case .reliable:
            capabilities.supportsReliableApplicationData
        case .unreliable:
            capabilities.supportsUnreliableApplicationData
        }
    }
}
