import Vapor

struct JiraFields: Content {
    let summary: String
    let created: String
    let resolutiondate: String?
    let status: JiraStatus
    let issuetype: JiraIssueType
    let labels: [String]
    let fixVersions: [JiraVersion]?
    let parent: JiraParent?
    
    // 중첩된 필드 디코딩
    struct JiraStatus: Content { let name: String }
    struct JiraIssueType: Content { 
        let name: String 
        let subtask: Bool
    }
    struct JiraVersion: Content { 
        let id: String
        let name: String 
        let releaseDate: String?
    }
    struct JiraParent: Content {
        let key: String
        let fields: JiraParentFields
    }
    struct JiraParentFields: Content {
        let summary: String
    }
}
