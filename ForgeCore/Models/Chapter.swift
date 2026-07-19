import Foundation

public struct Chapter: Identifiable, Hashable {
    public let id = UUID()
    public var sourceURL: URL
    public var title: String
    public var duration: TimeInterval
    public var sourceBitrate: Int = 0 // bits/sec, 0 = unknown
    public var codec: AudioCodec = .unknown("")
    public var sampleRate: Double = 0
    public var channels: Int = 0

    public init(
        sourceURL: URL,
        title: String,
        duration: TimeInterval,
        sourceBitrate: Int = 0,
        codec: AudioCodec = .unknown(""),
        sampleRate: Double = 0,
        channels: Int = 0
    ) {
        self.sourceURL = sourceURL
        self.title = title
        self.duration = duration
        self.sourceBitrate = sourceBitrate
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var displayDuration: String {
        duration.positional
    }
}
