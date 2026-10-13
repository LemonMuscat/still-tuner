import Foundation

struct PitchReading {
    let midi: Int
    let cents: Double

    init(frequency: Double, reference: Double) {
        let fractional = 69 + 12 * log2(frequency / reference)
        midi = Int(fractional.rounded())
        cents = (fractional - Double(midi)) * 100
    }
}
