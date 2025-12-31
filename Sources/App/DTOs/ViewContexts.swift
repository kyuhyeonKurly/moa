import Vapor

struct ReportContext: Content {
    let year: Int
    let totalCount: Int
    let typeCounts: [TypeCountItem]
    let monthlyGrid: [MonthlyGridItem]
    let spaceKey: String?
    let platform: String?
    
    // 기존 필드 (하위 호환성 유지)
    let monthlyStats: [MonthlyStat]
    let topLabels: [LabelCountItem]
    let projects: [ProjectGroup]
    let versionProjects: [ProjectGroup]
    
    // MARK: - Nested Types
    
    struct TypeCountItem: Content {
        let type: String
        let count: Int
    }

    struct LabelCountItem: Content {
        let label: String
        let count: Int
    }

    struct MonthlyGridItem: Content {
        let monthName: String
        let monthIndex: Int
        let issues: [ProcessedIssue]
    }

    struct MonthlyStat: Content {
        let month: Int
        let count: Int
    }

    struct ProjectGroup: Content {
        let name: String
        let groups: [SubGroup] // 에픽 또는 버전 그룹
    }

    struct SubGroup: Content {
        let title: String
        let key: String?
        let link: String?
        let roots: [IssueNode] // 트리 구조 지원
        let isVersion: Bool
        let count: Int
    }

    struct IssueNode: Content {
        let issue: ProcessedIssue
        let children: [IssueNode]
    }
}
