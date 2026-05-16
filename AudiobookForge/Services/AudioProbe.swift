import Foundation
import AVFoundation
import CoreMedia

/// Read duration and basic ID3 tags from an audio file using AVFoundation —
/// no ffprobe shell-out needed for this step, which keeps drag-drop snappy.
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

        var probed = Probed(duration: 0)

        if let cm = await durationCM {
            probed.duration = CMTimeGetSeconds(cm)
            if probed.duration.isNaN || probed.duration.isInfinite {
                probed.duration = 0
            }
        }

        if let tracks = try? await asset.loadTracks(withMediaType: .audio),
           let audio = tracks.first {
            if let rate = try? await audio.load(.estimatedDataRate),
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
}
