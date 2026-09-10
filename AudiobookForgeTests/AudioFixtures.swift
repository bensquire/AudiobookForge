import Foundation

/// Write a 16-bit mono PCM sine-wave WAV. Shared by the integration
/// tests: PCM sources force EncodeJob down the re-encode path, and a
/// tone is cheap to synthesise at any length (a 4-minute fixture is a
/// few hundred milliseconds of work).
func writeSineWav(
    to url: URL, seconds: Double, frequency: Double, sampleRate: Int = 44100,
    amplitude: Double = 12000
) throws {
    let frames = Int(Double(sampleRate) * seconds)
    var samples = Data(capacity: frames * 2)
    for i in 0 ..< frames {
        let value = Int16(amplitude * sin(2 * .pi * frequency * Double(i) / Double(sampleRate)))
        withUnsafeBytes(of: value.littleEndian) { samples.append(contentsOf: $0) }
    }
    var header = Data()
    func append(_ s: String) {
        header.append(contentsOf: s.utf8)
    }
    func append32(_ v: UInt32) {
        withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) }
    }
    func append16(_ v: UInt16) {
        withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) }
    }
    append("RIFF"); append32(UInt32(36 + samples.count)); append("WAVE")
    append("fmt "); append32(16); append16(1); append16(1)
    append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2))
    append16(2); append16(16)
    append("data"); append32(UInt32(samples.count))
    try (header + samples).write(to: url)
}

/// The repo's `AudiobookForge/Resources/bin`, where `scripts/build-ffmpeg.sh`
/// drops the bundled ffmpeg. Tests run outside the app bundle, so anything
/// that spawns ffmpeg points `Bundled` here first.
let repoBinDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // AudiobookForgeTests/
    .deletingLastPathComponent() // repo root
    .appendingPathComponent("AudiobookForge/Resources/bin")
