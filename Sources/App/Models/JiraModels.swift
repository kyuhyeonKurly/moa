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
    let resolutiondate: String? // 추가
    let status: JiraStatus
    let issuetype: JiraIssueType
    let labels: [String]
    let fixVersions: [JiraVersion]?
    let parent: JiraParent?
    let assignee: JiraAssignee? // 추가
    
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
        let issuetype: JiraIssueType?
    }
    struct JiraAssignee: Content { // 추가
        let accountId: String
        let displayName: String
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
    let versions: [VersionInfo] // String -> VersionInfo 변경
    let link: String
    
    // 구조화된 정보 추가
    let projectKey: String
    let parentKey: String?   // 바로 위 부모 (Epic, Story, Task 등)
    let parentSummary: String?
    let parentType: String?
    
    // 계층 구조 표시용 (Subtask -> Story -> Epic 인 경우 Epic 정보)
    var displayParentKey: String?
    var displayParentSummary: String?
    
    // 추가된 필드
    let issueType: String
    let isSubtask: Bool
    let typeClass: String
    let releaseDate: Date?
    let assigneeAccountId: String? // 추가
    let assigneeName: String? // 추가
    var isMyTicket: Bool = false // 내 티켓 여부 (통계용)
}

struct VersionInfo: Content, Hashable {
    let id: String
    let name: String
    let releaseDate: Date?
}

struct JiraUser: Content {
    let accountId: String
    let displayName: String
}
