import Foundation

enum YouTubeAudioServiceError: Error {
    case invalidURL
    case badResponse
    case decodingFailed
}

final class YouTubeAudioService {
    private let baseEndpoint = "https://mordokay.com/cgi-bin/yt_audio_info.py"

    /// Fetches audio information for a YouTube URL with default settings (M4A up to 64 kbps)
    /// - Parameter originalURLString: The YouTube URL or video ID
    /// - Returns: YouTubeAudioInfo containing audio metadata and stream URL
    func fetchInfo(for originalURLString: String) async throws -> YouTubeAudioInfo {
        return try await fetchInfo(for: originalURLString, maxAbr: 64, preferHls: false)
    }
    
    /// Fetches audio information for a YouTube URL with custom bitrate settings
    /// - Parameters:
    ///   - originalURLString: The YouTube URL or video ID
    ///   - maxAbr: Maximum audio bitrate in kbps (e.g., 48 for stricter cap, 64 for default)
    ///   - preferHls: Whether to prefer HLS AAC variants (m3u8 format) over direct audio streams
    /// - Returns: YouTubeAudioInfo containing audio metadata and stream URL
    /// 
    /// Examples:
    /// - Default Opus up to 64 kbps: `fetchInfo(for: url)`
    /// - Stricter 48 kbps cap: `fetchInfo(for: url, maxAbr: 48)`
    /// - HLS AAC at 64 kbps: `fetchInfo(for: url, maxAbr: 64, preferHls: true)`
    func fetchInfo(for originalURLString: String, maxAbr: Int, preferHls: Bool = false) async throws -> YouTubeAudioInfo {
        guard var components = URLComponents(string: baseEndpoint) else { throw YouTubeAudioServiceError.invalidURL }
        
        var queryItems = [URLQueryItem(name: "url", value: originalURLString)]
        
        // Add max_abr parameter if specified
        if maxAbr > 0 {
            queryItems.append(URLQueryItem(name: "max_abr", value: String(maxAbr)))
        }
        
        // Add prefer_hls parameter if requested
        if preferHls {
            queryItems.append(URLQueryItem(name: "prefer_hls", value: "1"))
        }
        
        components.queryItems = queryItems
        guard let url = components.url else { throw YouTubeAudioServiceError.invalidURL }

        print("DEBUG: Making request to: \(url.absoluteString)")
        print("DEBUG: Request parameters - maxAbr: \(maxAbr), preferHls: \(preferHls)")

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("DEBUG: No HTTP response received")
            throw YouTubeAudioServiceError.badResponse
        }
        
        print("DEBUG: Server response - Status: \(http.statusCode), URL: \(http.url?.absoluteString ?? "unknown")")
        
        guard (200..<300).contains(http.statusCode) else {
            print("DEBUG: Server error - Status: \(http.statusCode)")
            if let responseData = String(data: data, encoding: .utf8) {
                print("DEBUG: Server response body: \(responseData)")
            }
            throw YouTubeAudioServiceError.badResponse
        }
        do {
            let decoder = JSONDecoder()
            let info = try decoder.decode(YouTubeAudioInfo.self, from: data)
            
            // Debug: Print the audio info we received
            print("DEBUG: Received audio info:")
            print("  - Title: \(info.title ?? "nil")")
            print("  - Uploader: \(info.uploader ?? "nil")")
            print("  - Duration: \(info.duration ?? 0)")
            print("  - Extension: \(info.ext ?? "nil")")
            print("  - Format ID: \(info.formatId ?? "nil")")
            print("  - Codec: \(info.acodec ?? "nil")")
            print("  - Bitrate: \(info.abrKbps ?? 0) kbps")
            print("  - Estimated Size: \(info.estimatedSizeMb ?? 0) MB")
            print("  - Stream URL: \(info.streamURL?.absoluteString ?? "nil")")
            print("  - Prefer HLS: \(info.preferHls ?? false)")
            
            return info
        } catch {
            throw YouTubeAudioServiceError.decodingFailed
        }
    }
}


