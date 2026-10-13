import Foundation
var failures = 0
var elapsed = 0.0
var cases = 0
func check(_ condition: Bool, _ message: String) { if !condition { print("FAIL: \(message)"); failures += 1 } }
for rate in [44100.0, 48000, 96000, 192000] {
    for frequency in [55.0, 73.416, 82.4069, 110, 146.832, 195.998, 246.942, 329.628, 440, 659.255, 1108.73] {
        for harmonic in [false, true] {
            let samples = (0..<Int(rate * 0.085)).map { i -> Float in
                let phase = 2 * Double.pi * frequency * Double(i) / rate
                return Float(harmonic ? 0.16 * sin(phase) + 0.30 * sin(phase * 2) + 0.13 * sin(phase * 3) : 0.5 * sin(phase))
            }
            let start = Date()
            let result = PitchDetector.detect(samples, sampleRate: rate)
            elapsed += Date().timeIntervalSince(start); cases += 1
            if let result = result {
                let error = abs(1200 * log2(result.frequency / frequency))
                check(error < 2.0, "\(rate) Hz / \(frequency) Hz harmonic=\(harmonic), error=\(error) cents")
            } else { check(false, "No pitch at \(frequency) Hz, sample rate \(rate)") }
        }
    }
}
check(PitchDetector.detect([Float](repeating: 0, count: 4096), sampleRate: 48000) == nil, "silence")
check(PitchDetector.detect([Float](repeating: 0.3, count: 4096), sampleRate: 48000) == nil, "DC input")
var seed: UInt64 = 42
let noise: [Float] = (0..<4096).map { _ in seed = seed &* 6364136223846793005 &+ 1; return Float(Double(seed >> 32) / Double(UInt32.max) - 0.5) }
check(PitchDetector.detect(noise, sampleRate: 48000) == nil, "broadband noise")
// Sweep all chromatic notes across the guitar range, detuning and phase included.
var worst = 0.0, signedTotal = 0.0, sweepCount = 0
for rate in [44100.0, 48000, 96000, 192000] {
    for midi in 33...84 {
        for detune in [-35.0, 0, 19.0] {
            let frequency = 441 * pow(2, (Double(midi) - 69 + detune / 100) / 12)
            let samples = (0..<Int(rate * 0.085)).map { i -> Float in
                let t = Double(i) / rate
                let phase = 2 * Double.pi * frequency * t + 0.73
                return Float(0.4 * sin(phase) + 0.25 * sin(2 * phase + 0.3) + 0.1 * sin(3 * phase))
            }
            if let pitch = PitchDetector.detect(samples, sampleRate: rate) {
                let error = 1200 * log2(pitch.frequency / frequency)
                worst = max(worst, abs(error)); signedTotal += error; sweepCount += 1
                check(abs(error) < 0.4, "Sweep MIDI \(midi), \(rate), error \(error)")
                let reading = PitchReading(frequency: pitch.frequency, reference: 441)
                check(reading.midi == midi && abs(reading.cents - detune) < 0.4, "A441 note/cents conversion")
            } else { check(false, "Sweep missed MIDI \(midi)") }
        }
    }
}
var decayingCount = 0
for frequency in [73.416, 82.4069, 110, 139.28, 146.832, 195.998, 246.942, 329.628] {
    for phaseOffset in [0.0, 0.7, 2.1] {
        let samples = (0..<4080).map { i -> Float in
            let t = Double(i) / 48000
            let phase = 2 * Double.pi * frequency * t + phaseOffset
            return Float(exp(-4 * t) * (0.3 * sin(phase) + 0.18 * sin(2 * phase) + 0.08 * sin(3 * phase)))
        }
        if let pitch = PitchDetector.detect(samples, sampleRate: 48000) {
            let error = 1200 * log2(pitch.frequency / frequency)
            check(abs(error) < 0.5, "Decaying guitar signal \(frequency) Hz, error \(error)")
        } else { check(false, "Decaying guitar signal undetected") }
        decayingCount += 1
    }
}
let a440 = PitchReading(frequency: 139.28, reference: 440)
let a441 = PitchReading(frequency: 139.28, reference: 441)
check(abs((a440.cents - a441.cents) - 1200 * log2(441.0 / 440)) < 1e-9, "440/441 reference offset")
check(a440.midi == 49 && a441.midi == 49, "C#3 and Db3 are the same equal-tempered note")
print("Reference check 139.28 Hz: A440 \(a440.cents), A441 \(a441.cents) cents")
print("Sweep: \(sweepCount) signals; max abs error \(String(format: "%.4f", worst)) cents; signed mean \(String(format: "%.4f", signedTotal / Double(sweepCount))) cents")
print("\(cases + 3) baseline checks + \(sweepCount) sweep signals + \(decayingCount) decaying signals + reference checks; \(failures) failures; mean analysis \(String(format: "%.2f", elapsed / Double(cases) * 1000)) ms")
exit(failures == 0 ? 0 : 1)
