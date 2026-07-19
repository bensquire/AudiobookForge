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
/// ```
struct ForgeConfig: Codable {
    var libraryRoots: [String]
    var outputRoot: String?
    var stateDir: String = "~/.forge"
    var filenameTemplate: String = "{author}/{title}/{title}.m4b"
    var bitrate: String = "source"
    var gain: String = "off"
    var concurrency: Int = 4
    var autonomy: Autonomy = .autoWhenConfident

    enum Autonomy: String, Codable {
        case proposeAll = "propose-all"
        case autoWhenConfident = "auto-when-confident"
        case manual
    }

    // Explicit CodingKeys + decode-with-defaults so a minimal YAML file
    // (just libraryRoots) decodes cleanly instead of throwing on every
    // omitted key.
    private enum CodingKeys: String, CodingKey {
        case libraryRoots, outputRoot, stateDir, filenameTemplate,
             bitrate, gain, concurrency, autonomy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        libraryRoots = try c.decode([String].self, forKey: .libraryRoots)
        outputRoot = try c.decodeIfPresent(String.self, forKey: .outputRoot)
        stateDir = try c.decodeIfPresent(String.self, forKey: .stateDir) ?? "~/.forge"
        filenameTemplate = try c.decodeIfPresent(String.self, forKey: .filenameTemplate)
            ?? "{author}/{title}/{title}.m4b"
        bitrate = try c.decodeIfPresent(String.self, forKey: .bitrate) ?? "source"
        gain = try c.decodeIfPresent(String.self, forKey: .gain) ?? "off"
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency) ?? 4
        autonomy = try c.decodeIfPresent(Autonomy.self, forKey: .autonomy) ?? .autoWhenConfident
    }

    static func load(from path: String) throws -> ForgeConfig {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw ConfigError.notFound(url.path)
        }
        do {
            return try YAMLDecoder().decode(ForgeConfig.self, from: data)
        } catch {
            throw ConfigError.invalid(url.path, String(describing: error))
        }
    }

    var stateDirURL: URL {
        URL(fileURLWithPath: (stateDir as NSString).expandingTildeInPath)
    }

    var libraryRootURLs: [URL] {
        libraryRoots.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    enum ConfigError: Error, CustomStringConvertible {
        case notFound(String)
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
            case let .invalid(path, detail):
                "Couldn't parse \(path): \(detail)"
            }
        }
    }
}
