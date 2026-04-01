import SwiftUI

/// Cached zone image view. Shows cached image instantly, validates/updates in background.
struct CachedZoneImage: View {
    let urlString: String
    let fallback: AnyView

    // Populated synchronously from nonisolated cache — no actor hop, no flash
    @State private var image: UIImage? = ImageCache.shared.syncCachedImage(for: "")

    init(urlString: String, fallback: AnyView) {
        self.urlString = urlString
        self.fallback = fallback
        // Initialize with whatever is already in the sync cache
        _image = State(initialValue: ImageCache.shared.syncCachedImage(for: urlString))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallback
            }
        }
        .task(id: urlString) {
            // Fetch/validate in background — updates image silently if changed or first load
            if let fresh = await ImageCache.shared.image(for: urlString) {
                image = fresh
            }
        }
    }
}
