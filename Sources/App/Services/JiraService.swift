import Vapor

struct JiraService {
    let apiClient: JiraAPIClient
    
    func fetchIssues(year: Int, assignee: String? = nil, platform: String? = nil) async throws -> [ProcessedIssue] {
        print("[Debug] fetchIssues started. Year: \(year), Assignee: \(assignee ?? "nil")")

        // 0. 내 정보 가져오기 (AccountId 식별용 & 토큰 검증)
        var myAccountId: String?
        let myselfUri = URI(string: "\(apiClient.apiBaseURL)/rest/api/3/myself")
        do {
            let myselfResponse = try await apiClient.client.get(myselfUri, headers: apiClient.headers)
            if myselfResponse.status == .ok {
                let myself = try myselfResponse.content.decode(Myself.self)
                myAccountId = myself.accountId
                print("[Debug] ✅ Auth Success! Logged in as: \(myself.displayName)")
            } else {
                print("[Debug] ❌ Auth Failed! Status: \(myselfResponse.status)")
                throw Abort(.unauthorized, reason: "Jira 인증 실패: 이메일과 토큰을 확인해주세요. (Status: \(myselfResponse.status))")
            }
        } catch {
            print("[Debug] ❌ Auth Request Error: \(error)")
            throw Abort(.unauthorized, reason: "Jira 인증 요청 중 오류 발생: \(error)")
        }
        
        // 1. 먼저 사용자가 활동한 프로젝트를 찾기 위해 광범위한 검색 수행
        // [Modified] 모든 내 이슈를 먼저 수집 (Sub-task 포함)
        let assigneeClause = assignee != nil ? "assignee = \"\(assignee!)\"" : "assignee = currentUser()"
        let jql = """
        \(assigneeClause) 
        AND project not in (KQA) 
        AND (created >= \(year)-01-01 OR resolutiondate >= \(year)-01-01)
        """
        
        // 2. 이슈 수집 실행
        var myIssues = try await executeJqlSearch(jql: jql, platform: platform)
        
        // 3. 내 이슈로 마킹
        for i in 0..<myIssues.count {
            myIssues[i].isMyTicket = true
        }
        
        // 4. 재귀적 버전 조회 (부모 이슈 조회 포함)
        // resolveVersionsRecursively는 필요한 부모 이슈를 추가로 fetch하여 리스트에 포함시킴
        // 이때 추가된 부모 이슈는 isMyTicket이 false(기본값)일 것임 -> OK
        return try await resolveVersionsRecursively(issues: myIssues, platform: platform)
    }
    
    struct Myself: Decodable {
        let accountId: String
        let displayName: String
    }
    
    private func executeJqlSearch(jql: String, platform: String? = nil) async throws -> [ProcessedIssue] {
        print("[Debug] executeJqlSearch called. Platform: \(platform ?? "nil")")
        print("[Debug] JQL: \(jql)")
        
        var issues: [ProcessedIssue] = []
        var nextPageToken: String? = nil
        let maxResults = 100
        var isFinished = false
        
        while !isFinished {
            let searchResult = try await apiClient.searchIssues(
                jql: jql,
                fields: ["summary", "status", "labels", "created", "resolutiondate", "fixVersions", "parent", "issuetype", "assignee"],
                maxResults: maxResults,
                nextPageToken: nextPageToken
            )
            
            print("[Debug] Search returned \(searchResult.issues.count) issues.")
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            let backupDateFormatter = DateFormatter()
            backupDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            let releaseDateFormatter = DateFormatter()
            releaseDateFormatter.dateFormat = "yyyy-MM-dd"
            
            let pageIssues = searchResult.issues.map { issue -> ProcessedIssue in
                let dateString = issue.fields.resolutiondate ?? issue.fields.created
                let date = dateFormatter.date(from: dateString) 
                    ?? backupDateFormatter.date(from: dateString) 
                    ?? ISO8601DateFormatter().date(from: dateString)
                    ?? Date()
                
                // Version Mapping & Sorting
                let rawVersions: [VersionInfo] = issue.fields.fixVersions?.map { version in
                    let vDate = version.releaseDate.flatMap { releaseDateFormatter.date(from: $0) }
                    return VersionInfo(id: version.id, name: version.name, releaseDate: vDate)
                } ?? []
                
                let sortedVersions: [VersionInfo]
                if let platform = platform, !platform.isEmpty {
                    print("[Debug] Filtering Issue \(issue.key) for platform: '\(platform)'")
                    print("[Debug] Raw Versions: \(rawVersions.map { $0.name })")
                    
                    sortedVersions = rawVersions.filter { version in
                        version.name.localizedCaseInsensitiveContains(platform)
                    }
                    
                    print("[Debug] Filtered Versions: \(sortedVersions.map { $0.name })")
                } else {
                    sortedVersions = rawVersions
                }
                
                let releaseDate = sortedVersions.first?.releaseDate
                
                let projectKey = issue.key.split(separator: "-").first.map(String.init) ?? "UNKNOWN"
                
                var parentKey: String? = nil
                var parentSummary: String? = nil
                if let parent = issue.fields.parent {
                    parentKey = parent.key
                    parentSummary = parent.fields.summary
                }
                
                // 이슈 타입 매핑
                var issueType = issue.fields.issuetype.name
                if issueType == "Service Request with Approvals" { issueType = "외부 요청" }
                
                // 상태 매핑
                let typeClass = self.getTypeClass(for: issueType)
                
                return ProcessedIssue(
                    key: issue.key,
                    summary: issue.fields.summary,
                    createdDate: date,
                    labels: issue.fields.labels,
                    versions: sortedVersions,
                    link: "\(apiClient.apiBaseURL)/browse/\(issue.key)",
                    projectKey: projectKey,
                    parentKey: parentKey,
                    parentSummary: parentSummary,
                    issueType: issueType,
                    isSubtask: issue.fields.issuetype.subtask,
                    typeClass: typeClass,
                    releaseDate: releaseDate,
                    assigneeAccountId: issue.fields.assignee?.accountId,
                    assigneeName: issue.fields.assignee?.displayName
                )
            }
            
            issues.append(contentsOf: pageIssues)
            
            if let token = searchResult.nextPageToken, !token.isEmpty {
                nextPageToken = token
            } else {
                isFinished = true
            }
        }
        return issues
    }
    
    private func resolveVersionsRecursively(issues: [ProcessedIssue], platform: String? = nil) async throws -> [ProcessedIssue] {
        var issueMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0) })
        var versionMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0.versions) })
        var releaseDateMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0.releaseDate) })
        var parentMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0.parentKey) })
        
        for _ in 0..<3 {
            let unresolvedKeys = issueMap.keys.filter { (versionMap[$0]?.isEmpty ?? true) && parentMap[$0] != nil }
            if unresolvedKeys.isEmpty { break }
            
            let knownKeys = Set(issueMap.keys)
            let requiredParentKeys = Set(unresolvedKeys.compactMap { parentMap[$0] ?? nil })
            let missingParentKeys = requiredParentKeys.subtracting(knownKeys)
            
            if !missingParentKeys.isEmpty {
                let fetchedParents = try await fetchIssuesByKeys(keys: Array(missingParentKeys), platform: platform)
                for p in fetchedParents {
                    issueMap[p.key] = p
                    versionMap[p.key] = p.versions
                    releaseDateMap[p.key] = p.releaseDate
                    parentMap[p.key] = p.parentKey
                }
            }
            
            var changed = false
            for key in unresolvedKeys {
                if let pKey = parentMap[key] ?? nil, let pVersions = versionMap[pKey], !pVersions.isEmpty {
                    versionMap[key] = pVersions
                    releaseDateMap[key] = releaseDateMap[pKey] ?? nil
                    changed = true
                }
            }
            
            if !changed && missingParentKeys.isEmpty { break }
        }
        
        return issues.map { issue in
            if let v = versionMap[issue.key], !v.isEmpty {
                return ProcessedIssue(
                    key: issue.key,
                    summary: issue.summary,
                    createdDate: issue.createdDate,
                    labels: issue.labels,
                    versions: v,
                    link: issue.link,
                    projectKey: issue.projectKey,
                    parentKey: issue.parentKey,
                    parentSummary: issue.parentSummary,
                    issueType: issue.issueType,
                    isSubtask: issue.isSubtask,
                    typeClass: issue.typeClass,
                    releaseDate: releaseDateMap[issue.key] ?? nil,
                    assigneeAccountId: issue.assigneeAccountId,
                    assigneeName: issue.assigneeName,
                    isMyTicket: issue.isMyTicket // 기존 값 유지
                )
            }
            return issue
        }
    }
    
    private func fetchIssuesByKeys(keys: [String], platform: String? = nil) async throws -> [ProcessedIssue] {
        if keys.isEmpty { return [] }
        let jql = "key in (\(keys.joined(separator: ",")))"
        return try await executeJqlSearch(jql: jql, platform: platform)
    }
    
    private func getTypeClass(for typeName: String) -> String {
        switch typeName {
        case "Epic", "에픽": return "type-epic"
        case "Story", "스토리": return "type-story"
        case "Task", "작업": return "type-task"
        case "Bug", "버그": return "type-bug"
        case "Improvement", "개선": return "type-improvement"
        case "Design", "디자인": return "type-design"
        default: return "type-default"
        }
    }
}
