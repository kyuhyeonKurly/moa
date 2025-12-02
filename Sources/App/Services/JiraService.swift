import Vapor

struct JiraService {
    let apiClient: JiraAPIClient
    
    func fetchIssues(year: Int, assignee: String? = nil) async throws -> [ProcessedIssue] {
        // 1. 먼저 사용자가 활동한 프로젝트를 찾기 위해 광범위한 검색 수행
        let assigneeClause = assignee != nil ? "assignee = \"\(assignee!)\"" : "assignee = currentUser()"
        let discoveryJql = """
        \(assigneeClause) 
        AND project not in (KQA) 
        AND (created >= \(year)-01-01 OR resolutiondate >= \(year)-01-01)
        """
        
        // 2. 1차 검색 실행 (프로젝트 식별용)
        var allIssues = try await executeJqlSearch(jql: discoveryJql)
        
        // 3. 식별된 프로젝트들의 해당 연도 릴리즈 버전 조회
        let projectKeys = Set(allIssues.map { $0.projectKey })
        var targetVersionIds: [String] = []
        
        for projectKey in projectKeys {
            let versions = try await apiClient.fetchProjectVersions(projectKey: projectKey)
            let targetVersions = versions.filter { version in
                guard version.released, let dateStr = version.releaseDate else { return false }
                return dateStr.hasPrefix("\(year)")
            }
            targetVersionIds.append(contentsOf: targetVersions.map { $0.id })
        }
        
        // 4. 해당 버전들에 포함된 이슈 추가 검색
        if !targetVersionIds.isEmpty {
            let chunkSize = 50
            let chunks = stride(from: 0, to: targetVersionIds.count, by: chunkSize).map {
                Array(targetVersionIds[$0..<min($0 + chunkSize, targetVersionIds.count)])
            }
            
            for chunk in chunks {
                let versionIdsStr = chunk.joined(separator: ",")
                let versionJqlSafe = """
                \(assigneeClause) 
                AND fixVersion in (\(versionIdsStr))
                """
                
                let versionIssues = try await executeJqlSearch(jql: versionJqlSafe)
                
                // 중복 제거 후 병합
                let existingKeys = Set(allIssues.map { $0.key })
                let newIssues = versionIssues.filter { !existingKeys.contains($0.key) }
                allIssues.append(contentsOf: newIssues)
            }
        }
        
        // 5. 버전 정보 재매핑
        return try await resolveVersionsRecursively(issues: allIssues)
    }
    
    private func executeJqlSearch(jql: String) async throws -> [ProcessedIssue] {
        var issues: [ProcessedIssue] = []
        var nextPageToken: String? = nil
        let maxResults = 100
        var isFinished = false
        
        while !isFinished {
            let searchResult = try await apiClient.searchIssues(
                jql: jql,
                fields: ["summary", "status", "labels", "created", "resolutiondate", "fixVersions", "parent", "issuetype"],
                maxResults: maxResults,
                nextPageToken: nextPageToken
            )
            
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
                
                let releaseDateString = issue.fields.fixVersions?.compactMap { $0.releaseDate }.first
                let releaseDate = releaseDateString.flatMap { releaseDateFormatter.date(from: $0) }
                
                let projectKey = issue.key.split(separator: "-").first.map(String.init) ?? "UNKNOWN"
                
                var parentKey: String? = nil
                var parentSummary: String? = nil
                if let parent = issue.fields.parent {
                    parentKey = parent.key
                    parentSummary = parent.fields.summary
                }
                
                var issueType = issue.fields.issuetype.name
                if issueType == "Service Request with Approvals" { issueType = "BI 요청" }
                let typeClass = self.getTypeClass(for: issueType)
                
                return ProcessedIssue(
                    key: issue.key,
                    summary: issue.fields.summary,
                    createdDate: date,
                    labels: issue.fields.labels,
                    versions: issue.fields.fixVersions?.map { version in
                        let vDate = version.releaseDate.flatMap { releaseDateFormatter.date(from: $0) }
                        return VersionInfo(id: version.id, name: version.name, releaseDate: vDate)
                    } ?? [],
                    link: "\(apiClient.apiBaseURL)/browse/\(issue.key)",
                    projectKey: projectKey,
                    parentKey: parentKey,
                    parentSummary: parentSummary,
                    issueType: issueType,
                    isSubtask: issue.fields.issuetype.subtask,
                    typeClass: typeClass,
                    releaseDate: releaseDate
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
    
    private func resolveVersionsRecursively(issues: [ProcessedIssue]) async throws -> [ProcessedIssue] {
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
                let fetchedParents = try await fetchIssuesByKeys(keys: Array(missingParentKeys))
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
                    releaseDate: releaseDateMap[issue.key] ?? nil
                )
            }
            return issue
        }
    }
    
    private func fetchIssuesByKeys(keys: [String]) async throws -> [ProcessedIssue] {
        if keys.isEmpty { return [] }
        let jql = "key in (\(keys.joined(separator: ",")))"
        return try await executeJqlSearch(jql: jql)
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
