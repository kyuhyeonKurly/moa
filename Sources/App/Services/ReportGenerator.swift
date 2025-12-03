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
    let topLabels: [LabelCountItem] // Added topLabels
    let projects: [ProjectGroup]
    let versionProjects: [ProjectGroup]
}

struct TypeCountItem: Encodable {
    let type: String
    let count: Int
}

struct LabelCountItem: Encodable {
    let label: String
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
                    assigneeName: issue.assigneeName,
                    isMyTicket: issue.isMyTicket
                )
            }
        } else {
            displayIssues = issues
        }

        // 1. 통계 계산 (Total Count & Type Counts)
        // 조건: isMyTicket == true 인 것만 카운트
        let myTickets = displayIssues.filter { $0.isMyTicket }
        let totalCount = myTickets.count
        
        var typeCountsDict: [String: Int] = [:]
        for issue in myTickets {
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
        
        // 3. 상위 라벨 통계 (Top 5)
        var labelCountsDict: [String: Int] = [:]
        for issue in myTickets {
            for label in issue.labels {
                labelCountsDict[label, default: 0] += 1
            }
        }
        let topLabels = labelCountsDict.map { key, value in
            LabelCountItem(label: key, count: value)
        }.sorted { $0.count > $1.count }.prefix(5).map { $0 }

        // 4. 월별 통계 (Release Date 기준)
        let calendar = Calendar.current
        let issuesByMonth = Dictionary(grouping: displayIssues) { issue in
            if let releaseDate = issue.releaseDate {
                return calendar.component(.month, from: releaseDate)
            }
            return calendar.component(.month, from: issue.createdDate)
        }
        
        let monthlyStats = issuesByMonth.keys.sorted().map { month in
            MonthlyStat(month: month, count: issuesByMonth[month]?.count ?? 0)
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
        
        // 5. 에픽별 보기 데이터 생성 (Projects)
        let issuesByProject = Dictionary(grouping: displayIssues) { $0.projectKey }
        let sortedProjectKeys = issuesByProject.keys.sorted()
        
        let projects = sortedProjectKeys.map { pKey -> ProjectGroup in
            let projectIssues = issuesByProject[pKey] ?? []
            
            // Group by Parent (Epic or Story)
            var epicGroups: [String: [ProcessedIssue]] = [:]
            var epicSummaries: [String: String] = [:]
            
            for issue in projectIssues {
                if let pKey = issue.parentKey {
                    epicGroups[pKey, default: []].append(issue)
                    if let pSummary = issue.parentSummary {
                        epicSummaries[pKey] = pSummary
                    }
                } else {
                    epicGroups["No Epic", default: []].append(issue)
                }
            }
            
            let sortedEpicKeys = epicGroups.keys.sorted { k1, k2 in
                if k1 == "No Epic" { return false }
                if k2 == "No Epic" { return true }
                return k1 < k2
            }
            
            let subGroups = sortedEpicKeys.map { eKey -> SubGroup in
                let issuesInEpic = epicGroups[eKey] ?? []
                let title = eKey == "No Epic" ? "에픽 없음" : (epicSummaries[eKey] ?? eKey)
                let link = eKey == "No Epic" ? nil : "\(issuesInEpic.first?.link.components(separatedBy: "/browse/").first ?? "")/browse/\(eKey)"
                
                let roots = buildIssueTree(issues: issuesInEpic)
                
                return SubGroup(
                    title: title,
                    key: eKey == "No Epic" ? nil : eKey,
                    link: link,
                    roots: roots,
                    isVersion: false,
                    count: issuesInEpic.count
                )
            }
            
            return ProjectGroup(name: pKey, groups: subGroups)
        }
        
        // 6. 버전별 보기 데이터 생성 (VersionProjects)
        let versionProjects = sortedProjectKeys.map { pKey -> ProjectGroup in
            let projectIssues = issuesByProject[pKey] ?? []
            
            var versionGroups: [String: [ProcessedIssue]] = [:]
            
            for issue in projectIssues {
                if let v = issue.versions.first {
                    versionGroups[v.name, default: []].append(issue)
                } else {
                    versionGroups["No Version", default: []].append(issue)
                }
            }
            
            let sortedVersionNames = versionGroups.keys.sorted { v1, v2 in
                if v1 == "No Version" { return false }
                if v2 == "No Version" { return true }
                return v1 > v2
            }
            
            let subGroups = sortedVersionNames.map { vName -> SubGroup in
                let issuesInVersion = versionGroups[vName] ?? []
                let roots = buildIssueTree(issues: issuesInVersion)
                
                return SubGroup(
                    title: vName,
                    key: nil,
                    link: nil,
                    roots: roots,
                    isVersion: true,
                    count: issuesInVersion.count
                )
            }
            
            return ProjectGroup(name: pKey, groups: subGroups)
        }
        
        return ReportContext(
            year: year,
            totalCount: totalCount,
            typeCounts: typeCounts,
            monthlyGrid: monthlyGrid,
            spaceKey: spaceKey,
            platform: platform,
            monthlyStats: monthlyStats,
            topLabels: topLabels,
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
            "외부 요청"
        ]
        return order.firstIndex(of: type) ?? 999
    }
}
