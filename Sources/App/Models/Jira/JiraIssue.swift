import Vapor

struct JiraIssue: Content {
    let key: String
    let fields: JiraFields
}
