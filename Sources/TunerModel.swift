import AppKit
import AVFoundation
import SwiftUI

final class TunerModel: ObservableObject {
    @Published var devices: [InputDevice] = []
    @Published var deviceUID = UserDefaults.standard.string(forKey: "deviceUID") ?? ""
    @Published var channel = max(1, UserDefaults.standard.integer(forKey: "channel") == 0 ? 4 : UserDefaults.standard.integer(forKey: "channel"))
    @Published var reference = UserDefaults.standard.double(forKey: "reference") == 0 ? 440.0 : UserDefaults.standard.double(forKey: "reference")
    @Published var compact = UserDefaults.standard.bool(forKey: "compact")
    var onLayoutChange: (() -> Void)?
    @Published var alwaysOnTop = UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true
    @Published var frequency: Double?
    @Published var midi: Int?
    @Published var cents = 0.0
    @Published var level = -90.0
    @Published var status = "오디오 입력 준비 중"
    @Published var running = false
    @Published var permissionDenied = false
    @Published var clipping = false
    let demo = CommandLine.arguments.contains("--demo")
    private let audio = AudioInput()
    private let queue = DispatchQueue(label: "kr.still.tuner.analysis", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var deviceTimer: Timer?
    private var activeDevice: InputDevice?
    private var starting = false
    private var generation = 0
    private var missed = 0
    private var lastPitch = 0.0
    private var observers: [NSObjectProtocol] = []

    var note: String {
        guard let midi = midi else { return "—" }
        return ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"][(midi % 12 + 12) % 12]
    }
    var octave: String { midi.map { String($0 / 12 - 1) } ?? "" }
    var tuned: Bool { frequency != nil && abs(cents) <= 2 }
    var selectedDevice: InputDevice? { devices.first { $0.uid == deviceUID } }

    init() {
        if CommandLine.arguments.contains("--mini") { compact = true }
        if CommandLine.arguments.contains("--full") { compact = false }
        if demo {
            devices = [InputDevice(id: 0, uid: "demo", name: "Babyface Pro", channels: 12, rate: 48000)]
            deviceUID = "demo"; channel = 4; midi = 40; frequency = 82.41; cents = 0.3; level = -19; running = true; status = "DEMO · 실제 오디오 입력 없음"
            return
        }
        refreshDevices()
        deviceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshDevices() }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshDevices(); self?.connect() })
        requestPermission()
    }
    func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: connect()
        case .notDetermined:
            status = "마이크 접근을 허용하면 튜닝을 시작합니다"
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.requestPermission() } }
        default:
            permissionDenied = true; status = "시스템 설정에서 마이크 접근을 허용해 주세요"
        }
    }
    func refreshDevices() {
        let newDevices = inputDevices()
        if devices != newDevices { devices = newDevices }
        if deviceUID.isEmpty, let rme = devices.first(where: { $0.name.localizedCaseInsensitiveContains("babyface") || $0.name.localizedCaseInsensitiveContains("RME") }) {
            deviceUID = rme.uid
            channel = min(4, rme.channels)
        }
        if activeDevice != selectedDevice, !starting { connect() }
    }
    func chooseDevice(_ uid: String) {
        deviceUID = uid
        if let device = selectedDevice { channel = min(channel, device.channels) }
        save(); connect()
    }
    func chooseChannel(_ value: Int) { channel = value; save(); connect() }
    func save() {
        guard !demo else { return }
        UserDefaults.standard.set(compact, forKey: "compact")
        UserDefaults.standard.set(deviceUID, forKey: "deviceUID")
        UserDefaults.standard.set(channel, forKey: "channel")
        UserDefaults.standard.set(reference, forKey: "reference")
        UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
    }
    func toggleCompact() {
        compact.toggle(); save(); onLayoutChange?()
    }
    func setReference(_ value: Double) {
        reference = value
        if let frequency = frequency {
            let reading = PitchReading(frequency: frequency, reference: reference)
            midi = reading.midi; cents = reading.cents
            updatePitchStatus()
        }
        save()
    }
    private func updatePitchStatus() {
        status = clipping ? "입력 과다 · 인터페이스 게인을 낮춰 주세요" : (tuned ? "정확합니다" : cents < 0 ? "조금 더 조여 주세요" : "조금 더 풀어 주세요")
    }
    func pinChanged() {
        save()
        NSApp.windows.filter { $0.identifier?.rawValue == "tuner" }.forEach { $0.level = alwaysOnTop ? .floating : .normal }
    }
    func suspend() {
        generation += 1; starting = false; activeDevice = nil; running = false; clearPitch()
        queue.async { self.timer?.cancel(); self.timer = nil; self.audio.stop() }
    }
    func connect() {
        guard !demo else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
        generation += 1
        let token = generation
        starting = true; running = false; clearPitch(); level = -90
        let device = selectedDevice, inputChannel = channel
        activeDevice = device
        status = device == nil ? (deviceUID.isEmpty ? "오디오 입력 장치를 선택해 주세요" : "장치 연결을 기다리는 중 · 자동 재연결") : "입력 연결 중…"
        queue.async {
            self.timer?.cancel(); self.timer = nil; self.audio.stop()
            guard let device = device else {
                DispatchQueue.main.async { if self.generation == token { self.starting = false } }
                return
            }
            do {
                try self.audio.start(device: device, channel: inputChannel)
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + 0.2, repeating: 1.0 / 30, leeway: .milliseconds(3))
                timer.setEventHandler { [weak self] in self?.analyze(token: token) }
                self.timer = timer; timer.resume()
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.starting = false; self.running = true; self.missed = 0; self.status = "준비 완료 · 한 줄씩 연주해 주세요"
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.starting = false; self.activeDevice = nil; self.status = error.localizedDescription
                }
            }
        }
    }
    private func analyze(token: Int) {
        let snapshot = audio.snapshot()
        let pitch = snapshot.age < 0.3 ? PitchDetector.detect(snapshot.samples, sampleRate: audio.sampleRate) : nil
        let peak = snapshot.samples.reduce(Float(0)) { max($0, abs($1)) }
        let rms = sqrt(snapshot.samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, snapshot.samples.count)))
        DispatchQueue.main.async {
            guard self.generation == token else { return }
            self.level = snapshot.age < 0.3 ? 20 * log10(max(0.00003, rms)) : -90
            self.clipping = peak >= 0.99 && snapshot.age < 0.3
            if snapshot.age > 2 {
                self.missed += 1
                if self.missed > 30 { self.missed = 0; self.connect() }
            } else { self.missed = 0 }
            guard let pitch = pitch else {
                if ProcessInfo.processInfo.systemUptime - self.lastPitch > 0.3 { self.clearPitch() }
                self.status = self.clipping ? "입력 과다 · 인터페이스 게인을 낮춰 주세요" : "준비 완료 · 한 줄씩 연주해 주세요"
                return
            }
            self.lastPitch = ProcessInfo.processInfo.systemUptime
            let reading = PitchReading(frequency: pitch.frequency, reference: self.reference)
            // Smooth in log-frequency space; Hz, note, and cents share one reading.
            let displayed: Double
            if self.midi == reading.midi, let previous = self.frequency {
                displayed = exp(log(previous) * 0.45 + log(pitch.frequency) * 0.55)
            } else { displayed = pitch.frequency }
            let stable = PitchReading(frequency: displayed, reference: self.reference)
            self.midi = stable.midi; self.cents = stable.cents; self.frequency = displayed
            self.updatePitchStatus()
        }
    }
    private func clearPitch() { frequency = nil; midi = nil; cents = 0 }
}
