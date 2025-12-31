import Vapor

struct JiraProjectVersion: Content {
    let id: String
    let name: String
    let released: Bool
    let releaseDate: String?
    let projectId: Int?
}
