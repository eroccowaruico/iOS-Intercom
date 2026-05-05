import Testing
@testable import SoundIsolation
import AudioToolbox
import Foundation

@Test func componentDescriptionTargetsAppleSoundIsolationEffect() {
    let description = VoiceIsolationSupport.componentDescription

    #expect(description.componentType == kAudioUnitType_Effect)
    #expect(description.componentSubType == kAudioUnitSubType_AUSoundIsolation)
    #expect(description.componentManufacturer == kAudioUnitManufacturer_Apple)
    #expect(description.componentFlags == 0)
    #expect(description.componentFlagsMask == 0)
}

@Test func configurationClampsMixToAudioUnitRange() {
    #expect(VoiceIsolationConfiguration(mix: -0.25).mix == 0)
    #expect(VoiceIsolationConfiguration(mix: 0.5).mix == 0.5)
    #expect(VoiceIsolationConfiguration(mix: 1.25).mix == 1)
}

@Test func configurationConvertsMixToWetDryPercent() {
    #expect(VoiceIsolationConfiguration(mix: 0).wetDryMixPercent == 0)
    #expect(VoiceIsolationConfiguration(mix: 0.25).wetDryMixPercent == 25)
    #expect(VoiceIsolationConfiguration(mix: 1).wetDryMixPercent == 100)
}

@Test func voiceSoundTypeUsesStableAudioUnitValue() {
    #expect(VoiceIsolationSoundType.voice.isSupportedOnCurrentOS)
    #expect(VoiceIsolationSoundType.voice.parameterValue == AUValue(kAUSoundIsolationSoundType_Voice))
}

@Test func highQualityVoiceAvailabilityMatchesCurrentOS() {
    if #available(iOS 18, macOS 15, *) {
        #expect(VoiceIsolationSoundType.highQualityVoice.isSupportedOnCurrentOS)
        #expect(VoiceIsolationSoundType.highQualityVoice.parameterValue == AUValue(kAUSoundIsolationSoundType_HighQualityVoice))
    } else {
        #expect(!VoiceIsolationSoundType.highQualityVoice.isSupportedOnCurrentOS)
        #expect(VoiceIsolationSoundType.highQualityVoice.parameterValue == nil)
    }
}

@Test func runtimeSnapshotIsCodableAndIndependentFromMixer() throws {
    let configuration = VoiceIsolationConfiguration(soundType: .voice, mix: 0.75)
    let support = VoiceIsolationSupportSnapshot(isAvailable: true, supportedSoundTypes: [.voice], unsupportedSoundTypes: [.highQualityVoice])
    let snapshot = VoiceIsolationRuntimeSnapshot(configuration: configuration, support: support, state: .active)

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(VoiceIsolationRuntimeSnapshot.self, from: data)

    #expect(decoded == snapshot)
}
