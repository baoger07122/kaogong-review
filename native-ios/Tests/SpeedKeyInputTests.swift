import Foundation

@main
struct SpeedKeyInputTests {
    static func main() {
        let cases: [(String, String, String)] = [
            ("C", "123", "12"), ("C", "", ""), ("⌫", "123", ""), ("⌫", "", ""),
            (".", "", "."), (".", "1.2", "1.2"), (".", "1", "1."),
            ("+/-", "", ""), ("+/-", "12", "-12"), ("+/-", "-12", "12"),
            ("3", "12", "123"), ("0", "123456789", "1234567890"),
            ("1", "1234567890", "1234567890"), ("?", "12", "12")
        ]
        for (key, before, expected) in cases {
            precondition(SpeedKeyInput.applying(key, to: before) == expected, "Input mismatch: \(key), \(before)")
        }
        let samples = SpeedKeyTone.samples()
        precondition(samples.count == 3087 && samples.first == 0)
        precondition(samples.contains(32767) && samples.contains(where: { $0 < 0 }))
        precondition(abs(Int(samples.last!)) < 10)
        let wav = SpeedKeyTone.wavData()
        precondition(wav.count == 44 + samples.count * 2)
        precondition(String(data: wav.prefix(4), encoding: .utf8) == "RIFF")
        precondition(String(data: wav[8..<12], encoding: .utf8) == "WAVE")
        print("PASS \(cases.count) keypad input cases and 70ms/55Hz bounded PCM WAV checks")
    }
}
