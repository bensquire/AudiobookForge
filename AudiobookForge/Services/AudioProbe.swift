import Foundation
import AVFoundation
import CoreMedia

/// Probe an audio file for duration, tags, codec, and bitrate.
///
/// We split sources of truth:
/// - AVFoundation: fast, async, gives us duration, tags, codec, sample
///   rate, channels — all needed at drag-drop time without a subprocess.
/// - ffprobe (bundled): more accurate audio-stream bitrate. AVFoundation
///   reports `estimatedDataRate` which is the container's byte rate
///   divided across tracks. For MP3 files with chunky embedded cover art
///   (common in audiobooks) that overstates the actual audio bitrate by
///   the cover-art payload. ffprobe reads the codec context's `bit_rate`
///   directly, so a 64 kbps audiobook reports 64k instead of 80k.
enum AudioProbe {
    struct Probed {
        var title: String?
        var artist: String?
        var album: String?
        var trackNumber: Int?
        var duration: TimeInterval
        var bitrate: Int = 0     // bits/sec
        var codec: AudioCodec = .unknown("")
        var sampleRate: Double = 0
        var channels: Int = 0
    }

    static func probe(_ url: URL) async -> Probed {
        let asset = AVURLAsset(url: url)
        async let durationCM = try? asset.load(.duration)
        async let meta = try? asset.load(.commonMetadata)
        async let id3 = try? asset.loadMetadata(for: .id3Metadata)
        async let ffprobeBR = ffprobeBitrate(url)

        var probed = Probed(duration: 0)

        if let cm = await durationCM {
            probed.duration = CMTimeGetSeconds(cm)
            if probed.duration.isNaN || probed.duration.isInfinite {
                probed.duration = 0
            }
        }

        if let tracks = try? await asset.loadTracks(withMediaType: .audio),
           let audio = tracks.first {
            // Prefer ffprobe — see file header for why. Fall back to
            // AVFoundation's estimate when ffprobe can't determine it
            // (e.g. bundled binary missing in a dev build).
            if let ff = await ffprobeBR {
                probed.bitrate = ff
            } else if let rate = try? await audio.load(.estimatedDataRate),
                      rate.isFinite, rate > 0 {
                probed.bitrate = Int(rate)
            }
            // Codec / sample rate / channels — needed to decide whether we
            // can remux losslessly instead of re-encoding.
            if let descs = try? await audio.load(.formatDescriptions),
               let desc = descs.first {
                probed.codec = AudioCodec(fourCC: CMFormatDescriptionGetMediaSubType(desc))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                    probed.sampleRate = asbd.pointee.mSampleRate
                    probed.channels = Int(asbd.pointee.mChannelsPerFrame)
                }
            }
        }

        for item in (await meta) ?? [] {
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

        for item in (await id3) ?? [] where item.identifier == .id3MetadataTrackNumber {
            if let s = try? await item.load(.stringValue) {
                probed.trackNumber = Int(s.split(separator: "/").first.map(String.init) ?? s)
            }
        }

        return probed
    }

    /// Audio-stream bitrate as reported by ffprobe (bits/sec). Returns nil
    /// if the binary is missing, the file is unreadable, or the codec
    /// context has no bit_rate field (some lossless containers).
    private static func ffprobeBitrate(_ url: URL) async -> Int? {
        guard let ffprobe = Bundled.binary("ffprobe") else { return nil }

        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error",
            "-select_streams", "a:0",
            "-show_entries", "stream=bit_rate",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { (cont: CheckedContinuation<Int?, Never>) in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // ffprobe prints "N/A" for streams without a stored bit_rate
                // (e.g. raw PCM in WAV); treat that as "no answer".
                cont.resume(returning: text == "N/A" ? nil : Int(text))
            }
            do {
                try process.run()
            } catch {
                cont.resume(returning: nil)
            }
        }
    }
}
