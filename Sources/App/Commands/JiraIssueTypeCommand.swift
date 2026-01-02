import Vapor
import Foundation

/// 여러 이슈의 타입을 조회하여 태깅
/// Usage: swift run App jira-issue-type KMA-4771,KMA-4768,KMA-4817
struct JiraIssueTypeCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "keys", help: "Comma-separated issue keys")
        var keys: String
    }
    
    var help: String {
        "Fetch issue types for multiple issues and tag them"
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        guard let email = Environment.get("JIRA_EMAIL"),
              let token = Environment.get("JIRA_TOKEN") else {
            context.console.error("❌ JIRA_EMAIL and JIRA_TOKEN must be set in .env")
            return
        }
        
        let app = context.application
        let client = JiraAPIClient(client: app.client, email: email, token: token)
        
        let keys = signature.keys.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        
        context.console.print("🔍 Fetching \(keys.count) issues...")
        
        let group = DispatchGroup()
        
        final class ResultBox: @unchecked Sendable {
            var results: [(key: String, type: String, summary: String)] = []
            var errorMessage: String?
        }
        let box = ResultBox()
        
        group.enter()
        Task { @MainActor in
            do {
                // 한 번의 JQL로 모든 이슈 조회
                let keysJql = keys.joined(separator: ", ")
                let jql = "key IN (\(keysJql))"
                context.console.print("JQL: \(jql.prefix(100))...")
                
                var allIssues: [JiraIssue] = []
                var nextPageToken: String? = nil
                
                repeat {
                    let response = try await client.searchIssues(
                        jql: jql,
                        fields: ["summary", "issuetype"],
                        maxResults: 100,
                        nextPageToken: nextPageToken
                    )
                    allIssues.append(contentsOf: response.issues)
                    nextPageToken = response.nextPageToken
                } while nextPageToken != nil
                
                context.console.print("Found: \(allIssues.count) issues")
                
                // 결과 매핑
                let issueMap = Dictionary(uniqueKeysWithValues: allIssues.map { ($0.key, $0) })
                
                for key in keys {
                    if let issue = issueMap[key] {
                        let typeName = issue.fields.issuetype.name
                        let summary = issue.fields.summary
                        box.results.append((key: key, type: typeName, summary: summary))
                    } else {
                        box.results.append((key: key, type: "NOT_FOUND", summary: ""))
                    }
                }
            } catch {
                box.errorMessage = error.localizedDescription
            }
            group.leave()
        }
        
        group.wait()
        
        if let error = box.errorMessage {
            context.console.error("❌ Error: \(error)")
            return
        }
        
        // 타입별 이모지 매핑
        let typeEmoji: [String: String] = [
            "에픽": "🟣",
            "Epic": "🟣",
            "스토리": "🟢",
            "Story": "🟢",
            "개선": "🟡",
            "Improvement": "🟡",
            "버그": "🔴",
            "Bug": "🔴",
            "작업": "🔵",
            "Task": "🔵",
            "하위 작업": "⚪",
            "Sub-task": "⚪",
            "디자인": "🟠",
            "Design": "🟠"
        ]
        
        context.console.print("\n📋 Results:\n")
        
        for result in box.results {
            let emoji = typeEmoji[result.type] ?? "⬜"
            let shortType = result.type
                .replacingOccurrences(of: "하위 작업", with: "하위")
                .replacingOccurrences(of: "Sub-task", with: "하위")
            context.console.print("\(emoji)[\(shortType)] [\(result.key)](https://kurly0521.atlassian.net/browse/\(result.key)) \(result.summary)")
        }
        
        context.console.print("\n✅ Done!")
    }
}
