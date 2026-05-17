import SwiftUI

/// Always-square cover thumbnail. The square frame is baked in so
/// callers can't accidentally produce a non-square (which can happen
/// with externally-applied frames during `scaledToFill` re-layouts).
struct CoverThumbnail: View {
    let data: Data?
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 6

    /// Cache the parsed image so re-renders (e.g. typing in the metadata
    /// panel) don't re-decode the JPEG every keystroke.
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "book.closed")
                        .font(.system(size: size * 0.45, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: data) {
            // Decode off the main actor — a 1500×1500 JPEG is tens of
            // ms on M-series, enough to drop a frame during metadata
            // swaps that change `data`.
            let captured = data
            let decoded = await Task.detached(priority: .userInitiated) {
                captured.flatMap { NSImage(data: $0) }
            }.value
            guard !Task.isCancelled else { return }
            image = decoded
        }
    }
}
