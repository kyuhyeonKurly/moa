import Vapor

struct JiraSearchRequest: Content {
    let jql: String
    let fields: [String]
    let maxResults: Int
    let nextPageToken: String?
}
