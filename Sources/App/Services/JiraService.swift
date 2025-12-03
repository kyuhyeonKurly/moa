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
        let assigneeClause = assignee != nil ? "assignee = \"\(assignee!)\"" : "assignee = currentUser()"
        let discoveryJql = """
        \(assigneeClause) 
        AND project not in (KQA) 
        AND (created >= \(year)-01-01 OR resolutiondate >= \(year)-01-01)
        """
        
        // 2. 1차 검색 실행 (프로젝트 식별용)
        let discoveryIssues = try await executeJqlSearch(jql: discoveryJql, platform: platform)
        
        // 3. 식별된 프로젝트들의 해당 연도 릴리즈 버전 조회
        var projectKeys = Set(discoveryIssues.map { $0.projectKey })
        if projectKeys.isEmpty {
             projectKeys.insert("KMA")
        }
        var targetVersionIds: [String] = []
        
        for projectKey in projectKeys {
            let versions = try await apiClient.fetchProjectVersions(projectKey: projectKey)
            let targetVersions = versions.filter { version in
                guard version.released, let dateStr = version.releaseDate else { return false }
                return dateStr.hasPrefix("\(year)")
            }
            targetVersionIds.append(contentsOf: targetVersions.map { $0.id })
        }
        
        // 4. 해당 버전들에 포함된 이슈 추가 검색 (2-Pass Strategy)
        var finalIssues: [ProcessedIssue] = []
        
        if !targetVersionIds.isEmpty {
            let chunkSize = 30
            let chunks = stride(from: 0, to: targetVersionIds.count, by: chunkSize).map {
                Array(targetVersionIds[$0..<min($0 + chunkSize, targetVersionIds.count)])
            }
            
            for chunk in chunks {
                let versionIdsStr = chunk.joined(separator: ",")
                
                // Pass 1: 버전 내 *모든* 이슈 조회
                let versionJql = "fixVersion in (\(versionIdsStr))"
                let versionIssues = try await executeJqlSearch(jql: versionJql, platform: platform)
                
                // Pass 2: 내 하위 작업 조회
                let versionIssueKeys = versionIssues.map { $0.key }
                var mySubtasksMap: [String: [ProcessedIssue]] = [:]
                
                if !versionIssueKeys.isEmpty {
                    let keyChunkSize = 50
                    let keyChunks = stride(from: 0, to: versionIssueKeys.count, by: keyChunkSize).map {
                        Array(versionIssueKeys[$0..<min($0 + keyChunkSize, versionIssueKeys.count)])
                    }
                    
                    for keyChunk in keyChunks {
                        let keysStr = keyChunk.joined(separator: ",")
                        // assigneeClause 사용 (currentUser() 또는 특정 사용자)
                        let subtaskJql = "parent in (\(keysStr)) AND \(assigneeClause)"
                        
                        let subtasks = try await executeJqlSearch(jql: subtaskJql, platform: platform)
                        for sub in subtasks {
                            if let pKey = sub.parentKey {
                                mySubtasksMap[pKey, default: []].append(sub)
                            }
                        }
                    }
                }
                
                // 필터링 및 병합
                for issue in versionIssues {
                    let isAssignedToMe: Bool
                    if let targetAssignee = assignee {
                        // 이름으로 비교 (정확하지 않을 수 있음)
                        isAssignedToMe = issue.assigneeName == targetAssignee
                    } else {
                        // AccountId로 비교 (정확함)
                        isAssignedToMe = (myAccountId != nil && issue.assigneeAccountId == myAccountId)
                    }
                    
                    let hasMySubtasks = (mySubtasksMap[issue.key]?.count ?? 0) > 0
                    
                    if isAssignedToMe || hasMySubtasks {
                        var processedIssue = issue
                        processedIssue.isMyTicket = isAssignedToMe
                        finalIssues.append(processedIssue)
                    }
                }
            }
        }
        
        // 중복 제거
        let uniqueIssues = Array(Set(finalIssues.map { $0.key })).compactMap { key in
            finalIssues.first { $0.key == key }
        }
        
        // 5. 버전 정보 재매핑
        // resolveVersionsRecursively에서 isMyTicket 정보가 유실되지 않도록 주의해야 함
        // 하지만 resolveVersionsRecursively는 새로운 ProcessedIssue를 생성하지 않고 기존 것을 매핑하거나 부모를 추가함.
        // 부모를 추가할 때 부모의 isMyTicket은 기본값(false)일 것임. (부모가 내 것이 아닐 수 있으므로 OK)
        // 기존 이슈는 그대로 유지되므로 isMyTicket도 유지됨.
        return try await resolveVersionsRecursively(issues: uniqueIssues, platform: platform)
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
                
                var issueType = issue.fields.issuetype.name
                if issueType == "Service Request with Approvals" { issueType = "BI 요청" }
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
