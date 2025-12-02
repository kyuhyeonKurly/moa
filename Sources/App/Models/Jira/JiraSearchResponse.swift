import Vapor

struct JiraSearchResponse: Content {
    let startAt: Int?
    let maxResults: Int?
    let total: Int?
    let nextPageToken: String?
    let issues: [JiraIssue]
}
