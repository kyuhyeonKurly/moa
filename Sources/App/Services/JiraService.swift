import Vapor

struct JiraService {
    let client: Client
    let apiBaseURL = "https://kurly0521.atlassian.net"

    func fetchProjectVersions(projectKey: String, email: String, token: String) async throws -> [JiraProjectVersion] {
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        let uri = URI(string: "\(apiBaseURL)/rest/api/3/project/\(projectKey)/versions")
        
        let response = try await client.get(uri, headers: headers)
        
        guard response.status == .ok else {
            // 프로젝트 권한이 없거나 존재하지 않는 경우 빈 배열 반환
            return []
        }
        
        return try response.content.decode([JiraProjectVersion].self)
    }

    func fetchIssues(year: Int, assignee: String? = nil, email: String? = nil, token: String? = nil, req: Request) async throws -> [ProcessedIssue] {
        let finalEmail = email ?? Environment.get("JIRA_EMAIL") ?? ""
        let finalToken = token ?? Environment.get("JIRA_TOKEN") ?? ""
        
        if finalEmail.isEmpty || finalToken.isEmpty {
             throw Abort(.unauthorized, reason: "Jira Email or Token is missing.")
        }

        // 1. 먼저 사용자가 활동한 프로젝트를 찾기 위해 광범위한 검색 수행
        // (생성일 또는 해결일이 해당 연도인 이슈 검색)
        let assigneeClause = assignee != nil ? "assignee = \"\(assignee!)\"" : "assignee = currentUser()"
        let discoveryJql = """
        \(assigneeClause) 
        AND project not in (KQA) 
        AND (created >= \(year)-01-01 OR resolutiondate >= \(year)-01-01)
        """
        
        // ... 기존 로직 재사용을 위해 내부 함수로 분리하거나 여기서 직접 호출 ...
        // 여기서는 기존 fetch 로직을 활용하되, JQL을 보강하는 방식으로 진행
        
        // 2. 1차 검색 실행 (프로젝트 식별용)
        // 성능을 위해 maxResults를 적게 잡고 프로젝트만 뽑을 수도 있지만, 
        // 어차피 이슈 데이터가 필요하므로 전체를 가져옵니다.
        var allIssues = try await executeJqlSearch(jql: discoveryJql, email: finalEmail, token: finalToken, req: req)
        
        // 3. 식별된 프로젝트들의 2025년 릴리즈 버전 조회
        let projectKeys = Set(allIssues.map { $0.projectKey })
        var targetVersionIds: [String] = []
        
        for projectKey in projectKeys {
            let versions = try await fetchProjectVersions(projectKey: projectKey, email: finalEmail, token: finalToken)
            let targetVersions = versions.filter { version in
                guard version.released, let dateStr = version.releaseDate else { return false }
                return dateStr.hasPrefix("\(year)")
            }
            targetVersionIds.append(contentsOf: targetVersions.map { $0.id })
        }
        
        // 4. 해당 버전들에 포함된 이슈 추가 검색 (이미 찾은 이슈에 포함되지 않았을 수 있는 '오래된 생성일' 이슈들)
        if !targetVersionIds.isEmpty {
            // JQL 길이 제한 고려하여 청크로 나눔 (대략 50개씩)
            let chunkSize = 50
            let chunks = stride(from: 0, to: targetVersionIds.count, by: chunkSize).map {
                Array(targetVersionIds[$0..<min($0 + chunkSize, targetVersionIds.count)])
            }
            
            for chunk in chunks {
                let versionIdsStr = chunk.joined(separator: ",")
                let versionJql = """
                \(assigneeClause) 
                AND fixVersion in (\(versionIdsStr))
                AND key not in (\(allIssues.map { $0.key }.joined(separator: ",")))
                """
                
                // 이미 찾은 이슈는 제외하고 검색 (key not in)
                // 주의: key 리스트가 너무 길면 에러 날 수 있음. 
                // 차라리 중복 허용하고 나중에 필터링하는 게 안전함.
                
                let versionJqlSafe = """
                \(assigneeClause) 
                AND fixVersion in (\(versionIdsStr))
                """
                
                let versionIssues = try await executeJqlSearch(jql: versionJqlSafe, email: finalEmail, token: finalToken, req: req)
                
                // 중복 제거 후 병합
                let existingKeys = Set(allIssues.map { $0.key })
                let newIssues = versionIssues.filter { !existingKeys.contains($0.key) }
                allIssues.append(contentsOf: newIssues)
            }
        }
        
        // 5. 버전 정보 재매핑 (선택 사항: 이슈의 fixVersion 정보가 정확하다면 불필요)
        // 하지만 ReportGenerator에서 정확한 Release Date를 쓰려면 
        // 이슈 내의 fixVersion.releaseDate가 잘 들어있는지 확인해야 함.
        // (Jira API는 보통 이슈 조회 시 fixVersion 객체에 releaseDate를 포함해서 줌)
        
        return try await resolveVersionsRecursively(issues: allIssues, req: req)
    }
    
    // 기존 fetch 로직을 분리하여 재사용
    private func executeJqlSearch(jql: String, email: String, token: String, req: Request) async throws -> [ProcessedIssue] {
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        let uri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        
        var issues: [ProcessedIssue] = []
        var nextPageToken: String? = nil
        let maxResults = 100
        var isFinished = false
        
        while !isFinished {
            let currentToken = nextPageToken
            let response = try await client.post(uri, headers: headers) { req in
                let searchRequest = JiraSearchRequest(
                    jql: jql,
                    fields: ["summary", "status", "labels", "created", "resolutiondate", "fixVersions", "parent", "issuetype"],
                    maxResults: maxResults,
                    nextPageToken: currentToken
                )
                try req.content.encode(searchRequest)
            }
            
            guard response.status == .ok else {
                let body = response.body.map { String(buffer: $0) } ?? "No body"
                // 검색 실패 시 (예: JQL 오류) 빈 배열 반환하거나 에러 던짐
                // 여기서는 로그 남기고 중단
                print("JQL Search Failed: \(body)")
                throw Abort(.internalServerError, reason: "Jira API Error: \(body)")
            }
            
            let searchResult = try response.content.decode(JiraSearchResponse.self)
            
            // ... (기존 매핑 로직) ...
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
                    link: "\(self.apiBaseURL)/browse/\(issue.key)",
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
    
    private func resolveVersionsRecursively(issues: [ProcessedIssue], req: Request) async throws -> [ProcessedIssue] {
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
                let fetchedParents = try await fetchIssuesByKeys(keys: Array(missingParentKeys), req: req)
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
    
    private func fetchIssuesByKeys(keys: [String], req: Request) async throws -> [ProcessedIssue] {
        if keys.isEmpty { return [] }
        
        let jql = "key in (\(keys.joined(separator: ",")))"
        let email = Environment.get("JIRA_EMAIL") ?? ""
        let apiToken = Environment.get("JIRA_TOKEN") ?? ""
        let authString = "\(email):\(apiToken)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        let uri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        
        let response = try await client.post(uri, headers: headers) { req in
            let searchRequest = JiraSearchRequest(
                jql: jql,
                fields: ["summary", "status", "labels", "created", "fixVersions", "parent", "issuetype"],
                maxResults: keys.count,
                nextPageToken: nil
            )
            try req.content.encode(searchRequest)
        }
        
        guard response.status == .ok else { return [] }
        
        let searchResult = try? response.content.decode(JiraSearchResponse.self)
        let dateFormatter = ISO8601DateFormatter()
        let releaseDateFormatter = DateFormatter()
        releaseDateFormatter.dateFormat = "yyyy-MM-dd"
        
        return searchResult?.issues.map { issue in
            let date = dateFormatter.date(from: issue.fields.created) ?? Date()
            let projectKey = issue.key.split(separator: "-").first.map(String.init) ?? "UNKNOWN"
            
            var parentKey: String? = nil
            var parentSummary: String? = nil
            if let parent = issue.fields.parent {
                parentKey = parent.key
                parentSummary = parent.fields.summary
            }
            
            let typeClass = self.getTypeClass(for: issue.fields.issuetype.name)
            
            let releaseDateString = issue.fields.fixVersions?.compactMap { $0.releaseDate }.first
            let releaseDate = releaseDateString.flatMap { releaseDateFormatter.date(from: $0) }
            
            return ProcessedIssue(
                key: issue.key,
                summary: issue.fields.summary,
                createdDate: date,
                labels: issue.fields.labels,
                versions: issue.fields.fixVersions?.map { version in
                    let vDate = version.releaseDate.flatMap { releaseDateFormatter.date(from: $0) }
                    return VersionInfo(id: version.id, name: version.name, releaseDate: vDate)
                } ?? [],
                link: "\(self.apiBaseURL)/browse/\(issue.key)",
                projectKey: projectKey,
                parentKey: parentKey,
                parentSummary: parentSummary,
                issueType: issue.fields.issuetype.name,
                isSubtask: issue.fields.issuetype.subtask,
                typeClass: typeClass,
                releaseDate: releaseDate
            )
        } ?? []
    }
}
