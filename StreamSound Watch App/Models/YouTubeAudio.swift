import Foundation
import SwiftData

@Model
final class YouTubeAudio {
    @Attribute(.unique) var id: UUID
    var originalURL: String
    var title: String?
    var uploader: String?
    var duration: Int?
    var fileExtension: String?
    var streamURL: String?
    var thumbnailURL: String?
    var shortDescription: String?
    var expireTS: Int?
    var expireHuman: String?
    var preferHls: Bool?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        originalURL: String,
        title: String?,
        uploader: String?,
        duration: Int?,
        fileExtension: String?,
        streamURL: String?,
        thumbnailURL: String?,
        shortDescription: String?,
        expireTS: Int?,
        expireHuman: String?,
        preferHls: Bool?,
        addedAt: Date = .now
    ) {
        self.id = id
        self.originalURL = originalURL
        self.title = title
        self.uploader = uploader
        self.duration = duration
        self.fileExtension = fileExtension
        self.streamURL = streamURL
        self.thumbnailURL = thumbnailURL
        self.shortDescription = shortDescription
        self.expireTS = expireTS
        self.expireHuman = expireHuman
        self.preferHls = preferHls
        self.addedAt = addedAt
    }
}

extension YouTubeAudio {
    static func from(info: YouTubeAudioInfo) -> YouTubeAudio? {
        guard info.ok == true else { return nil }
        return YouTubeAudio(
            originalURL: info.originalURL?.absoluteString ?? "",
            title: info.title,
            uploader: info.uploader,
            duration: info.duration,
            fileExtension: info.ext,
            streamURL: info.streamURL?.absoluteString,
            thumbnailURL: info.thumbnailURL?.absoluteString,
            shortDescription: info.shortDescription,
            expireTS: info.expireTS,
            expireHuman: info.expireHuman,
            preferHls: info.preferHls
        )
    }
}


