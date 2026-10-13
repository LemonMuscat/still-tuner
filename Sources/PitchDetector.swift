import Foundation

struct PitchResult {
    let frequency: Double
    let confidence: Double
    let level: Double
}

// YIN, on a decimated analysis copy. No signal is ever sent to an output device.
struct PitchDetector {
    static func detect(_ input: [Float], sampleRate: Double) -> PitchResult? {
        guard sampleRate > 0, input.count >= 1024 else { return nil }
        let stride = max(1, Int(sampleRate / 24000))
        let rate = sampleRate / Double(stride)
        let count = input.count / stride
        var x = [Double](repeating: 0, count: count)
        var energy = 0.0
        for i in 0..<count {
            var sum = 0.0
            for j in 0..<stride { sum += Double(input[i * stride + j]) }
            x[i] = sum / Double(stride)
            energy += x[i] * x[i]
        }
        let rms = sqrt(energy / Double(count))
        guard rms > 0.0005 else { return nil }
        let minLag = max(2, Int(rate / 1400))
        let maxLag = min(count / 2 - 1, Int(rate / 45))
        guard maxLag > minLag else { return nil }
        let window = count - maxLag
        var difference = [Double](repeating: 0, count: maxLag + 1)
        var rawDifference = [Double](repeating: 0, count: maxLag + 1)
        var running = 0.0
        for lag in 1...maxLag {
            var sum = 0.0
            for i in 0..<window {
                let d = x[i] - x[i + lag]
                sum += d * d
            }
            rawDifference[lag] = sum
            running += sum
            difference[lag] = running > 0 ? sum * Double(lag) / running : 1
        }
        var candidate: Int?
        var lag = minLag
        while lag < maxLag {
            if difference[lag] < 0.14 {
                while lag + 1 <= maxLag && difference[lag + 1] < difference[lag] { lag += 1 }
                candidate = lag
                break
            }
            lag += 1
        }
        guard let t = candidate, difference[t] < 0.20 else { return nil }
        var refined = Double(t)
        if t > 1 && t < maxLag {
            // Refine the raw difference minimum. Normalization slopes the trough
            // and introduces a small systematic sharp bias in sub-sample timing.
            let a = rawDifference[t - 1], b = rawDifference[t], c = rawDifference[t + 1]
            let denom = a - 2 * b + c
            if abs(denom) > 1e-12 { refined += 0.5 * (a - c) / denom }
        }
        return PitchResult(frequency: rate / refined, confidence: 1 - difference[t], level: rms)
    }
}
