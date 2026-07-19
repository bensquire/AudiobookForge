import CoreMedia
import Foundation

/// Audio codec identified at probe time. CoreMedia gives us a FourCC like
/// `'aac '` (with trailing space) — comparing against the raw string is
/// fragile; an enum gives us safety and a place to hang
/// codec-specific decisions (e.g. "is this MP4-compatible for remux").
public enum AudioCodec: Hashable {
    case aac
    case aacHE
    case aacHEv2
    case alac
    case mp3
    case opus
    case flac
    case vorbis
    case pcm
    case unknown(String)

    public init(fourCC: FourCharCode) {
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
        // CoreMedia reports AAC profiles as distinct FourCCs:
        // kAudioFormatMPEG4AAC_HE = 'aach', …HE_V2 = 'aacp'. Keeping them
        // as separate cases means canRemux's codec-equality check can
        // never mix LC and HE bitstreams in one `-c:a copy` concat.
        case "aach": self = .aacHE
        case "aacp": self = .aacHEv2
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
    /// audiobook playback. AAC (any profile) is the only universally-
    /// supported family — MP3 is legal in MP4 but stumbles in some
    /// readers, so we keep it on the re-encode path. Mixing profiles is
    /// prevented by canRemux's codec-equality check, not here.
    public var isMP4RemuxFriendly: Bool {
        self == .aac || self == .aacHE || self == .aacHEv2
    }
}
