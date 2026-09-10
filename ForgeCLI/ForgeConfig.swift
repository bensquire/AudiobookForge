import ForgeCore
import Foundation
import Yams

/// User configuration for the pipeline, loaded from YAML. Only the
/// fields scan needs are *required*; the rest carry defaults so one
/// short config file is enough to start:
///
/// ```yaml
/// # ~/.forge/forge.yml
/// libraryRoots:
///   - /Volumes/data/torrents/completed/Audiobooks
/// outputRoot: /Volumes/data/audiobooks-forged
/// bitrate: 64k        # or "source" (default)
/// gain: auto          # off (default), +3 … +12, or auto
/// ```
///
/// Encode-related values are validated at load time and typed with the
/// same enums the GUI uses, so a typo in `gain:` fails here with a
/// message rather than at the end of a long `run`.
struct ForgeConfig {
    var libraryRoots: [String]
    var outputRoot: String?
    var stateDir: String = "~/.forge"
    var filenameTemplate: String = EncodeSettings().filenameTemplate
    var bitrate: EncodeSettings.Bitrate = .source
    var gain: EncodeSettings.GainBoost = .off
    var concurrency: Int = 4
    var autonomy: Autonomy = .autoWhenConfident

    enum Autonomy: String, Codable {
        case proposeAll = "propose-all"
        case autoWhenConfident = "auto-when-confident"
        case manual
    }

    static func load(from path: String) throws -> Self {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
        {
            throw ConfigError.notFound(url.path)
        } catch {
            throw ConfigError.unreadable(url.path, error.localizedDescription)
        }
        do {
            return try YAMLDecoder().decode(Self.self, from: data)
        } catch let error as ConfigError {
            throw error
        } catch let DecodingError.dataCorrupted(context) {
            // Our own field validators throw through this path; keep
            // just their message rather than the coding-path dump.
            throw ConfigError.invalid(url.path, context.debugDescription)
        } catch {
            throw ConfigError.invalid(url.path, String(describing: error))
        }
    }

    var stateDirURL: URL {
        URL(fileURLWithPath: (stateDir as NSString).expandingTildeInPath)
    }

    var outputRootURL: URL? {
        outputRoot.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    var libraryRootURLs: [URL] {
        libraryRoots.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    /// The `EncodeSettings` a `run` would hand to `EncodeJob` — the one
    /// place config values become encode parameters.
    func encodeSettings() -> EncodeSettings {
        var settings = EncodeSettings()
        settings.bitrate = bitrate
        settings.gainBoost = gain
        settings.filenameTemplate = filenameTemplate
        settings.outputDirectory = outputRootURL
        return settings
    }

    enum ConfigError: Error, CustomStringConvertible {
        case notFound(String)
        case unreadable(String, String)
        case invalid(String, String)

        var description: String {
            switch self {
            case let .notFound(path):
                """
                No config file at \(path).
                Create one, e.g.:

                  libraryRoots:
                    - /path/to/your/audiobook/library
                """
            case let .unreadable(path, why):
                "Couldn't read \(path): \(why)"
            case let .invalid(path, detail):
                "Couldn't parse \(path): \(detail)"
            }
        }
    }
}

/// Decoding lives in an extension so the memberwise initializer — and
/// with it the single set of property defaults above — survives.
extension ForgeConfig: Decodable {
    private enum CodingKeys: String, CodingKey {
        case libraryRoots, outputRoot, stateDir, filenameTemplate,
             bitrate, gain, concurrency, autonomy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var config = try ForgeConfig(libraryRoots: c.decode([String].self, forKey: .libraryRoots))
        config.outputRoot = try c.decodeIfPresent(String.self, forKey: .outputRoot)
        if let v = try c.decodeIfPresent(String.self, forKey: .stateDir) { config.stateDir = v }
        if let v = try c.decodeIfPresent(String.self, forKey: .filenameTemplate) {
            config.filenameTemplate = v
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .bitrate) {
            guard let v = EncodeSettings.Bitrate(userSpelling: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .bitrate, in: c,
                    debugDescription: "bitrate: \"\(raw)\" isn't one of "
                        + EncodeSettings.Bitrate.allCases.map(\.rawValue).joined(separator: ", ")
                )
            }
            config.bitrate = v
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .gain) {
            guard let v = EncodeSettings.GainBoost(userSpelling: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .gain, in: c,
                    debugDescription: "gain: \"\(raw)\" isn't one of off, +3, +6, +9, +12, auto"
                )
            }
            config.gain = v
        }
        if let v = try c.decodeIfPresent(Int.self, forKey: .concurrency) {
            guard v >= 1 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .concurrency, in: c, debugDescription: "concurrency must be at least 1"
                )
            }
            config.concurrency = v
        }
        if let v = try c.decodeIfPresent(Autonomy.self, forKey: .autonomy) { config.autonomy = v }
        self = config
    }
}
