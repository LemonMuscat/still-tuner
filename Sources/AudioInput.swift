import Foundation
import CoreAudio
import AudioToolbox

struct InputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let channels: Int
    let rate: Double
}

func audioProperty<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) -> T {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    _ = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0) }
    return value
}

func inputDevices() -> [InputDevice] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        var config = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var bytes: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &config, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(bytes), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &config, 0, nil, &bytes, raw) == noErr else { return nil }
        let count = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
        guard count > 0 else { return nil }
        let name: CFString = audioProperty(id, kAudioObjectPropertyName, initial: "Audio input" as CFString)
        let uid: CFString = audioProperty(id, kAudioDevicePropertyDeviceUID, initial: "" as CFString)
        let rate: Double = audioProperty(id, kAudioDevicePropertyNominalSampleRate, initial: 48000.0)
        return InputDevice(id: id, uid: uid as String, name: name as String, channels: count, rate: rate)
    }
}

final class AudioInput {
    private var unit: AudioUnit?
    private var storage: UnsafeMutablePointer<Float>?
    private var list = AudioBufferList()
    private let capacity = 8192
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: 32768)
    private var writeIndex = 0
    private var available = 0
    private var lastInput = 0.0
    private var selectedChannel = 0
    private var channelCount = 0
    private(set) var sampleRate = 48000.0

    func start(device: InputDevice, channel: Int) throws {
        stop()
        selectedChannel = channel - 1
        channelCount = device.channels
        guard selectedChannel >= 0 && selectedChannel < channelCount else { throw failure("입력 채널을 확인해 주세요.", -1) }
        sampleRate = device.rate
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else { throw failure("Core Audio를 찾을 수 없습니다.", -1) }
        var instance: AudioUnit?
        try check(AudioComponentInstanceNew(component, &instance))
        unit = instance
        guard let unit = unit else { throw failure("오디오 입력 생성 실패", -1) }
        do {
            var enabled: UInt32 = 1, disabled: UInt32 = 0
            try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, 4))
            try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, 4))
            var id = device.id
            try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout.size(ofValue: id))))
            var format = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: UInt32(4 * channelCount), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * channelCount), mChannelsPerFrame: UInt32(channelCount), mBitsPerChannel: 32, mReserved: 0)
            try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, UInt32(MemoryLayout.size(ofValue: format))))
            var maxFrames = UInt32(capacity)
            try check(AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, 4))
            storage = .allocate(capacity: capacity * channelCount)
            list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: UInt32(channelCount), mDataByteSize: UInt32(capacity * channelCount * 4), mData: storage))
            var callback = AURenderCallbackStruct(inputProc: { context, flags, stamp, _, frames, _ in
                let input = Unmanaged<AudioInput>.fromOpaque(context).takeUnretainedValue()
                return input.render(flags: flags, stamp: stamp, frames: frames)
            }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout.size(ofValue: callback))))
            try check(AudioUnitInitialize(unit))
            try check(AudioOutputUnitStart(unit))
        } catch { stop(); throw error }
    }

    private func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, stamp: UnsafePointer<AudioTimeStamp>, frames: UInt32) -> OSStatus {
        guard let unit = unit, let data = storage, frames <= capacity else { return noErr }
        list.mBuffers.mDataByteSize = frames * UInt32(channelCount * 4)
        let status = AudioUnitRender(unit, flags, stamp, 1, frames, &list)
        guard status == noErr, lock.try() else { return status }
        for i in 0..<Int(frames) {
            ring[writeIndex] = data[i * channelCount + selectedChannel]
            writeIndex = (writeIndex + 1) % ring.count
        }
        available = min(ring.count, available + Int(frames))
        lastInput = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        return noErr
    }

    func snapshot() -> (samples: [Float], age: Double) {
        let desired = max(2048, Int(sampleRate * 0.085))
        var samples = [Float](repeating: 0, count: desired)
        lock.lock()
        defer { lock.unlock() }
        let count = min(available, desired)
        if count < desired { return ([], ProcessInfo.processInfo.systemUptime - lastInput) }
        for i in 0..<count { samples[i] = ring[(writeIndex - count + i + ring.count) % ring.count] }
        return (samples, ProcessInfo.processInfo.systemUptime - lastInput)
    }

    func stop() {
        if let unit = unit { AudioOutputUnitStop(unit); AudioUnitUninitialize(unit); AudioComponentInstanceDispose(unit) }
        unit = nil
        storage?.deallocate(); storage = nil
        lock.lock(); available = 0; lastInput = 0; lock.unlock()
    }
    deinit { stop() }
    private func check(_ status: OSStatus) throws { if status != noErr { throw failure("오디오 입력을 열 수 없습니다", status) } }
    private func failure(_ message: String, _ code: OSStatus) -> NSError { NSError(domain: "StillTuner", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "\(message) (\(code))"]) }
}
