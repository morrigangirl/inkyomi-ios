import Foundation

struct DownloadArtifactRequest: Encodable {
    let bookId: String
    let artifactType: String

    enum CodingKeys: String, CodingKey {
        case bookId = "book_id"
        case artifactType = "artifact_type"
    }
}

struct DownloadArtifactResponse: Decodable {
    let downloadUrl: String
    let expiresIn: Int?
    let filename: String?
}
