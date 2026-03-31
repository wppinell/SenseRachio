import SwiftUI

/// Cached zone image view. Loads from disk cache, validates with ETag, downloads only if changed.
struct CachedZoneImage: View {
    let urlString: String
    let fallback: AnyView

    @State private var image: UIImage? = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                fallback
                    .overlay(
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.7)
                    )
            } else {
                fallback
            }
        }
        .task(id: urlString) {
            isLoading = true
            image = await ImageCache.shared.image(for: urlString)
            isLoading = false
        }
    }
}
