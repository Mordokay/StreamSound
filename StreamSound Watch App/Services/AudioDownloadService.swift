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
    
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]
    
    private let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private let infoService = YouTubeAudioService()
    
    deinit {
        // Clean up all observations
        progressObservations.values.forEach { $0.invalidate() }
        progressObservations.removeAll()
    }
    
    func downloadAudio(for item: YouTubeAudio) async throws {
        guard let streamURLString = item.streamURL,
              let streamURL = URL(string: streamURLString) else {
            throw DownloadError.noStreamURL
        }
        
        downloadingItems.insert(item.id)
        downloadProgress[item.id] = 0.0
        
        do {
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
            // Update the model with FILE NAME only
            item.localFilePath = localURL.lastPathComponent
            try? item.modelContext?.save()
            downloadingItems.remove(item.id)
            downloadProgress.removeValue(forKey: item.id)
            progressObservations[item.id]?.invalidate()
            progressObservations.removeValue(forKey: item.id)
            
        } catch {
            downloadingItems.remove(item.id)
            downloadProgress.removeValue(forKey: item.id)
            progressObservations[item.id]?.invalidate()
            progressObservations.removeValue(forKey: item.id)
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
        
        // Download the file with progress tracking
        let (tempURL, response) = try await downloadWithProgress(from: url, for: item)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Failed to cast HTTPURLResponse for : \(response)")
            throw DownloadError.downloadFailed
        }
        guard httpResponse.statusCode == 200 else {
            print("Failed to get a status code 200. Instead got: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 403 { throw DownloadError.forbidden }
            throw DownloadError.downloadFailed
        }
        
        // Move to final location
        try FileManager.default.moveItem(at: tempURL, to: localURL)
        
        print("DEBUG: Download completed successfully")
        print("DEBUG: File size: \(try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64 ?? 0) bytes")
        
        return localURL
    }
    
    private func downloadWithProgress(from url: URL, for item: YouTubeAudio) async throws -> (URL, URLResponse) {
        let request = URLRequest(url: url)
        let itemID = item.id
        
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let data = data, let response = response else {
                    continuation.resume(throwing: DownloadError.downloadFailed)
                    return
                }
                
                // Write data to temporary file
                do {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try data.write(to: tempURL)
                    
                    // Update final progress
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        
                        self.downloadProgress[itemID] = 1.0

                        // Clean up observation
                        self.progressObservations[itemID]?.invalidate()
                        self.progressObservations.removeValue(forKey: itemID)
                    }
                    
                    continuation.resume(returning: (tempURL, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            // Set up progress observation
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.downloadProgress[itemID] = progress.fractionCompleted
                }
            }
            
            // Store observation for cleanup
            self?.progressObservations[itemID] = observation
            
            // Start the download
            task.resume()
        }
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

