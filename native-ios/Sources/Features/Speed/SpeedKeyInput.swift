import Foundation

/// Matches the preserved web keypad, including its intentionally unusual C / delete mapping.
enum SpeedKeyInput {
    static func applying(_ key: String, to input: String) -> String {
        switch key {
        case "C": return String(input.dropLast())
        case "⌫": return ""
        case "+/-":
            guard !input.isEmpty else { return input }
            return input.hasPrefix("-") ? String(input.dropFirst()) : "-" + input
        case ".": return input.contains(".") ? input : input + "."
        default:
            guard key.count == 1, "0123456789".contains(key), input.count < 10 else { return input }
            return input + key
        }
    }
}

/// WebAudio reference: sine, 55 Hz, gain 14 -> 0.0001 exponentially over 70 ms.
/// Gain 14 is NOT a volume percentage. Limit the final PCM output to the valid range.
enum SpeedKeyTone {
    static let sampleRate = 44_100
    static let duration = 0.07
    static func samples() -> [Int16] {
        (0..<Int(Double(sampleRate) * duration)).map { index in
            let t = Double(index) / Double(sampleRate)
            let gain = 14 * pow(0.0001 / 14, t / duration)
            let value = sin(2 * .pi * 55 * t) * gain
            return Int16((min(1, max(-1, value)) * 32767).rounded())
        }
    }

    static func wavData() -> Data {
        let pcm = samples()
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        word(UInt32(36 + pcm.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(sampleRate)); word(UInt32(sampleRate * 2))
        word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8)
        word(UInt32(pcm.count * 2))
        for sample in pcm { word(sample) }
        return data
    }
}
