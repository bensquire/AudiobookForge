import AVFoundation
import CoreMedia
import Foundation

/// Probe an audio file for duration, tags, codec, and bitrate.
///
/// AVFoundation gives us everything except an accurate audio-stream
/// bitrate for MP3: its `estimatedDataRate` is the container's byte rate
/// divided across tracks, so an MP3 with chunky ID3v2 cover art reports
/// inflated bitrate. ffmpeg's stderr banner (`Audio: …, 64 kb/s`) reads
/// the codec context's `bit_rate` directly, so we shell out for that
/// number and use AVFoundation for everything else.
public enum AudioProbe {
    public struct Probed {
        public var title: String?
        public var artist: String?
        public var album: String?
        public var trackNumber: Int?
        public var duration: TimeInterval
        public var bitrate: Int = 0 // bits/sec
        public var codec: AudioCodec = .unknown("")
        public var sampleRate: Double = 0
        public var channels: Int = 0
        /// Whether the file carries embedded chapter markers (mp4
        /// chapter atoms, ID3 CHAP frames). A file that already has
        /// chapters is a finished audiobook — importing it as a single
        /// chapter would silently discard them.
        public var hasChapters = false
    }

    public static func probe(_ url: URL) async -> Probed {
        let asset = AVURLAsset(url: url)
        async let durationCM = try? asset.load(.duration)
        async let meta = try? asset.load(.commonMetadata)
        async let id3 = try? asset.loadMetadata(for: .id3Metadata)
        async let ffmpegBitrate = ffmpegStreamBitrate(url)
        async let chapters = hasEmbeddedChapters(url)

        var probed = Probed(duration: 0)
        probed.hasChapters = await chapters

        if let cm = await durationCM {
            probed.duration = CMTimeGetSeconds(cm)
            if probed.duration.isNaN || probed.duration.isInfinite {
                probed.duration = 0
            }
        }

        if let tracks = try? await asset.loadTracks(withMediaType: .audio),
           let audio = tracks.first
        {
            // Prefer ffmpeg — see file header for why. Fall back to
            // AVFoundation's estimate when ffmpeg can't determine it
            // (e.g. bundled binary missing in a dev build).
            if let ff = await ffmpegBitrate {
                probed.bitrate = ff
            } else if let rate = try? await audio.load(.estimatedDataRate),
                      rate.isFinite, rate > 0
            {
                probed.bitrate = Int(rate)
            }
            // Codec / sample rate / channels — needed to decide whether we
            // can remux losslessly instead of re-encoding.
            if let descs = try? await audio.load(.formatDescriptions),
               let desc = descs.first
            {
                probed.codec = AudioCodec(fourCC: CMFormatDescriptionGetMediaSubType(desc))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    probed.sampleRate = asbd.pointee.mSampleRate
                    probed.channels = Int(asbd.pointee.mChannelsPerFrame)
                }
            }
        }

        for item in await (meta) ?? [] {
            guard let key = item.commonKey?.rawValue else { continue }
            switch key {
            case AVMetadataKey.commonKeyTitle.rawValue:
                probed.title = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyArtist.rawValue:
                probed.artist = try? await item.load(.stringValue)
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                probed.album = try? await item.load(.stringValue)
            default:
                break
            }
        }

        for item in await (id3) ?? [] where item.identifier == .id3MetadataTrackNumber {
            if let s = try? await item.load(.stringValue) {
                probed.trackNumber = Int(s.split(separator: "/").first.map(String.init) ?? s)
            }
        }

        return probed
    }

    /// How a file's embedded chapters are stored. `chap` (QuickTime
    /// chapter track) is what Apple players read; `chpl` (Nero atom) is
    /// readable by ffmpeg-lineage players but invisible to AVFoundation.
    /// Our own encoder always writes both; inherited files vary.
    public enum ChapterFormat: String, Codable, Sendable {
        case chap
        case chpl
        case none
    }

    /// Chapters-only probe. AVFoundation first (one metadata read, no
    /// subprocess) — but it only sees QuickTime `chap` track chapters.
    /// Many m4bs in the wild carry Nero-style `chpl` atoms instead
    /// (AVFoundation reports none; ffmpeg reads them fine), so a file
    /// that looks chapterless gets a second opinion from the ffmpeg
    /// banner before we conclude anything.
    public static func chapterFormat(_ url: URL) async -> ChapterFormat {
        let asset = AVURLAsset(url: url)
        if let locales = try? await asset.load(.availableChapterLocales),
           !locales.isEmpty
        {
            return .chap
        }
        // Only mp4-family files can hide chpl chapters worth the spawn;
        // for mp3 etc. the AVFoundation answer stands.
        guard ["m4a", "m4b", "aac", "mp4"].contains(url.pathExtension.lowercased()) else {
            return .none
        }
        guard let stderr = await FFmpegRunner.captureStderr(arguments: ["-i", url.path]) else {
            return .none
        }
        return parseChapterCount(fromBanner: stderr) > 0 ? .chpl : .none
    }

    public static func hasEmbeddedChapters(_ url: URL) async -> Bool {
        await chapterFormat(url) != .none
    }

    /// Count `Chapter #N:M:` entries in an ffmpeg input banner. Internal
    /// so tests can pin it against captured output.
    static func parseChapterCount(fromBanner stderr: String) -> Int {
        stderr.split(separator: "\n").count { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("Chapter #")
        }
    }

    /// The audio stream's codec-context bitrate, read from ffmpeg's
    /// startup banner (stderr). `-t 1` caps the demux to one second of
    /// stream — the banner is printed at startup so we get the same
    /// number as a full read for ~14× less wall time (~20 ms vs ~280 ms
    /// on a 90-min MP3).
    private static func ffmpegStreamBitrate(_ url: URL) async -> Int? {
        let stderr = await FFmpegRunner.captureStderr(arguments: [
            "-i", url.path,
            "-t", "1",
            "-c", "copy",
            "-f", "null", "-"
        ])
        return stderr.flatMap(parseBitrateFromFFmpegBanner)
    }

    private static let kbpsPattern = /(\d+)\s*kb\/s/

    /// Parse `Audio: …, N kb/s` from ffmpeg's stderr banner. Exposed
    /// (internal scope) so AudioProbeBitrateParseTests can pin the
    /// parser against captured outputs from the pinned ffmpeg version.
    static func parseBitrateFromFFmpegBanner(_ stderr: String) -> Int? {
        for line in stderr.split(separator: "\n", omittingEmptySubsequences: false)
            where line.contains("Audio:")
        {
            // Walk every "<int> kb/s" match and keep the last — for AAC
            // ffmpeg sometimes prints both stream and container bitrate
            // on the same line and the stream value comes second.
            var lastMatch: Int?
            for match in line.matches(of: kbpsPattern) {
                lastMatch = Int(match.output.1) ?? lastMatch
            }
            if let kbps = lastMatch {
                return kbps * 1000
            }
        }
        return nil
    }
}
