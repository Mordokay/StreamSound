import Foundation

enum YouTubeAudioServiceError: Error {
    case invalidURL
    case badResponse
    case decodingFailed
}

final class YouTubeAudioService {
    private let baseEndpoint = "https://mordokay.com/cgi-bin/yt_audio_info.py"

    func fetchInfo(for originalURLString: String) async throws -> YouTubeAudioInfo {
        guard var components = URLComponents(string: baseEndpoint) else { throw YouTubeAudioServiceError.invalidURL }
        components.queryItems = [URLQueryItem(name: "url", value: originalURLString)]
        guard let url = components.url else { throw YouTubeAudioServiceError.invalidURL }

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
            print("  - Stream URL: \(info.streamURL?.absoluteString ?? "nil")")
            print("  - Prefer HLS: \(info.preferHls ?? false)")
            
            return info
        } catch {
            throw YouTubeAudioServiceError.decodingFailed
        }
    }
}


