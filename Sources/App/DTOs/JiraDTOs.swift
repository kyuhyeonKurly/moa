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

// MARK: - Issue Detail (상세 조회용)

/// 단일 이슈 상세 응답 (description, attachment, comment 포함)
struct JiraIssueDetail: Content {
    let key: String
    let fields: JiraDetailFields
}

struct JiraDetailFields: Content {
    let summary: String
    let description: ADFDocument?
    let status: JiraFields.JiraStatus
    let issuetype: JiraFields.JiraIssueType
    let assignee: JiraFields.JiraAssignee?
    let created: String
    let updated: String?
    let resolutiondate: String?
    let labels: [String]?
    let attachment: [JiraAttachment]?
    let comment: JiraCommentWrapper?
    let subtasks: [JiraSubtask]?
    let issuelinks: [JiraIssueLink]?
}

// MARK: - ADF (Atlassian Document Format)

/// Jira의 Rich Text 포맷 (description, comment body 등)
struct ADFDocument: Content {
    let type: String
    let version: Int?
    let content: [ADFNode]?
    
    /// ADF를 Plain Text로 변환
    func toPlainText() -> String {
        guard let content = content else { return "" }
        return content.map { $0.extractText() }.joined()
    }
}

struct ADFNode: Content {
    let type: String
    let text: String?
    let content: [ADFNode]?
    let attrs: ADFAttrs?
    
    func extractText() -> String {
        var result = ""
        
        // 텍스트 노드
        if let text = text {
            result += text
        }
        
        // 자식 노드 재귀 처리
        if let content = content {
            result += content.map { $0.extractText() }.joined()
        }
        
        // 블록 요소 뒤에 줄바꿈 추가
        switch type {
        case "paragraph", "heading", "bulletList", "orderedList", "listItem", "codeBlock", "blockquote":
            result += "\n"
        case "hardBreak":
            result += "\n"
        default:
            break
        }
        
        return result
    }
}

struct ADFAttrs: Content {
    let level: Int?
    let url: String?
}

// MARK: - Attachment

struct JiraAttachment: Content {
    let id: String
    let filename: String
    let mimeType: String?
    let size: Int
    let created: String
    let content: String  // 다운로드 URL
    let author: JiraAttachmentAuthor?
}

struct JiraAttachmentAuthor: Content {
    let accountId: String
    let displayName: String
}

// MARK: - Comment

struct JiraCommentWrapper: Content {
    let comments: [JiraComment]
    let total: Int
}

struct JiraComment: Content {
    let id: String
    let author: JiraCommentAuthor?
    let body: ADFDocument?
    let created: String
    let updated: String?
}

struct JiraCommentAuthor: Content {
    let accountId: String
    let displayName: String
}

// MARK: - Subtask & Links

struct JiraSubtask: Content {
    let key: String
    let fields: JiraSubtaskFields
}

struct JiraSubtaskFields: Content {
    let summary: String
    let status: JiraFields.JiraStatus
}

struct JiraIssueLink: Content {
    let type: JiraLinkType
    let inwardIssue: JiraLinkedIssue?
    let outwardIssue: JiraLinkedIssue?
}

struct JiraLinkType: Content {
    let name: String
}

struct JiraLinkedIssue: Content {
    let key: String
    let fields: JiraLinkedIssueFields
}

struct JiraLinkedIssueFields: Content {
    let summary: String
    let status: JiraFields.JiraStatus
}
