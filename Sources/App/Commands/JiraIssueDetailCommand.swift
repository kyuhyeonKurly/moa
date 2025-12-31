import Vapor

struct JiraIssueDetailCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "issue", short: "i", help: "Issue key (e.g. KMA-4564)")
        var issueKey: String?
    }

    var help: String {
        "Fetch and display detailed issue information including description, attachments, and comments."
    }

    func run(using context: CommandContext, signature: Signature) throws {
        guard let issueKey = signature.issueKey else {
            context.console.print("❌ Please provide an issue key with --issue or -i")
            context.console.print("   Example: swift run App jira-detail --issue KMA-4564")
            return
        }
        
        let group = DispatchGroup()
        group.enter()
        
        Task {
            do {
                try await self.runAsync(using: context, issueKey: issueKey)
            } catch {
                context.console.print("❌ Error: \(error)")
            }
            group.leave()
        }
        
        group.wait()
    }
    
    func runAsync(using context: CommandContext, issueKey: String) async throws {
        let app = context.application
        
        // Load Credentials
        let email = Environment.get("JIRA_EMAIL") ?? ""
        let token = Environment.get("JIRA_TOKEN") ?? ""
        
        if email.isEmpty || token.isEmpty {
            context.console.print("❌ Missing JIRA_EMAIL or JIRA_TOKEN in environment variables.")
            return
        }
        
        let apiClient = JiraAPIClient(client: app.client, email: email, token: token)
        
        context.console.print("🔍 Fetching issue: \(issueKey)...")
        context.console.print("")
        
        let issue = try await apiClient.fetchIssueDetail(issueKey: issueKey)
        
        // MARK: - Header
        printSeparator(context: context, char: "=")
        context.console.print("📋 \(issue.key) - \(issue.fields.summary)")
        printSeparator(context: context, char: "=")
        
        // MARK: - Meta Info
        context.console.print("")
        let typeLabel = formatTypeLabel(issue.fields.issuetype.name)
        let assignee = issue.fields.assignee?.displayName ?? "미배정"
        let status = issue.fields.status.name
        
        context.console.print("🏷️  Type: \(typeLabel)")
        context.console.print("👤 Assignee: \(assignee)")
        context.console.print("📊 Status: \(status)")
        context.console.print("📅 Created: \(formatDate(issue.fields.created))")
        if let updated = issue.fields.updated {
            context.console.print("🔄 Updated: \(formatDate(updated))")
        }
        context.console.print("🔗 Link: https://kurly0521.atlassian.net/browse/\(issue.key)")
        
        // MARK: - Description
        context.console.print("")
        printSeparator(context: context, char: "-")
        context.console.print("📝 Description")
        printSeparator(context: context, char: "-")
        
        if let description = issue.fields.description {
            let plainText = description.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
            if plainText.isEmpty {
                context.console.print("(내용 없음)")
            } else {
                context.console.print(plainText)
            }
        } else {
            context.console.print("(내용 없음)")
        }
        
        // MARK: - Attachments
        context.console.print("")
        printSeparator(context: context, char: "-")
        let attachmentCount = issue.fields.attachment?.count ?? 0
        context.console.print("📎 Attachments (\(attachmentCount))")
        printSeparator(context: context, char: "-")
        
        if let attachments = issue.fields.attachment, !attachments.isEmpty {
            for (index, attachment) in attachments.enumerated() {
                let sizeStr = formatFileSize(attachment.size)
                let author = attachment.author?.displayName ?? "Unknown"
                context.console.print("\(index + 1). \(attachment.filename) (\(sizeStr)) - @\(author)")
                context.console.print("   📥 \(attachment.content)")
            }
        } else {
            context.console.print("(첨부파일 없음)")
        }
        
        // MARK: - Comments
        context.console.print("")
        printSeparator(context: context, char: "-")
        let commentCount = issue.fields.comment?.total ?? 0
        context.console.print("💬 Comments (\(commentCount))")
        printSeparator(context: context, char: "-")
        
        if let commentWrapper = issue.fields.comment, !commentWrapper.comments.isEmpty {
            for (index, comment) in commentWrapper.comments.enumerated() {
                let author = comment.author?.displayName ?? "Unknown"
                let date = formatDate(comment.created)
                let body = comment.body?.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines) ?? "(내용 없음)"
                
                context.console.print("")
                context.console.print("[\(index + 1)] @\(author) - \(date)")
                context.console.print(body)
            }
        } else {
            context.console.print("(댓글 없음)")
        }
        
        context.console.print("")
        printSeparator(context: context, char: "=")
    }
    
    // MARK: - Helpers
    
    private func printSeparator(context: CommandContext, char: Character) {
        context.console.print(String(repeating: char, count: 60))
    }
    
    private func formatTypeLabel(_ issueType: String) -> String {
        switch issueType {
        case "Epic", "에픽": return "[에픽]"
        case "Story", "스토리": return "[스토리]"
        case "Task", "작업": return "[작업]"
        case "Bug", "버그": return "[버그]"
        case "Improvement", "개선": return "[개선]"
        case "Design", "디자인": return "[디자인]"
        case "Sub-task", "하위 작업": return "[하위작업]"
        case "외부 요청": return "[외부요청]"
        default: return "[\(issueType)]"
        }
    }
    
    private func formatDate(_ isoString: String) -> String {
        // "2024-01-15T10:30:00.000+0900" -> "2024-01-15 10:30"
        let parts = isoString.components(separatedBy: "T")
        guard parts.count >= 2 else { return isoString }
        let datePart = parts[0]
        let timePart = String(parts[1].prefix(5))
        return "\(datePart) \(timePart)"
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}
