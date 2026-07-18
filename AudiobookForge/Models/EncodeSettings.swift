import Foundation

struct EncodeSettings: Equatable {
    enum Bitrate: String, CaseIterable, Identifiable {
        case k32 = "32k"
        case k64 = "64k"
        case k96 = "96k"
        case k128 = "128k"
        case k192 = "192k"
        case source
        var id: String {
            rawValue
        }

        var label: String {
            self == .source ? "Match source" : rawValue
        }

        /// Numeric kbps for the fixed cases; nil for `.source`, whose
        /// value is resolved from the chapters at encode time.
        var kbps: Int? {
            switch self {
            case .k32: 32
            case .k64: 64
            case .k96: 96
            case .k128: 128
            case .k192: 192
            case .source: nil
            }
        }
    }

    /// Optional per-book loudness adjustment applied during encoding.
    /// Manual cases inject a fixed `volume=NdB` filter; `.autoNormalize`
    /// measures the whole book's integrated loudness up front then
    /// applies a single computed gain to all chapters. Either way the
    /// remux fast-path is disabled because we have to re-encode to
    /// touch samples.
    enum GainBoost: String, CaseIterable, Identifiable, Equatable {
        case off
        case dB3
        case dB6
        case dB9
        case dB12
        case autoNormalize

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .off: "Off"
            case .dB3: "+3 dB"
            case .dB6: "+6 dB"
            case .dB9: "+9 dB"
            case .dB12: "+12 dB"
            case .autoNormalize: "Auto-normalize"
            }
        }

        /// dB value for the manual cases, or nil for `.off` and
        /// `.autoNormalize` (whose value is computed at encode time).
        var manualDB: Int? {
            switch self {
            case .dB3: 3
            case .dB6: 6
            case .dB9: 9
            case .dB12: 12
            default: nil
            }
        }

        var isManual: Bool {
            manualDB != nil
        }

        /// Compact display suffix for the format summary line ("+6 dB",
        /// "auto-normalised", or empty for `.off`).
        var suffix: String {
            switch self {
            case .off: ""
            case .autoNormalize: "auto-normalised"
            default: label
            }
        }
    }

    var bitrate: Bitrate = .source
    var gainBoost: GainBoost = .off
    var outputDirectory: URL?
    var filenameTemplate: String = "{author}/{title}/{title}.m4b"
}
