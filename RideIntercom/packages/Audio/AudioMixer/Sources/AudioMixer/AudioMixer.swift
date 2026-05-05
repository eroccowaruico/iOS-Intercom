@preconcurrency import AVFAudio

public enum AudioMixerError: Error, Equatable, Sendable {
	case emptyBusID
	case unknownBus(String)
	case invalidRoute(String)
	case busAlreadyRouted(String)
	case cycleDetected(source: String, destination: String)
	case invalidEffectIndex(Int)
	case incompatibleEffectNode
}

public struct AudioMixerSnapshot: Equatable, Sendable {
	public var busIDs: [String]
	public var buses: [MixerBusSnapshot]
	public var routes: [MixerRouteSnapshot]
	public var outputBusID: String?

	public init(busIDs: [String], buses: [MixerBusSnapshot], routes: [MixerRouteSnapshot], outputBusID: String?) {
		self.busIDs = busIDs
		self.buses = buses
		self.routes = routes
		self.outputBusID = outputBusID
	}
}

public struct MixerBusSnapshot: Equatable, Sendable {
	public var id: String
	public var volume: Float
	public var sourceCount: Int
	public var effectCount: Int

	public init(id: String, volume: Float, sourceCount: Int, effectCount: Int) {
		self.id = id
		self.volume = volume
		self.sourceCount = sourceCount
		self.effectCount = effectCount
	}
}

public struct MixerRouteSnapshot: Equatable, Sendable {
	public var sourceBusID: String
	public var destinationBusID: String

	public init(sourceBusID: String, destinationBusID: String) {
		self.sourceBusID = sourceBusID
		self.destinationBusID = destinationBusID
	}
}

public final class AudioMixer {
	public static let defaultFormat = AVAudioFormat(
		commonFormat: .pcmFormatFloat32,
		sampleRate: 48_000,
		channels: 2,
		interleaved: false
	)!

	public let engine: AVAudioEngine
	public let format: AVAudioFormat

	private var buses: [String: MixerBus] = [:]
	private var parentByChildID: [String: String] = [:]
	private var outputBusID: String?

	public init(engine: AVAudioEngine = AVAudioEngine(), format: AVAudioFormat = AudioMixer.defaultFormat) {
		self.engine = engine
		self.format = format
	}

	public var busIDs: [String] {
		buses.keys.sorted()
	}

	public func snapshot() -> AudioMixerSnapshot {
		let ids = busIDs
		return AudioMixerSnapshot(
			busIDs: ids,
			buses: ids.compactMap { buses[$0]?.snapshot() },
			routes: parentByChildID
				.map { MixerRouteSnapshot(sourceBusID: $0.key, destinationBusID: $0.value) }
				.sorted {
					if $0.sourceBusID != $1.sourceBusID {
						return $0.sourceBusID < $1.sourceBusID
					}
					return $0.destinationBusID < $1.destinationBusID
				},
			outputBusID: outputBusID
		)
	}

	@discardableResult
	public func createBus(_ id: String) throws -> MixerBus {
		guard !id.isEmpty else {
			throw AudioMixerError.emptyBusID
		}

		if let existing = buses[id] {
			return existing
		}

		let bus = MixerBus(id: id, engine: engine, format: format)
		engine.attach(bus.inputMixer)
		engine.attach(bus.faderMixer)
		bus.rebuildChain()
		buses[id] = bus
		return bus
	}

	public func bus(_ id: String) -> MixerBus? {
		buses[id]
	}

	public func route(_ source: MixerBus, to destination: MixerBus) throws {
		try validateManaged(source)
		try validateManaged(destination)

		guard source.id != destination.id else {
			throw AudioMixerError.invalidRoute(source.id)
		}
		guard parentByChildID[source.id] == nil, outputBusID != source.id else {
			throw AudioMixerError.busAlreadyRouted(source.id)
		}
		guard !createsCycle(sourceID: source.id, destinationID: destination.id) else {
			throw AudioMixerError.cycleDetected(source: source.id, destination: destination.id)
		}

		let inputBus = destination.inputMixer.nextAvailableInputBus
		engine.connect(source.outputNode, to: destination.inputMixer, fromBus: 0, toBus: inputBus, format: format)
		parentByChildID[source.id] = destination.id
	}

	public func routeToOutput(_ source: MixerBus) throws {
		try validateManaged(source)

		guard parentByChildID[source.id] == nil, outputBusID != source.id else {
			throw AudioMixerError.busAlreadyRouted(source.id)
		}
		guard outputBusID == nil else {
			throw AudioMixerError.busAlreadyRouted(outputBusID ?? source.id)
		}

		engine.connect(source.outputNode, to: engine.mainMixerNode, format: format)
		outputBusID = source.id
	}

	public func start() throws {
		engine.prepare()
		try engine.start()
	}

	public func stop() {
		engine.stop()
	}

	private func validateManaged(_ bus: MixerBus) throws {
		guard buses[bus.id] === bus else {
			throw AudioMixerError.unknownBus(bus.id)
		}
	}

	private func createsCycle(sourceID: String, destinationID: String) -> Bool {
		var currentID: String? = destinationID
		while let id = currentID {
			if id == sourceID {
				return true
			}
			currentID = parentByChildID[id]
		}
		return false
	}
}

public final class MixerBus {
	public let id: String
	public let inputMixer: AVAudioMixerNode
	public let faderMixer: AVAudioMixerNode

	private unowned let engine: AVAudioEngine
	private let format: AVAudioFormat
	private var sourceNodeIDs: Set<ObjectIdentifier> = []
	private var effectNodeIDs: Set<ObjectIdentifier> = []

	public private(set) var effects: [AVAudioNode] = []

	public var volume: Float {
		get { faderMixer.outputVolume }
		set { faderMixer.outputVolume = newValue }
	}

	public var outputNode: AVAudioNode {
		faderMixer
	}

	init(id: String, engine: AVAudioEngine, format: AVAudioFormat) {
		self.id = id
		self.engine = engine
		self.format = format
		self.inputMixer = AVAudioMixerNode()
		self.faderMixer = AVAudioMixerNode()
	}

	public func addSource(_ node: AVAudioNode) throws {
		let nodeID = ObjectIdentifier(node)
		guard !sourceNodeIDs.contains(nodeID) else {
			throw AudioMixerError.invalidRoute(id)
		}
		guard !isEngineInternalNode(node) else {
			throw AudioMixerError.incompatibleEffectNode
		}

		engine.attach(node)
		let inputBus = inputMixer.nextAvailableInputBus
		engine.connect(node, to: inputMixer, fromBus: 0, toBus: inputBus, format: format)
		sourceNodeIDs.insert(nodeID)
	}

	public func snapshot() -> MixerBusSnapshot {
		MixerBusSnapshot(
			id: id,
			volume: volume,
			sourceCount: sourceNodeIDs.count,
			effectCount: effects.count
		)
	}

	public func addEffect(_ node: AVAudioNode) throws {
		let nodeID = ObjectIdentifier(node)
		guard !effectNodeIDs.contains(nodeID) else {
			throw AudioMixerError.invalidRoute(id)
		}
		guard !isEngineInternalNode(node) else {
			throw AudioMixerError.incompatibleEffectNode
		}

		// Nodes with no output bus cannot pass audio downstream
		guard node.numberOfOutputs > 0 else {
			throw AudioMixerError.incompatibleEffectNode
		}

		engine.attach(node)

		// For AVAudioUnit nodes with pre-configured bus formats (e.g. custom AUAudioUnit
		// subclasses), validate that their format matches the mixer before connecting.
		// AVAudioUnitEffect nodes are excluded because they negotiate format at connect time.
		if let auNode = node as? AVAudioUnit, !(node is AVAudioUnitEffect),
		   auNode.auAudioUnit.outputBusses.count > 0 {
			let nodeFmt = auNode.auAudioUnit.outputBusses[0].format
			if nodeFmt.sampleRate > 0,
			   nodeFmt.sampleRate != format.sampleRate || nodeFmt.channelCount != format.channelCount {
				engine.detach(node)
				throw AudioMixerError.incompatibleEffectNode
			}
		}

		effects.append(node)
		effectNodeIDs.insert(nodeID)
		rebuildChain()
	}

	private func isEngineInternalNode(_ node: AVAudioNode) -> Bool {
		node === engine.inputNode || node === engine.outputNode || node === engine.mainMixerNode
	}

	public func removeEffect(at index: Int) throws {
		guard effects.indices.contains(index) else {
			throw AudioMixerError.invalidEffectIndex(index)
		}

		let removed = effects.remove(at: index)
		effectNodeIDs.remove(ObjectIdentifier(removed))
		engine.disconnectNodeOutput(removed)
		engine.disconnectNodeInput(removed)
		engine.detach(removed)
		rebuildChain()
	}

	func rebuildChain() {
		engine.disconnectNodeOutput(inputMixer)
		for effect in effects {
			engine.disconnectNodeOutput(effect)
		}

		var previous: AVAudioNode = inputMixer
		for effect in effects {
			engine.connect(previous, to: effect, format: format)
			previous = effect
		}

		engine.connect(previous, to: faderMixer, format: format)
	}
}
