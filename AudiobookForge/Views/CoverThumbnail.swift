import SwiftUI

struct CoverThumbnail: View {
    let data: Data?
    var cornerRadius: CGFloat = 6

    // Cache the parsed image so re-renders (e.g. typing in the metadata
    // panel) don't re-decode the JPEG every keystroke.
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
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: data) {
            image = data.flatMap { NSImage(data: $0) }
        }
    }
}
