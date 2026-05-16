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
    }

    enum Codec: String, CaseIterable, Identifiable {
        case aac
        var id: String {
            rawValue
        }
    }

    var bitrate: Bitrate = .source
    var codec: Codec = .aac
    var outputDirectory: URL?
    var filenameTemplate: String = "{author}/{title}/{title}.m4b"
}
