import Foundation

enum EncodeError: LocalizedError {
    case missingSourceFile(URL)
    case sourceChanged(URL)
    case outputUnavailable(String, String)
    case noOutputDir
    case invalidCoverImage
    case insufficientDiskSpace(required: Int64, available: Int64)

    var errorDescription: String? {
        switch self {
        case let .missingSourceFile(url):
            "Source file no longer found: \(url.lastPathComponent). "
                + "Move it back to \(url.deletingLastPathComponent().path) or remove this queue item."
        case let .sourceChanged(url):
            "Source file changed since it was queued: \(url.lastPathComponent). Remove and re-add this item to refresh it."
        case let .outputUnavailable(path, why):
            "Output folder is no longer available (\(path)): \(why). Choose a new output folder and retry."
        case .noOutputDir:
            "No output folder selected."
        case .invalidCoverImage:
            "The cover image couldn't be read. Clear it or choose a different image, then retry."
        case let .insufficientDiskSpace(required, available):
            "Not enough free space on the output volume: needs about "
                + "\(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), "
                + "only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) available."
        }
    }
}
