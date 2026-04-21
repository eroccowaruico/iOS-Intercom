import Foundation

struct HandleMicrophoneInputResult: Equatable {
    let packets: [OutboundAudioPacket]
    let isVoiceActive: Bool
}

enum HandleMicrophoneInputUseCase {
    static func execute(
        controller: inout AudioTransmissionController,
        frameID: Int,
        level: Float,
        samples: [Float]
    ) -> HandleMicrophoneInputResult {
        let packets = controller.process(frameID: frameID, level: level, samples: samples)
        return HandleMicrophoneInputResult(
            packets: packets,
            isVoiceActive: packets.contains { packet in
                if case .voice = packet {
                    return true
                }
                return false
            }
        )
    }
}