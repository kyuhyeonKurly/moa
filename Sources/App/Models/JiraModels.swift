import Vapor

// Jira Issue 구조체
struct JiraSearchResponse: Content {
    let startAt: Int?
    let maxResults: Int?
    let total: Int?
    let nextPageToken: String?
    let issues: [JiraIssue]
}

struct JiraIssue: Content {
    let key: String
    let fields: JiraFields
}

struct JiraFields: Content {
    let summary: String
    let created: String
    let status: JiraStatus
    let labels: [String]
    let fixVersions: [JiraVersion]?
    let parent: JiraParent?
    
    // 중첩된 필드 디코딩
    struct JiraStatus: Content { let name: String }
    struct JiraVersion: Content { let name: String }
    struct JiraParent: Content {
        let key: String
        let fields: JiraParentFields
    }
    struct JiraParentFields: Content {
        let summary: String
    }
}

// Jira 검색 요청 구조체
struct JiraSearchRequest: Content {
    let jql: String
    let fields: [String]
    let maxResults: Int
    let nextPageToken: String?
}

// 내부 로직용 가공된 모델
struct ProcessedIssue: Content {
    let key: String
    let summary: String
    let createdDate: Date
    let labels: [String]
    let versions: [String]
    let link: String
    
    // 구조화된 정보 추가
    let projectKey: String
    let parentKey: String?   // 바로 위 부모 (Epic, Story, Task 등)
    let parentSummary: String?
}
