import Vapor

struct JiraVersionDetailCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "projectKey", help: "The Project Key to test (e.g. KMA)")
        var projectKey: String
        
        @Option(name: "version", short: "v", help: "The Version ID to fetch issues for")
        var versionId: String?
        
        @Flag(name: "me", short: "m", help: "Filter by current user (assignee = currentUser())")
        var filterByMe: Bool
    }

    var help: String {
        "Fetches issues for a specific project version from Jira, optionally filtering by current user."
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let group = DispatchGroup()
        group.enter()
        
        Task {
            do {
                try await runAsync(using: context, signature: signature)
            } catch {
                context.console.print("❌ Error: \(error)")
            }
            group.leave()
        }
        
        group.wait()
    }

    func runAsync(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let projectKey = signature.projectKey
        
        guard let versionId = signature.versionId else {
            context.console.print("❌ Error: --version <id> is required for this command.")
            return
        }
        
        context.console.print("🚀 Fetching Issues for Project: \(projectKey), Version ID: \(versionId)")
        
        // Load Credentials
        let email = Environment.get("JIRA_EMAIL") ?? ""
        let token = Environment.get("JIRA_TOKEN") ?? ""
        
        if email.isEmpty || token.isEmpty {
            context.console.print("❌ Missing JIRA_EMAIL or JIRA_TOKEN in environment variables.")
            return
        }
        
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        let apiBaseURL = "https://kurly0521.atlassian.net"
        
        // 0. Fetch Current User Info (if filtering enabled)
        var myAccountId: String?
        
        if signature.filterByMe {
            context.console.print("👤 Fetching current user info...")
            let myselfUri = URI(string: "\(apiBaseURL)/rest/api/3/myself")
            let myselfResponse = try await app.client.get(myselfUri, headers: headers)
            
            struct Myself: Decodable {
                let accountId: String
                let displayName: String
            }
            
            if myselfResponse.status == .ok,
               let myself = try? myselfResponse.content.decode(Myself.self) {
                myAccountId = myself.accountId
                context.console.print("   👉 Logged in as: \(myself.displayName) (\(myself.accountId))")
            } else {
                context.console.print("⚠️ Failed to fetch user info. Filtering might be inaccurate.")
            }
        }
        
        // Search Issues (JQL)
        let jql = "project = \(projectKey) AND fixVersion = \(versionId)"
        context.console.print("🔎 Executing JQL: \(jql)")
        
        let searchUri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        
        struct JQLRequest: Content {
            let jql: String
            let fields: [String]
            let maxResults: Int
        }
        
        let requestBody = JQLRequest(
            jql: jql,
            fields: ["summary", "status", "issuetype", "assignee", "subtasks", "parent"],
            maxResults: 100
        )
        
        let searchResponse = try await app.client.post(searchUri, headers: headers) { req in
            try req.content.encode(requestBody)
        }
        
        guard searchResponse.status == .ok else {
            context.console.print("❌ Failed to search issues: \(searchResponse.status)")
            if let body = searchResponse.body {
                context.console.print(String(buffer: body))
            }
            return
        }
        
        // Define minimal models for decoding response
        struct MinimalIssue: Decodable {
            let key: String
            let fields: Fields
            
            struct Fields: Decodable {
                let summary: String
                let status: Status
                let issuetype: IssueType
                let assignee: Assignee?
                let parent: Parent?
                
                struct Status: Decodable { let name: String }
                struct IssueType: Decodable { let name: String }
                struct Assignee: Decodable { 
                    let displayName: String 
                    let accountId: String?
                }
                
                struct Parent: Decodable {
                    let key: String
                    let fields: ParentFields
                }
                struct ParentFields: Decodable {
                    let summary: String
                }
            }
        }
        
        struct SearchResult: Decodable {
            let issues: [MinimalIssue]
            let total: Int?
        }
        
        let result = try searchResponse.content.decode(SearchResult.self)
        let versionIssues = result.issues
        let totalCount = result.total ?? versionIssues.count
        context.console.print("✅ Found \(totalCount) issues in version.")
        
        if !signature.filterByMe {
            context.console.print("\n📋 Showing all issues (No user filter applied)")
            for issue in versionIssues {
                let assignee = issue.fields.assignee?.displayName ?? "Unassigned"
                context.console.print("   - [\(issue.key)] \(issue.fields.summary)")
                context.console.print("     Status: \(issue.fields.status.name) | Type: \(issue.fields.issuetype.name) | Assignee: \(assignee)")
            }
            return
        }
        
        context.console.print("\n🎯 Filtering results for current user...")
        
        // 2-Pass Strategy:
        // 1. Identify issues in version that are NOT assigned to me (Potential Parents).
        // 2. Fetch all subtasks assigned to me that belong to ANY issue in this version.
        
        let versionIssueKeys = versionIssues.map { $0.key }
        var mySubtasksMap: [String: [MinimalIssue]] = [:]
        
        if !versionIssueKeys.isEmpty {
            // Chunk keys to avoid JQL length limits (e.g., 50 keys per batch)
            let chunkSize = 50
            let chunks = stride(from: 0, to: versionIssueKeys.count, by: chunkSize).map {
                Array(versionIssueKeys[$0..<min($0 + chunkSize, versionIssueKeys.count)])
            }
            
            for chunk in chunks {
                let keysStr = chunk.joined(separator: ",")
                // JQL: parent in (...) AND assignee = currentUser()
                let subtaskJql = "parent in (\(keysStr)) AND assignee = currentUser()"
                
                let subtaskReqBody = JQLRequest(
                    jql: subtaskJql,
                    fields: ["summary", "status", "issuetype", "assignee", "parent"],
                    maxResults: 100
                )
                
                let subResponse = try await app.client.post(searchUri, headers: headers) { req in
                    try req.content.encode(subtaskReqBody)
                }
                
                if subResponse.status == .ok,
                   let subResult = try? subResponse.content.decode(SearchResult.self) {
                    for sub in subResult.issues {
                        if let parentKey = sub.fields.parent?.key {
                            mySubtasksMap[parentKey, default: []].append(sub)
                        }
                    }
                }
            }
        }
        
        var foundCount = 0
        
        for issue in versionIssues {
            let assigneeAccountId = issue.fields.assignee?.accountId
            let assigneeName = issue.fields.assignee?.displayName ?? "Unassigned"
            
            // Check if assigned to me using Account ID
            let isAssignedToMe = (myAccountId != nil && assigneeAccountId == myAccountId)
            
            let myRelatedSubtasks = mySubtasksMap[issue.key] ?? []
            let hasRelatedSubtasks = !myRelatedSubtasks.isEmpty
            
            if isAssignedToMe {
                foundCount += 1
                context.console.print("   ✅ [Direct] [\(issue.key)] \(issue.fields.summary)")
                context.console.print("     Status: \(issue.fields.status.name) | Type: \(issue.fields.issuetype.name) | Assignee: \(assigneeName)")
                
                if hasRelatedSubtasks {
                    for sub in myRelatedSubtasks {
                        context.console.print("      ↳ [My Subtask] [\(sub.key)] \(sub.fields.summary) (\(sub.fields.status.name))")
                    }
                }
                
            } else if hasRelatedSubtasks {
                foundCount += 1
                context.console.print("   🔗 [Related] [\(issue.key)] \(issue.fields.summary)")
                context.console.print("     Status: \(issue.fields.status.name) | Type: \(issue.fields.issuetype.name) | Assignee: \(assigneeName)")
                for sub in myRelatedSubtasks {
                    context.console.print("      ↳ [My Subtask] [\(sub.key)] \(sub.fields.summary) (\(sub.fields.status.name))")
                }
            }
        }
        
        context.console.print("\n🏁 Total related issues found: \(foundCount)")
    }
}
