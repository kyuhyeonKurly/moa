import Vapor

struct ReportContext: Encodable {
    let year: Int
    let totalCount: Int
    let typeCounts: [TypeCountItem]
    let monthlyGrid: [MonthlyGridItem]
    let spaceKey: String? // Added spaceKey
    let platform: String? // Added platform
    
    // 기존 필드 (하위 호환성 유지)
    let monthlyStats: [MonthlyStat]
    let projects: [ProjectGroup]
    let versionProjects: [ProjectGroup]
}

struct TypeCountItem: Encodable {
    let type: String
    let count: Int
}

struct MonthlyGridItem: Encodable {
    let monthName: String
    let monthIndex: Int
    let issues: [ProcessedIssue]
}

struct MonthlyStat: Encodable {
    let month: Int
    let count: Int
}

struct ProjectGroup: Encodable {
    let name: String
    let groups: [SubGroup] // 에픽 또는 버전 그룹
}

struct SubGroup: Encodable {
    let title: String
    let key: String?
    let link: String?
    let roots: [IssueNode] // 트리 구조 지원
    let isVersion: Bool
    let count: Int
}

struct IssueNode: Encodable {
    let issue: ProcessedIssue
    let children: [IssueNode]
}

struct ReportGenerator {
    static func generateContext(issues: [ProcessedIssue], year: Int, spaceKey: String? = nil, platform: String? = nil) -> ReportContext {
        // 0. 플랫폼 필터링 (View용 데이터 가공)
        let displayIssues: [ProcessedIssue]
        if let platform = platform, !platform.isEmpty {
            displayIssues = issues.map { issue in
                // 해당 플랫폼이 포함된 버전만 남김
                let filteredVersions = issue.versions.filter { $0.name.contains(platform) }
                
                return ProcessedIssue(
                    key: issue.key,
                    summary: issue.summary,
                    createdDate: issue.createdDate,
                    labels: issue.labels,
                    versions: filteredVersions,
                    link: issue.link,
                    projectKey: issue.projectKey,
                    parentKey: issue.parentKey,
                    parentSummary: issue.parentSummary,
                    issueType: issue.issueType,
                    isSubtask: issue.isSubtask,
                    typeClass: issue.typeClass,
                    releaseDate: issue.releaseDate,
                    assigneeAccountId: issue.assigneeAccountId,
                    assigneeName: issue.assigneeName
                )
            }
        } else {
            displayIssues = issues
        }

        // 1. 월별 통계 (Release Date 기준)
        let calendar = Calendar.current
        let issuesByMonth = Dictionary(grouping: displayIssues) { issue in
            if let releaseDate = issue.releaseDate {
                return calendar.component(.month, from: releaseDate)
            }
            return calendar.component(.month, from: issue.createdDate)
        }
        
        // [Modified] 통계 비활성화
        // let monthlyStats = issuesByMonth.keys.sorted().map { month in
        //     MonthlyStat(month: month, count: issuesByMonth[month]?.count ?? 0)
        // }
        let monthlyStats: [MonthlyStat] = []
        
        // 2. 타입별 카운트
        // [Modified] 타입별 요약 비활성화
        // var typeCountsDict: [String: Int] = [:]
        // for issue in issues {
        //     typeCountsDict[issue.issueType, default: 0] += 1
        // }
        // 
        // let typeCounts = typeCountsDict.map { key, value in
        //     TypeCountItem(type: key, count: value)
        // }.sorted { item1, item2 in
        //     let p1 = getTypePriority(item1.type)
        //     let p2 = getTypePriority(item2.type)
        //     
        //     if p1 != p2 {
        //         return p1 < p2
        //     } else {
        //         return item1.count > item2.count
        //     }
        // }
        let typeCounts: [TypeCountItem] = []
        
        // 3. 월별 그리드 (1월 ~ 12월)
        // 조건: 버전이 있고, 서브태스크가 아닌 최상위 티켓만 표시
        var monthlyGrid: [MonthlyGridItem] = []
        let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        
        for i in 1...12 {
            let monthIssues = issuesByMonth[i] ?? []
            let filteredIssues = monthIssues.filter { issue in
                !issue.versions.isEmpty && 
                !issue.isSubtask &&
                !issue.versions.contains { v in 
                    v.name.contains("버전할당 대기") || v.name.contains("버전 할당 대기")
                }
            }.sorted { issue1, issue2 in
                // 1. 릴리즈 날짜 순
                if let d1 = issue1.releaseDate, let d2 = issue2.releaseDate, d1 != d2 {
                    return d1 < d2
                }
                
                // 2. 우선순위 순
                let p1 = getTypePriority(issue1.issueType)
                let p2 = getTypePriority(issue2.issueType)
                
                if p1 != p2 {
                    return p1 < p2
                }
                return issue1.createdDate < issue2.createdDate
            }
            
            monthlyGrid.append(MonthlyGridItem(
                monthName: monthNames[i-1],
                monthIndex: i,
                issues: filteredIssues
            ))
        }
        
        // [Modified] 에픽별/버전별 보기 비활성화
        // // 공통: 프로젝트별 그룹화 (기존 로직 유지)
        // let issuesByProject = Dictionary(grouping: issues) { $0.projectKey }
        // let sortedProjectKeys = issuesByProject.keys.sorted()
        // 
        // // 4. 에픽별 보기 데이터 생성
        // let projects = sortedProjectKeys.map { pKey -> ProjectGroup in
        //     ...
        // }
        // 
        // // 5. 버전별 보기 데이터 생성
        // let versionProjects = sortedProjectKeys.map { pKey -> ProjectGroup in
        //     ...
        // }
        
        return ReportContext(
            year: year,
            totalCount: 0, // [Modified] 총 티켓 수 비활성화
            typeCounts: typeCounts,
            monthlyGrid: monthlyGrid,
            spaceKey: spaceKey,
            platform: platform,
            monthlyStats: monthlyStats,
            projects: [], // [Modified] 에픽별 보기 비활성화
            versionProjects: [] // [Modified] 버전별 보기 비활성화
        )
    }
    
    // 트리 빌더
    private static func buildIssueTree(issues: [ProcessedIssue]) -> [IssueNode] {
        // 1. 모든 이슈를 Node로 변환 (참조를 위해 클래스 사용하거나 딕셔너리 사용)
        // 여기서는 간단히 딕셔너리 사용.
        // 부모-자식 관계를 맺으려면 부모가 '이 리스트 안에' 있어야 함.
        
        let issueMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0) })
        var childrenMap: [String: [ProcessedIssue]] = [:]
        var roots: [ProcessedIssue] = []
        
        for issue in issues {
            if let pKey = issue.parentKey, issueMap[pKey] != nil {
                // 부모가 이 그룹 안에 존재함 -> 자식으로 등록
                childrenMap[pKey, default: []].append(issue)
            } else {
                // 부모가 없거나, 부모가 이 그룹에 없음 -> 루트로 취급
                roots.append(issue)
            }
        }
        
        // 재귀적으로 Node 생성
        func createNode(issue: ProcessedIssue) -> IssueNode {
            let children = childrenMap[issue.key]?.map { createNode(issue: $0) } ?? []
            return IssueNode(issue: issue, children: children)
        }
        
        return roots.map { createNode(issue: $0) }
    }

    private static func getTypePriority(_ type: String) -> Int {
        let order = [
            "Epic", "에픽",
            "Story", "스토리",
            "Improvement", "개선",
            "Bug", "버그",
            "Design", "디자인",
            "Task", "작업",
            "Sub-task", "하위 작업",
            "BI 요청"
        ]
        return order.firstIndex(of: type) ?? 999
    }
}
