import Foundation
import AVFoundation
import Combine
import SwiftData

enum DownloadError: Error {
    case invalidURL
    case downloadFailed
    case fileSystemError
    case noStreamURL
    case forbidden
}

@MainActor
final class AudioDownloadService: ObservableObject {
    @Published var downloadingItems: Set<UUID> = []
    @Published var downloadProgress: [UUID: Double] = [:]
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let infoService = YouTubeAudioService()
    
    func downloadAudio(for item: YouTubeAudio) async throws {
        guard let streamURLString = item.streamURL,
              let streamURL = URL(string: streamURLString) else {
            throw DownloadError.noStreamURL
        }
        
        downloadingItems.insert(item.id)
        downloadProgress[item.id] = 0.0
        
        do {
            print("banana1")
            var localURL: URL
            do {
                localURL = try await performDownload(from: streamURL, for: item)
            } catch DownloadError.forbidden {
                // Expired/forbidden; refresh and retry once
                print("DEBUG: 403 on first attempt. Refreshing and retrying...")
                await refreshItem(item)
                if let refreshed = item.streamURL, let refreshedURL = URL(string: refreshed) {
                    localURL = try await performDownload(from: refreshedURL, for: item)
                } else {
                    throw DownloadError.downloadFailed
                }
            }
            print("banana2")
            // Update the model with FILE NAME only
            item.localFilePath = localURL.lastPathComponent
            try? item.modelContext?.save()
            print("banana3")
            downloadingItems.remove(item.id)
            downloadProgress.removeValue(forKey: item.id)
            
        } catch {
            downloadingItems.remove(item.id)
            downloadProgress.removeValue(forKey: item.id)
            throw error
        }
    }
    
    private func performDownload(from url: URL, for item: YouTubeAudio) async throws -> URL {
        // Create filename: 11-char YouTube ID + extension
        let videoID = extractVideoID(from: item.originalURL) ?? "unknown"
        let ext = sanitizeExtension(item.fileExtension ?? "m4a") // Use the actual extension from server
        let filename = "\(videoID).\(ext)"
        let localURL = documentsDirectory.appendingPathComponent(filename)
        
        print("DEBUG: Downloading from URL: \(url)")
        print("DEBUG: Using extension: \(ext)")
        print("DEBUG: Saving to: \(localURL.path)")
        
        // If the file already exists, reuse it
        if FileManager.default.fileExists(atPath: localURL.path) {
            print("DEBUG: File already exists, reusing: \(localURL.path)")
            return localURL
        }
        
        // Download the file
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("banana4: \(response)")
            throw DownloadError.downloadFailed
        }
        guard httpResponse.statusCode == 200 else {
            print("banana4: \(response)")
            if httpResponse.statusCode == 403 { throw DownloadError.forbidden }
            throw DownloadError.downloadFailed
        }
        
        // Move to final location
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        
        print("DEBUG: Download completed successfully")
        print("DEBUG: File size: \(try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0) bytes")
        
        return localURL
    }

    // MARK: - Filename Sanitization
    private func sanitizeFilenameComponent(_ input: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let trimmed = input.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce("") { $0 + String($1) }
        // Collapse multiple dashes/spaces and trim
        let collapsed = trimmed.replacingOccurrences(of: "[\n\r\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "audio" : collapsed
    }
    
    private func sanitizeExtension(_ input: String) -> String {
        let lower = input.lowercased()
        // Only allow known audio/container extensions AVPlayer on watchOS typically supports
        let allowed = ["m4a", "mp4", "aac", "mp3", "mov", "m3u8"]
        return allowed.contains(lower) ? lower : "m4a"
    }
    
    func deleteLocalFile(for item: YouTubeAudio) {
        guard let stored = item.localFilePath else { return }

        let fileManager = FileManager.default
        let path: String
        if stored.hasPrefix("/") {
            path = stored
        } else {
            path = documentsDirectory.appendingPathComponent(stored).path
        }

        if fileManager.fileExists(atPath: path) {
            do { try fileManager.removeItem(atPath: path) }
            catch { print("Failed to delete local file: \(error)") }
        } else {
            print("DEBUG: Local file did not exist at resolved path, clearing model path: \(path)")
        }

        // Clear model path regardless and persist
        item.localFilePath = nil
        try? item.modelContext?.save()
    }
    
    func getLocalFileURL(for item: YouTubeAudio) -> URL? {
        guard let stored = item.localFilePath, !stored.isEmpty else { return nil }
        // If an absolute path was stored previously, use it; otherwise resolve within Documents
        if stored.hasPrefix("/") { return URL(fileURLWithPath: stored) }
        return documentsDirectory.appendingPathComponent(stored)
    }
    
    private func extractVideoID(from urlString: String) -> String? {
        let pattern = "[A-Za-z0-9_-]{11}"
        return urlString.range(of: pattern, options: .regularExpression).map { String(urlString[$0]) }
    }
    
    func isDownloading(_ item: YouTubeAudio) -> Bool {
        downloadingItems.contains(item.id)
    }
    
    func getDownloadProgress(_ item: YouTubeAudio) -> Double {
        downloadProgress[item.id] ?? 0.0
    }

    // MARK: - Refresh helpers
    private func refreshIfNeeded(_ item: YouTubeAudio) async {
        if let expire = item.expireTS, Date(timeIntervalSince1970: TimeInterval(expire)) > .now, item.streamURL != nil {
            return
        }
        await refreshItem(item)
    }

    private func refreshItem(_ item: YouTubeAudio) async {
        do {
            let info = try await infoService.fetchInfo(for: item.originalURL)
            item.title = info.title
            item.uploader = info.uploader
            item.duration = info.duration
            item.fileExtension = info.ext
            item.streamURL = info.streamURL?.absoluteString
            item.thumbnailURL = info.thumbnailURL?.absoluteString
            item.shortDescription = info.shortDescription
            item.expireTS = info.expireTS
            item.expireHuman = info.expireHuman
            item.preferHls = info.preferHls
            try? item.modelContext?.save()
            print("DEBUG: Refreshed item stream before download")
        } catch {
            print("DEBUG: Failed to refresh item before download: \(error)")
        }
    }
}
