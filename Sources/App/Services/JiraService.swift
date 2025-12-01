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

        let uri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        
        var allIssues: [ProcessedIssue] = []
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
                throw Abort(.internalServerError, reason: "Jira API Error (\(response.status)): \(body)")
            }
            
            let searchResult = try response.content.decode(JiraSearchResponse.self)
            
            // Jira 날짜 포맷터 (밀리초 포함 대응)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            
            // 백업 포맷터 (밀리초 없는 경우)
            let backupDateFormatter = DateFormatter()
            backupDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            
            let pageIssues = searchResult.issues.map { issue -> ProcessedIssue in
                // resolutiondate 우선 사용, 없으면 created 사용
                let dateString = issue.fields.resolutiondate ?? issue.fields.created
                let date = dateFormatter.date(from: dateString) 
                    ?? backupDateFormatter.date(from: dateString) 
                    ?? ISO8601DateFormatter().date(from: dateString)
                    ?? Date() // 파싱 실패 시 현재 시간 (주의: 이로 인해 12월로 몰릴 수 있음)
                
                let projectKey = issue.key.split(separator: "-").first.map(String.init) ?? "UNKNOWN"
                
                var parentKey: String? = nil
                var parentSummary: String? = nil
                
                if let parent = issue.fields.parent {
                    parentKey = parent.key
                    parentSummary = parent.fields.summary
                }
                
                // 이슈 유형 이름 변경 (간소화)
                var issueType = issue.fields.issuetype.name
                if issueType == "Service Request with Approvals" {
                    issueType = "BI 요청"
                }
                
                let typeClass = self.getTypeClass(for: issueType)
                
                return ProcessedIssue(
                    key: issue.key,
                    summary: issue.fields.summary,
                    createdDate: date,
                    labels: issue.fields.labels,
                    versions: issue.fields.fixVersions?.map { $0.name } ?? [],
                    link: "\(self.apiBaseURL)/browse/\(issue.key)",
                    projectKey: projectKey,
                    parentKey: parentKey,
                    parentSummary: parentSummary,
                    issueType: issueType,
                    isSubtask: issue.fields.issuetype.subtask,
                    typeClass: typeClass
                )
            }
            
            allIssues.append(contentsOf: pageIssues)
            
            if let token = searchResult.nextPageToken, !token.isEmpty {
                nextPageToken = token
            } else {
                isFinished = true
            }
        }
        
        // [고도화] 재귀적 버전 추적
        allIssues = try await resolveVersionsRecursively(issues: allIssues, req: req)
        
        return allIssues
    }
    
    private func resolveVersionsRecursively(issues: [ProcessedIssue], req: Request) async throws -> [ProcessedIssue] {
        var issueMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0) })
        var versionMap = Dictionary(uniqueKeysWithValues: issues.map { ($0.key, $0.versions) })
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
                    parentMap[p.key] = p.parentKey
                }
            }
            
            var changed = false
            for key in unresolvedKeys {
                if let pKey = parentMap[key] ?? nil, let pVersions = versionMap[pKey], !pVersions.isEmpty {
                    versionMap[key] = pVersions
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
                    typeClass: issue.typeClass
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
            
            return ProcessedIssue(
                key: issue.key,
                summary: issue.fields.summary,
                createdDate: date,
                labels: issue.fields.labels,
                versions: issue.fields.fixVersions?.map { $0.name } ?? [],
                link: "\(self.apiBaseURL)/browse/\(issue.key)",
                projectKey: projectKey,
                parentKey: parentKey,
                parentSummary: parentSummary,
                issueType: issue.fields.issuetype.name,
                isSubtask: issue.fields.issuetype.subtask,
                typeClass: typeClass
            )
        } ?? []
    }
}
