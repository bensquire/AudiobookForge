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
/// gain: auto-if-quiet # off (default), +3 … +12, auto, or auto-if-quiet
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
        let url = Self.expanded(path)
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
        } catch let DecodingError.dataCorrupted(context) {
            // Field validation (ours and the enums') throws through this
            // path; "gain: …" reads better than the coding-path dump.
            let key = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw ConfigError.invalid(
                url.path, key.isEmpty ? context.debugDescription : "\(key): \(context.debugDescription)"
            )
        } catch {
            throw ConfigError.invalid(url.path, String(describing: error))
        }
    }

    var stateDirURL: URL {
        Self.expanded(stateDir)
    }

    var libraryRootURLs: [URL] {
        libraryRoots.map(Self.expanded)
    }

    private static func expanded(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
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
        // Absent keys keep the property defaults; the enums validate their
        // own spellings (see EncodeSettings) and throw with the accepted list.
        var config = try ForgeConfig(libraryRoots: c.decode([String].self, forKey: .libraryRoots))
        config.outputRoot = try c.decodeIfPresent(String.self, forKey: .outputRoot)
        config.stateDir = try c.decodeIfPresent(String.self, forKey: .stateDir) ?? config.stateDir
        config.filenameTemplate = try c.decodeIfPresent(String.self, forKey: .filenameTemplate)
            ?? config.filenameTemplate
        config.bitrate = try c.decodeIfPresent(EncodeSettings.Bitrate.self, forKey: .bitrate) ?? config
            .bitrate
        config.gain = try c.decodeIfPresent(EncodeSettings.GainBoost.self, forKey: .gain) ?? config.gain
        config.concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency) ?? config.concurrency
        guard config.concurrency >= 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .concurrency, in: c, debugDescription: "must be at least 1"
            )
        }
        config.autonomy = try c.decodeIfPresent(Autonomy.self, forKey: .autonomy) ?? config.autonomy
        self = config
    }
}
