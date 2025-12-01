import Vapor

struct ReportContext: Encodable {
    let year: Int
    let totalCount: Int
    let typeCounts: [TypeCountItem]
    let monthlyGrid: [MonthlyGridItem]
    let spaceKey: String? // Added spaceKey
    
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
    static func generateContext(issues: [ProcessedIssue], year: Int, spaceKey: String? = nil) -> ReportContext {
        // 1. 월별 통계 (Release Date 기준)
        let calendar = Calendar.current
        let issuesByMonth = Dictionary(grouping: issues) { issue in
            if let releaseDate = issue.releaseDate {
                return calendar.component(.month, from: releaseDate)
            }
            return calendar.component(.month, from: issue.createdDate)
        }
        
        let monthlyStats = issuesByMonth.keys.sorted().map { month in
            MonthlyStat(month: month, count: issuesByMonth[month]?.count ?? 0)
        }
        
        // 2. 타입별 카운트
        var typeCountsDict: [String: Int] = [:]
        for issue in issues {
            typeCountsDict[issue.issueType, default: 0] += 1
        }
        
        let typeCounts = typeCountsDict.map { key, value in
            TypeCountItem(type: key, count: value)
        }.sorted { item1, item2 in
            let p1 = getTypePriority(item1.type)
            let p2 = getTypePriority(item2.type)
            
            if p1 != p2 {
                return p1 < p2
            } else {
                return item1.count > item2.count
            }
        }
        
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
                    v.contains("버전할당 대기") || v.contains("버전 할당 대기")
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
        
        // 공통: 프로젝트별 그룹화 (기존 로직 유지)
        let issuesByProject = Dictionary(grouping: issues) { $0.projectKey }
        let sortedProjectKeys = issuesByProject.keys.sorted()
        
        // 4. 에픽별 보기 데이터 생성
        let projects = sortedProjectKeys.map { pKey -> ProjectGroup in
            let projectIssues = issuesByProject[pKey] ?? []
            let issuesByEpic = Dictionary(grouping: projectIssues) { $0.parentKey ?? "NO_EPIC" }
            
            let sortedEpicKeys = issuesByEpic.keys.sorted {
                if $0 == "NO_EPIC" { return false }
                if $1 == "NO_EPIC" { return true }
                return $0 < $1
            }
            
            let groups = sortedEpicKeys.map { eKey -> SubGroup in
                let epicIssues = issuesByEpic[eKey] ?? []
                let firstIssue = epicIssues.first!
                
                let title = eKey == "NO_EPIC" ? "기타 (에픽 없음)" : (firstIssue.parentSummary ?? "Unknown Epic")
                let link = eKey == "NO_EPIC" ? nil : firstIssue.link.replacingOccurrences(of: firstIssue.key, with: eKey)
                
                let nodes = epicIssues.map { IssueNode(issue: $0, children: []) }
                
                return SubGroup(title: title, key: eKey == "NO_EPIC" ? nil : eKey, link: link, roots: nodes, isVersion: false, count: epicIssues.count)
            }
            
            return ProjectGroup(name: pKey, groups: groups)
        }
        
        // 5. 버전별 보기 데이터 생성
        let versionProjects = sortedProjectKeys.map { pKey -> ProjectGroup in
            let projectIssues = issuesByProject[pKey] ?? []
            
            var issuesByVersion: [String: [ProcessedIssue]] = [:]
            
            for issue in projectIssues {
                if issue.versions.isEmpty {
                    issuesByVersion["Unversioned", default: []].append(issue)
                } else {
                    let normalizedVersions = Set(issue.versions.map { version -> String in
                        return version.replacingOccurrences(of: " - iOS", with: "")
                                      .replacingOccurrences(of: " - Android", with: "")
                    })
                    
                    for version in normalizedVersions {
                        issuesByVersion[version, default: []].append(issue)
                    }
                }
            }
            
            let sortedVersionNames = issuesByVersion.keys.sorted {
                if $0 == "Unversioned" { return false }
                if $1 == "Unversioned" { return true }
                return $0 > $1
            }
            
            let groups = sortedVersionNames.map { vName -> SubGroup in
                let vIssues = issuesByVersion[vName] ?? []
                let roots = buildIssueTree(issues: vIssues)
                return SubGroup(title: vName, key: nil, link: nil, roots: roots, isVersion: true, count: vIssues.count)
            }
            
            return ProjectGroup(name: pKey, groups: groups)
        }
        
        return ReportContext(
            year: year,
            totalCount: issues.count,
            typeCounts: typeCounts,
            monthlyGrid: monthlyGrid,
            spaceKey: spaceKey,
            monthlyStats: monthlyStats,
            projects: projects,
            versionProjects: versionProjects
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
