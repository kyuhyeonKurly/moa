import Vapor

struct ProcessedIssue: Content {
    let key: String
    let summary: String
    let createdDate: Date
    let labels: [String]
    let versions: [VersionInfo]
    let link: String
    
    // 구조화된 정보 추가
    let projectKey: String
    let parentKey: String?   // 바로 위 부모 (Epic, Story, Task 등)
    let parentSummary: String?
    
    // 추가된 필드
    let issueType: String
    let isSubtask: Bool
    let typeClass: String
    let releaseDate: Date?
}
