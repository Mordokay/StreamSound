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
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw YouTubeAudioServiceError.badResponse
        }
        do {
            let decoder = JSONDecoder()
            let info = try decoder.decode(YouTubeAudioInfo.self, from: data)
            return info
        } catch {
            throw YouTubeAudioServiceError.decodingFailed
        }
    }
}


