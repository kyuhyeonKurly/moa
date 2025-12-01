import Vapor

struct JiraService {
    let client: Client
    let apiBaseURL = "https://kurly0521.atlassian.net"

    func fetchIssues(year: Int, assignee: String? = nil, email: String? = nil, token: String? = nil, req: Request) async throws -> [ProcessedIssue] {
        let assigneeClause = assignee != nil ? "assignee = \"\(assignee!)\"" : "assignee = currentUser()"
        
        // 사용자 검증 JQL 반영 (단순화)
        let jql = """
        \(assigneeClause) 
        AND project not in (KQA) 
        AND created >= \(year)-01-01 
        ORDER BY created DESC
        """
        
        let finalEmail = email ?? Environment.get("JIRA_EMAIL") ?? ""
        let finalToken = token ?? Environment.get("JIRA_TOKEN") ?? ""
        
        if finalEmail.isEmpty || finalToken.isEmpty {
             throw Abort(.unauthorized, reason: "Jira Email or Token is missing.")
        }

        let authString = "\(finalEmail):\(finalToken)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]

        // Jira API 변경 대응: /rest/api/3/search -> /rest/api/3/search/jql
        // 이 엔드포인트는 startAt 대신 nextPageToken을 사용합니다.
        let uri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        
        var allIssues: [ProcessedIssue] = []
        var nextPageToken: String? = nil
        let maxResults = 100
        var isFinished = false
        
        while !isFinished {
            let currentToken = nextPageToken // Capture for closure
            let response = try await client.post(uri, headers: headers) { req in
                let searchRequest = JiraSearchRequest(
                    jql: jql,
                    fields: ["summary", "status", "labels", "created", "fixVersions", "parent"],
                    maxResults: maxResults,
                    nextPageToken: currentToken
                )
                try req.content.encode(searchRequest)
            }
            
            guard response.status == .ok else {
                let body = response.body.map { String(buffer: $0) } ?? "No body"
                throw Abort(.internalServerError, reason: "Jira API Error (\(response.status)): \(body)")
            }
            
            let searchResult = try response.content.decode(JiraSearchResponse.self)
            
            let dateFormatter = ISO8601DateFormatter()
            
            let pageIssues = searchResult.issues.map { issue -> ProcessedIssue in
                let date = dateFormatter.date(from: issue.fields.created) ?? Date()
                
                // 프로젝트 키 추출 (KMA-123 -> KMA)
                let projectKey = issue.key.split(separator: "-").first.map(String.init) ?? "UNKNOWN"
                
                var parentKey: String? = nil
                var parentSummary: String? = nil
                
                if let parent = issue.fields.parent {
                    parentKey = parent.key
                    parentSummary = parent.fields.summary
                }
                
                return ProcessedIssue(
                    key: issue.key,
                    summary: issue.fields.summary,
                    createdDate: date,
                    labels: issue.fields.labels,
                    versions: issue.fields.fixVersions?.map { $0.name } ?? [],
                    link: "\(self.apiBaseURL)/browse/\(issue.key)",
                    projectKey: projectKey,
                    parentKey: parentKey,
                    parentSummary: parentSummary
                )
            }
            
            allIssues.append(contentsOf: pageIssues)
            
            // Pagination Logic (Cursor based)
            if let token = searchResult.nextPageToken, !token.isEmpty {
                nextPageToken = token
            } else {
                isFinished = true
            }
        }
        
        // [고도화] 재귀적 버전 추적 (Sub-task -> Story -> Epic)
        allIssues = try await resolveVersionsRecursively(issues: allIssues, req: req)
        
        return allIssues
    }
    
    // 재귀적으로 부모를 찾아 버전을 상속받는 로직
    private func resolveVersionsRecursively(issues: [ProcessedIssue], req: Request) async throws -> [ProcessedIssue] {
        var issueMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0) })
        var versionMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0.versions) })
        var parentMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0.parentKey) })
        
        // 최대 3단계 깊이까지 부모를 추적 (Sub-task -> Story -> Epic)
        for _ in 0..<3 {
            // 버전이 없고 부모가 있는 이슈들 식별
            let unresolvedKeys = issueMap.keys.filter { (versionMap[$0]?.isEmpty ?? true) && parentMap[$0] != nil }
            if unresolvedKeys.isEmpty { break }
            
            // 우리가 모르는 부모(아직 fetch 안된 이슈) 찾기
            let knownKeys = Set(issueMap.keys)
            let requiredParentKeys = Set(unresolvedKeys.compactMap { parentMap[$0] ?? nil }) // Optional Unwrapping
            let missingParentKeys = requiredParentKeys.subtracting(knownKeys)
            
            if !missingParentKeys.isEmpty {
                let fetchedParents = try await fetchIssuesByKeys(keys: Array(missingParentKeys), req: req)
                for p in fetchedParents {
                    issueMap[p.key] = p
                    versionMap[p.key] = p.versions
                    parentMap[p.key] = p.parentKey
                }
            }
            
            // 버전 전파 (부모 -> 자식)
            var changed = false
            for key in unresolvedKeys {
                // parentMap[key]는 String? 이므로 옵셔널 바인딩 필요
                if let pKey = parentMap[key] ?? nil, let pVersions = versionMap[pKey], !pVersions.isEmpty {
                    versionMap[key] = pVersions
                    changed = true
                }
            }
            
            if !changed && missingParentKeys.isEmpty { break }
        }
        
        // 원래 리스트에 버전 정보 업데이트하여 반환
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
                    parentSummary: issue.parentSummary
                )
            }
            return issue
        }
    }
    
    // 특정 키 목록으로 이슈 정보를 가져오는 헬퍼
    private func fetchIssuesByKeys(keys: [String], req: Request) async throws -> [ProcessedIssue] {
        guard !keys.isEmpty else { return [] }
        
        // JQL: key in (KMA-100, KMA-101, ...)
        let jql = "key in (\(keys.joined(separator: ",")))"
        let uri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        
        let email = Environment.get("JIRA_EMAIL") ?? ""
        let apiToken = Environment.get("JIRA_TOKEN") ?? ""
        let authString = "\(email):\(apiToken)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        let response = try await client.post(uri, headers: headers) { req in
            let searchRequest = JiraSearchRequest(
                jql: jql,
                fields: ["summary", "status", "labels", "created", "fixVersions", "parent"],
                maxResults: 100,
                nextPageToken: nil
            )
            try req.content.encode(searchRequest)
        }
        
        guard response.status == .ok else { return [] }
        let searchResult = try? response.content.decode(JiraSearchResponse.self)
        
        return searchResult?.issues.map { issue in
            let projectKey = issue.key.split(separator: "-").first.map(String.init) ?? "UNKNOWN"
            var parentKey: String? = nil
            var parentSummary: String? = nil
            if let parent = issue.fields.parent {
                parentKey = parent.key
                parentSummary = parent.fields.summary
            }
            
            return ProcessedIssue(
                key: issue.key,
                summary: issue.fields.summary,
                createdDate: Date(), // 날짜는 중요하지 않음
                labels: issue.fields.labels,
                versions: issue.fields.fixVersions?.map { $0.name } ?? [],
                link: "\(self.apiBaseURL)/browse/\(issue.key)",
                projectKey: projectKey,
                parentKey: parentKey,
                parentSummary: parentSummary
            )
        } ?? []
    }
}
