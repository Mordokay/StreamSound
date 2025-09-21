import Foundation
import SwiftUI
import UIKit

enum ThumbnailCacheError: Error {
    case invalidURL
    case downloadFailed
    case fileSystemError
}

final class ThumbnailCacheService {
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    
    // Store raw image data directly without any processing
    
    /// Get cached image data for a video ID, downloading if necessary
    func getImageData(for videoID: String, from remoteURL: String) async throws -> Data {
        let localURL = getLocalThumbnailURL(for: videoID)
        
        // Check if local file exists
        if FileManager.default.fileExists(atPath: localURL.path) {
            print("DEBUG: Using cached thumbnail data: \(localURL.path)")
            return try Data(contentsOf: localURL)
        }
        
        // Download and cache the thumbnail
        print("DEBUG: Downloading thumbnail for video ID: \(videoID)")
        return try await downloadAndCacheThumbnail(from: remoteURL, for: videoID)
    }
    
    /// Get cached image data for a video ID, trying multiple URLs if needed
    func getImageData(for videoID: String, primaryURL: String, fallbackURL: String) async throws -> Data {
        let localURL = getLocalThumbnailURL(for: videoID)
        
        // Check if local file exists
        if FileManager.default.fileExists(atPath: localURL.path) {
            print("DEBUG: Using cached thumbnail data: \(localURL.path)")
            return try Data(contentsOf: localURL)
        }
        
        // Try primary URL first
        do {
            print("DEBUG: Trying primary URL for video ID: \(videoID)")
            return try await downloadAndCacheThumbnail(from: primaryURL, for: videoID)
        } catch {
            print("DEBUG: Primary URL failed, trying fallback URL: \(error)")
            // Try fallback URL
            return try await downloadAndCacheThumbnail(from: fallbackURL, for: videoID)
        }
    }
    
    /// Get the local file URL for a video ID
    private func getLocalThumbnailURL(for videoID: String) -> URL {
        return documentsDirectory.appendingPathComponent("\(videoID).data")
    }
    
    /// Download and cache raw image data
    private func downloadAndCacheThumbnail(from remoteURLString: String, for videoID: String) async throws -> Data {
        guard let remoteURL = URL(string: remoteURLString) else {
            throw ThumbnailCacheError.invalidURL
        }
        
        let localURL = getLocalThumbnailURL(for: videoID)
        
        do {
            // Download the image data
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            
            print("DEBUG: Downloaded data size: \(data.count) bytes")
            print("DEBUG: Response URL: \(response.url?.absoluteString ?? "nil")")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("DEBUG: Response is not HTTPURLResponse")
                throw ThumbnailCacheError.downloadFailed
            }
            
            print("DEBUG: HTTP Status Code: \(httpResponse.statusCode)")
            print("DEBUG: Content-Type: \(httpResponse.allHeaderFields["Content-Type"] ?? "unknown")")
            
            guard httpResponse.statusCode == 200 else {
                print("DEBUG: HTTP request failed with status: \(httpResponse.statusCode)")
                throw ThumbnailCacheError.downloadFailed
            }
            
            // Check if data is empty
            guard !data.isEmpty else {
                print("DEBUG: Downloaded data is empty")
                throw ThumbnailCacheError.downloadFailed
            }
            
            // Test if UIImage can be created from this data (to filter out WebP on watchOS)
            if UIImage(data: data) == nil {
                print("DEBUG: Downloaded data cannot be converted to UIImage (likely WebP), will try fallback")
                throw ThumbnailCacheError.downloadFailed
            }
            
            // Save raw data directly to local storage
            try data.write(to: localURL)
            
            print("DEBUG: Thumbnail data cached successfully: \(localURL.path)")
            print("DEBUG: Cached data size: \(data.count) bytes")
            
            return data
            
        } catch {
            print("DEBUG: Failed to cache thumbnail: \(error)")
            throw error
        }
    }
    
    
    /// Check if thumbnail exists locally
    func hasCachedThumbnail(for videoID: String) -> Bool {
        let localURL = getLocalThumbnailURL(for: videoID)
        return FileManager.default.fileExists(atPath: localURL.path)
    }
    
    /// Get cached image data if it exists
    func getCachedImageData(for videoID: String) -> Data? {
        let localURL = getLocalThumbnailURL(for: videoID)
        guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
        return try? Data(contentsOf: localURL)
    }
    
    /// Delete cached thumbnail
    func deleteCachedThumbnail(for videoID: String) {
        let localURL = getLocalThumbnailURL(for: videoID)
        do {
            try FileManager.default.removeItem(at: localURL)
            print("DEBUG: Deleted cached thumbnail: \(localURL.path)")
        } catch {
            print("DEBUG: Failed to delete cached thumbnail: \(error)")
        }
    }
    
    /// Clear all cached thumbnails
    func clearAllCachedThumbnails() {
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            for url in contents {
                if url.pathExtension == "data" {
                    try fileManager.removeItem(at: url)
                    print("DEBUG: Deleted cached thumbnail: \(url.path)")
                }
            }
        } catch {
            print("DEBUG: Failed to clear cached thumbnails: \(error)")
        }
    }
}
