import Foundation

public struct EncodeSettings: Equatable, Sendable {
    public enum Bitrate: String, CaseIterable, Identifiable, Codable, Sendable {
        case k32 = "32k"
        case k64 = "64k"
        case k96 = "96k"
        case k128 = "128k"
        case k192 = "192k"
        case source
        public var id: String {
            rawValue
        }

        public var label: String {
            self == .source ? "Match source" : rawValue
        }

        /// Numeric kbps for the fixed cases; nil for `.source`, whose
        /// value is resolved from the chapters at encode time.
        public var kbps: Int? {
            switch self {
            case .k32: 32
            case .k64: 64
            case .k96: 96
            case .k128: 128
            case .k192: 192
            case .source: nil
            }
        }

        /// Decodes either the raw value or any `userSpelling`; anything
        /// else is a decoding error naming the accepted values, so a
        /// config typo fails at load rather than at encode time.
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let value = Self(rawValue: raw) ?? Self(userSpelling: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "\"\(raw)\" isn't one of \(Self.acceptedSpellings)"
                )
            }
            self = value
        }

        public static let acceptedSpellings = allCases.map(\.rawValue).joined(separator: ", ")

        /// Parse a human spelling from config files / CLI flags:
        /// `source`, `match`, `64k`, `64`, `64kbps`, `64 kbps`. Case-
        /// and whitespace-insensitive. Nil for anything else — callers
        /// should reject the config rather than fall back silently.
        public init?(userSpelling raw: String) {
            let s = raw.lowercased().filter { !$0.isWhitespace }
            if s == "source" || s == "match" || s == "matchsource" {
                self = .source
                return
            }
            let digits = s.prefix { $0.isNumber }
            let unit = s.dropFirst(digits.count)
            guard !digits.isEmpty, ["", "k", "kb", "kbps", "kbit", "kbit/s"].contains(unit),
                  let match = Self.allCases.first(where: { $0.kbps.map { String($0) } == String(digits) })
            else { return nil }
            self = match
        }
    }

    /// Optional per-book loudness adjustment applied during encoding.
    /// Manual cases inject a fixed `volume=NdB` filter. The auto modes
    /// measure the whole book's integrated loudness up front then apply
    /// a single computed gain to all chapters: `.autoNormalize` moves
    /// the book to the target in either direction, `.autoIfQuiet` only
    /// ever lifts (a book already at or above target is left untouched).
    /// Either way the remux fast-path is disabled because we have to
    /// re-encode to touch samples.
    public enum GainBoost: String, CaseIterable, Identifiable, Equatable, Codable, Sendable {
        case off
        case dB3
        case dB6
        case dB9
        case dB12
        case autoNormalize
        case autoIfQuiet

        public var id: String {
            rawValue
        }

        public var label: String {
            switch self {
            case .off: "Off"
            case .dB3: "+3 dB"
            case .dB6: "+6 dB"
            case .dB9: "+9 dB"
            case .dB12: "+12 dB"
            case .autoNormalize: "Auto-normalize"
            case .autoIfQuiet: "Auto (lift if quiet)"
            }
        }

        /// The canonical spelling for config files (`gain: +6`).
        public var configSpelling: String {
            switch self {
            case .off: "off"
            case .autoNormalize: "auto"
            case .autoIfQuiet: "auto-if-quiet"
            default: "+\(manualDB ?? 0)"
            }
        }

        public static let acceptedSpellings = allCases.map(\.configSpelling).joined(separator: ", ")

        /// Decodes either the raw value or any `userSpelling`; anything
        /// else is a decoding error naming the accepted values.
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let value = Self(rawValue: raw) ?? Self(userSpelling: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "\"\(raw)\" isn't one of \(Self.acceptedSpellings)"
                )
            }
            self = value
        }

        /// dB value for the manual cases, or nil for `.off` and
        /// `.autoNormalize` (whose value is computed at encode time).
        public var manualDB: Int? {
            switch self {
            case .dB3: 3
            case .dB6: 6
            case .dB9: 9
            case .dB12: 12
            default: nil
            }
        }

        public var isManual: Bool {
            manualDB != nil
        }

        /// Compact display suffix for the format summary line ("+6 dB",
        /// "auto-normalised", or empty for `.off`).
        public var suffix: String {
            switch self {
            case .off: ""
            case .autoNormalize: "auto-normalised"
            case .autoIfQuiet: "lifted if quiet"
            default: label
            }
        }

        /// Parse a human spelling from config files / CLI flags: `off`,
        /// `none`, `auto`, `auto-normalize`, `normalize`, `auto-if-quiet`,
        /// `lift-if-quiet`, `6`, `+6`, `6dB`, `+6 dB`. Only the fixed steps
        /// the app offers are accepted — `+5` is nil, not rounded. Case-,
        /// sign-, and whitespace-insensitive.
        public init?(userSpelling raw: String) {
            let s = raw.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
            switch s {
            case "off", "none", "0", "0db":
                self = .off
                return
            case "auto", "autonormalize", "autonormalise", "normalize", "normalise":
                self = .autoNormalize
                return
            case "autoifquiet", "ifquiet", "liftifquiet", "liftquiet", "autolift":
                self = .autoIfQuiet
                return
            default:
                break
            }
            let trimmed = s.hasPrefix("+") ? String(s.dropFirst()) : s
            let digits = trimmed.prefix { $0.isNumber }
            let unit = trimmed.dropFirst(digits.count)
            guard !digits.isEmpty, unit == "" || unit == "db",
                  let match = Self.allCases.first(where: { $0.manualDB.map { String($0) } == String(digits) })
            else { return nil }
            self = match
        }
    }

    public var bitrate: Bitrate = .source
    public var gainBoost: GainBoost = .off
    public var outputDirectory: URL?
    public var filenameTemplate: String = "{author}/{title}/{title}.m4b"

    public init() {}
}
