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
enum AudioProbe {
    struct Probed {
        var title: String?
        var artist: String?
        var album: String?
        var trackNumber: Int?
        var duration: TimeInterval
        var bitrate: Int = 0 // bits/sec
        var codec: AudioCodec = .unknown("")
        var sampleRate: Double = 0
        var channels: Int = 0
    }

    static func probe(_ url: URL) async -> Probed {
        let asset = AVURLAsset(url: url)
        async let durationCM = try? asset.load(.duration)
        async let meta = try? asset.load(.commonMetadata)
        async let id3 = try? asset.loadMetadata(for: .id3Metadata)
        async let ffmpegBR = ffmpegStreamBitrate(url)

        var probed = Probed(duration: 0)

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
            if let ff = await ffmpegBR {
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

    /// Audio-stream bitrate (bits/sec) as reported by ffmpeg's banner.
    /// `-t 1` caps the demux to one second of stream — the banner is
    /// printed at startup so we get the same numbers as a full read
    /// for ~14× less wall time (~20 ms vs ~280 ms on a 90-min MP3).
    private static func ffmpegStreamBitrate(_ url: URL) async -> Int? {
        guard let stderr = await FFmpegRunner.captureStderr(arguments: [
            "-i", url.path,
            "-t", "1",
            "-c", "copy",
            "-f", "null", "-"
        ]) else { return nil }
        return parseBitrateFromFFmpegBanner(stderr)
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
