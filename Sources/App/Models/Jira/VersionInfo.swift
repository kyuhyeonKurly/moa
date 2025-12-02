import Vapor

struct VersionInfo: Content, Hashable {
    let id: String
    let name: String
    let releaseDate: Date?
}
