import Foundation

struct Chapter: Identifiable, Hashable {
    let id = UUID()
    var sourceURL: URL
    var title: String
    var duration: TimeInterval
    var sourceBitrate: Int = 0       // bits/sec, 0 = unknown
    var codec: AudioCodec = .unknown("")
    var sampleRate: Double = 0
    var channels: Int = 0

    var displayDuration: String { duration.positional }
}
