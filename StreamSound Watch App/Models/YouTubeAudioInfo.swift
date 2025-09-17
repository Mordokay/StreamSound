import Foundation

struct YouTubeAudioInfo: Codable {
    let ok: Bool
    let title: String?
    let uploader: String?
    let duration: Int?
    let ext: String?
    let streamURL: URL?
    let thumbnailURL: URL?
    let shortDescription: String?
    let expireTS: Int?
    let expireHuman: String?
    let originalURL: URL?
    let preferHls: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case title
        case uploader
        case duration
        case ext
        case streamURL = "stream_url"
        case thumbnailURL = "thumbnail_url"
        case shortDescription
        case expireTS = "expire_ts"
        case expireHuman = "expire_human"
        case originalURL = "original_url"
        case preferHls = "prefer_hls"
    }
}


