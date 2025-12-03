import Vapor

struct JiraInspectCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "issueKeys", help: "Comma separated issue keys (e.g. KMA-5302,KMA-5765)")
        var issueKeys: String
    }

    var help: String {
        "Inspects specific Jira issues to debug parent fields."
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
        let keys = signature.issueKeys.split(separator: ",").map(String.init)
        
        let email = Environment.get("JIRA_EMAIL") ?? ""
        let token = Environment.get("JIRA_TOKEN") ?? ""
        
        if email.isEmpty || token.isEmpty {
            context.console.print("❌ Missing JIRA_EMAIL or JIRA_TOKEN")
            return
        }

        let apiClient = JiraAPIClient(client: app.client, email: email, token: token)
        
        let jql = "key in (\(keys.joined(separator: ",")))"
        let searchResult = try await apiClient.searchIssues(
            jql: jql,
            fields: ["summary", "status", "labels", "created", "resolutiondate", "fixVersions", "parent", "issuetype", "assignee"],
            maxResults: keys.count,
            nextPageToken: nil
        )
        
        for issue in searchResult.issues {
            context.console.print("\n--- Inspecting \(issue.key) ---")
            context.console.print("Summary: \(issue.fields.summary)")
            context.console.print("Type: \(issue.fields.issuetype.name) (Subtask: \(issue.fields.issuetype.subtask))")
            
            if let parent = issue.fields.parent {
                context.console.print("Parent: \(parent.key) - \(parent.fields.summary)")
                context.console.print("Parent Type: \(parent.fields.issuetype?.name ?? "Unknown")")
            } else {
                context.console.print("Parent: nil")
            }
            
            let versions = issue.fields.fixVersions?.map { $0.name } ?? []
            context.console.print("Versions: \(versions)")
        }
        
        // Simulate ReportGenerator Logic
        context.console.print("\n--- Simulating ReportGenerator Logic ---")
        
        // Convert to ProcessedIssue manually (simplified)
        let processedIssues = searchResult.issues.map { issue -> ProcessedIssue in
            let parent = issue.fields.parent
            return ProcessedIssue(
                key: issue.key,
                summary: issue.fields.summary,
                createdDate: Date(),
                labels: [],
                versions: [], // Empty for now, assuming inheritance happens later
                link: "",
                projectKey: "KMA",
                parentKey: parent?.key,
                parentSummary: parent?.fields.summary,
                parentType: parent?.fields.issuetype?.name,
                issueType: issue.fields.issuetype.name,
                isSubtask: issue.fields.issuetype.subtask,
                typeClass: "story",
                releaseDate: nil,
                assigneeAccountId: nil,
                assigneeName: nil,
                isMyTicket: true
            )
        }
        
        for issue in processedIssues {
            context.console.print("Issue: \(issue.key)")
            context.console.print("  ParentKey: \(issue.parentKey ?? "nil")")
            context.console.print("  ParentSummary: \(issue.parentSummary ?? "nil")")
            
            if let pKey = issue.parentKey, let _ = issue.parentSummary {
                context.console.print("  -> Has Parent! Should be grouped under \(pKey)")
            } else {
                context.console.print("  -> No Parent! Will be shown directly.")
            }
        }
    }
}
