import SwiftUI

// MARK: - Thumbnail with raw data caching
struct ThumbnailImage: View {
    let urlString: String
    let originalURLString: String
    
    @State private var imageData: Data?
    @State private var isLoading: Bool = true
    @State private var loadError: Error?
    
    private let cacheService = ThumbnailCacheService()

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
        // Look for 11-char YouTube video ID anywhere in the text
        let pattern = "[A-Za-z0-9_-]{11}"
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range) {
                if let matchRange = Range(match.range, in: text) {
                    return String(text[matchRange])
                }
            }
        } catch {
            // If regex fails to compile, fall back to nil
        }
        return nil
    }

    var body: some View {
        Group {
            if let data = imageData {
                // Show image from cached data
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            } else if isLoading {
                // Show loading state
                placeholder
            } else {
                // Show fallback or error
                placeholder
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let videoID = extractYouTubeID(from: originalURLString) else {
            isLoading = false
            return
        }
        
        // Check if we have cached data
        if let cachedData = cacheService.getCachedImageData(for: videoID) {
            print("DEBUG: Using cached thumbnail data for video: \(videoID) and data: \(cachedData.count) bytes")
            
            // Try to create UIImage from cached data
            if UIImage(data: cachedData) != nil {
                imageData = cachedData
                isLoading = false
                return
            } else {
                print("DEBUG: Cached data is not a valid image format, will try to re-download")
            }
        }
        
        // Download and cache the thumbnail
        Task {
            do {
                let primaryURL = urlString
                let fallbackURL = fallbackURL()?.absoluteString ?? urlString
                
                print("DEBUG: ThumbnailImage - Video ID: \(videoID)")
                print("DEBUG: ThumbnailImage - Primary URL: \(primaryURL)")
                print("DEBUG: ThumbnailImage - Fallback URL: \(fallbackURL)")
                
                // Try primary URL first, then fallback
                let data = try await cacheService.getImageData(for: videoID, primaryURL: primaryURL, fallbackURL: fallbackURL)
                
                await MainActor.run {
                    imageData = data
                    isLoading = false
                }
            } catch {
                print("DEBUG: Failed to load thumbnail: \(error)")
                await MainActor.run {
                    loadError = error
                    isLoading = false
                }
            }
        }
    }

    private var placeholder: some View { 
        Rectangle().fill(Color.gray.opacity(0.3))
    }
}
