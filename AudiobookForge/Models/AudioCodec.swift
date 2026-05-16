import CoreMedia
import Foundation

/// Audio codec identified at probe time. CoreMedia gives us a FourCC like
/// `'aac '` (with trailing space) — comparing against the raw string is
/// fragile; an enum gives us safety and a place to hang
/// codec-specific decisions (e.g. "is this MP4-compatible for remux").
enum AudioCodec: Hashable {
    case aac
    case alac
    case mp3
    case opus
    case flac
    case vorbis
    case pcm
    case unknown(String)

    init(fourCC: FourCharCode) {
        let bytes: [UInt8] = [
            UInt8((fourCC >> 24) & 0xFF),
            UInt8((fourCC >> 16) & 0xFF),
            UInt8((fourCC >> 8) & 0xFF),
            UInt8(fourCC & 0xFF)
        ]
        let raw = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""
        switch raw {
        case "aac": self = .aac
        case "alac": self = .alac
        case "mp3", ".mp3": self = .mp3
        case "opus": self = .opus
        case "flac": self = .flac
        case "vorbis": self = .vorbis
        case "lpcm": self = .pcm
        default: self = .unknown(raw)
        }
    }

    /// True for codecs that can be muxed into MP4 without re-encoding for
    /// audiobook playback. AAC is the only universally-supported one — MP3
    /// is legal in MP4 but stumbles in some readers, so we keep it on the
    /// re-encode path.
    var isMP4RemuxFriendly: Bool {
        self == .aac
    }
}
