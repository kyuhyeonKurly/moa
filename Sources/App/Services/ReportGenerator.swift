import Vapor

struct ReportContext: Encodable {
    let year: Int
    let totalCount: Int
    let monthlyStats: [MonthlyStat]
    let projects: [ProjectGroup] // 에픽별 보기
    let versionProjects: [ProjectGroup] // 버전별 보기 (구조 재사용)
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
    static func generateContext(issues: [ProcessedIssue], year: Int) -> ReportContext {
        // 1. 월별 통계
        let calendar = Calendar.current
        let issuesByMonth = Dictionary(grouping: issues) { issue in
            calendar.component(.month, from: issue.createdDate)
        }
        
        let monthlyStats = issuesByMonth.keys.sorted().map { month in
            MonthlyStat(month: month, count: issuesByMonth[month]?.count ?? 0)
        }
        
        // 공통: 프로젝트별 그룹화
        let issuesByProject = Dictionary(grouping: issues) { $0.projectKey }
        let sortedProjectKeys = issuesByProject.keys.sorted()
        
        // 2. 에픽별 보기 데이터 생성
        let projects = sortedProjectKeys.map { pKey -> ProjectGroup in
            let projectIssues = issuesByProject[pKey] ?? []
            let issuesByEpic = Dictionary(grouping: projectIssues) { $0.parentKey ?? "NO_EPIC" } // parentKey가 에픽일 수도 있고 아닐 수도 있지만, 에픽 뷰에서는 최상위 부모를 에픽으로 간주하거나, 에픽 필드를 따로 써야 함.
            // 주의: ProcessedIssue의 parentKey는 바로 위 부모임. 에픽 뷰를 위해서는 'Epic Link' 개념이 필요할 수 있음.
            // 하지만 현재 로직상 parentKey를 에픽으로 가정하고 진행 (Team-managed 프로젝트 등)
            // 만약 parentKey가 Story라면? 에픽 뷰가 좀 이상해질 수 있음.
            // 일단 기존 로직 유지: parentKey를 기준으로 그룹화.
            
            let sortedEpicKeys = issuesByEpic.keys.sorted {
                if $0 == "NO_EPIC" { return false }
                if $1 == "NO_EPIC" { return true }
                return $0 < $1
            }
            
            let groups = sortedEpicKeys.map { eKey -> SubGroup in
                let epicIssues = issuesByEpic[eKey] ?? []
                let firstIssue = epicIssues.first!
                
                let title = eKey == "NO_EPIC" ? "기타 (에픽 없음)" : (firstIssue.parentSummary ?? "Unknown Epic")
                let link = eKey == "NO_EPIC" ? nil : firstIssue.link.replacingOccurrences(of: firstIssue.key, with: eKey) // 링크 생성 트릭
                
                // 에픽 뷰는 플랫하게 보여줌 (기존 유지)
                let nodes = epicIssues.map { IssueNode(issue: $0, children: []) }
                
                return SubGroup(title: title, key: eKey == "NO_EPIC" ? nil : eKey, link: link, roots: nodes, isVersion: false, count: epicIssues.count)
            }
            
            return ProjectGroup(name: pKey, groups: groups)
        }
        
        // 3. 버전별 보기 데이터 생성 (트리 구조 적용)
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
}
