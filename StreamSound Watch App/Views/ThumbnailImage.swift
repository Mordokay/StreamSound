import SwiftUI

// MARK: - Thumbnail with WebP -> JPEG fallback
struct ThumbnailImage: View {
    let urlString: String
    let originalURLString: String

    private func fallbackURL() -> URL? {
        // 1) Try simple WebP -> JPG replacement used by YouTube
        if urlString.contains("i.ytimg.com") {
            var replaced = urlString
            replaced = replaced.replacingOccurrences(of: "/vi_webp/", with: "/vi/")
            replaced = replaced.replacingOccurrences(of: ".webp", with: ".jpg")
            if let u = URL(string: replaced) { return u }
        }
        // 2) Derive from video ID
        if let id = extractYouTubeID(from: originalURLString) {
            let candidates = [
                "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg",
                "https://i.ytimg.com/vi/\(id)/hqdefault.jpg",
                "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"
            ]
            for c in candidates { if let u = URL(string: c) { return u } }
        }
        return nil
    }

    private func extractYouTubeID(from text: String) -> String? {
        // Look for 11-char ID
        let pattern = "[A-Za-z0-9_-]{11}"
        return text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }

    var body: some View {
        let primary = URL(string: urlString)
        let fallback = fallbackURL()
        if let primary {
            asyncImageView(url: primary, fallback: fallback)
        } else if let fallback {
            simpleAsyncImage(url: fallback)
        } else {
            Rectangle().fill(Color.gray.opacity(0.3))
        }
    }

    @ViewBuilder
    private func asyncImageView(url: URL, fallback: URL?) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                if let fallback { simpleAsyncImage(url: fallback) } else { placeholder }
            case .empty:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    @ViewBuilder
    private func simpleAsyncImage(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty:
                placeholder
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
    }

    private var placeholder: some View { Rectangle().fill(Color.gray.opacity(0.3)) }
}
