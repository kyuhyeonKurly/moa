import Vapor
import Foundation

struct JiraExportCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "year", short: "y", help: "Year to export (e.g. 2024)")
        var year: String?
        
        @Option(name: "output", short: "o", help: "Output file path (e.g. ./exports/2024.md)")
        var output: String?
        
        @Flag(name: "skip-details", short: "s", help: "Skip fetching detailed info (faster, only titles)")
        var skipDetails: Bool
    }

    var help: String {
        "Export yearly tickets to markdown file with full details (description, attachments, comments)"
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let group = DispatchGroup()
        group.enter()
        
        Task {
            do {
                try await self.runAsync(using: context, signature: signature)
            } catch {
                context.console.print("❌ Error: \(error)")
            }
            group.leave()
        }
        
        group.wait()
    }
    
    func runAsync(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let targetYear = signature.year.flatMap { Int($0) } ?? Calendar.current.component(.year, from: Date())
        
        // Output path
        let outputPath = signature.output ?? "./exports/\(targetYear)_성과.md"
        
        // Load Credentials
        let email = Environment.get("JIRA_EMAIL") ?? ""
        let token = Environment.get("JIRA_TOKEN") ?? ""
        
        if email.isEmpty || token.isEmpty {
            context.console.print("❌ Missing JIRA_EMAIL or JIRA_TOKEN in environment variables.")
            return
        }
        
        let apiClient = JiraAPIClient(client: app.client, email: email, token: token)
        let jiraService = JiraService(apiClient: apiClient, logger: app.logger)
        
        context.console.print("📅 Fetching \(targetYear) tickets...")
        
        // 1. 티켓 목록 가져오기
        let issues = try await jiraService.fetchIssues(year: targetYear, assignee: nil, platform: nil)
        
        if issues.isEmpty {
            context.console.print("⚠️ No tickets found for year \(targetYear)")
            return
        }
        
        context.console.print("📦 Found \(issues.count) ticket(s)")
        
        // 2. 월별 그룹핑
        let calendar = Calendar.current
        let issuesByMonth = Dictionary(grouping: issues) { issue -> Int in
            let date = issue.releaseDate ?? issue.createdDate
            return calendar.component(.month, from: date)
        }
        
        // 3. 마크다운 생성 시작
        var markdown = ""
        
        // Header
        markdown += "# \(targetYear)년 Jira 성과 정리\n\n"
        markdown += "> Generated: \(formatCurrentDate())\n\n"
        
        // Summary
        markdown += "## 📊 요약\n\n"
        markdown += "- **총 티켓**: \(issues.count)건\n"
        
        // Type counts
        let typeCounts = Dictionary(grouping: issues) { $0.issueType }
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        for (type, count) in typeCounts {
            markdown += "- \(formatTypeLabel(type)): \(count)건\n"
        }
        markdown += "\n---\n\n"
        
        // 4. 월별 상세
        let monthNames = ["January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]
        
        var processedCount = 0
        let totalIssues = issues.count
        
        for month in 1...12 {
            guard let monthIssues = issuesByMonth[month], !monthIssues.isEmpty else { continue }
            
            // 부모로 롤업 (중복 제거)
            let displayIssues = rollupToParent(issues: monthIssues)
            
            markdown += "## \(monthNames[month - 1]) (\(displayIssues.count)건)\n\n"
            
            for issue in displayIssues.sorted(by: { $0.key < $1.key }) {
                processedCount += 1
                let progress = String(format: "%.0f%%", Double(processedCount) / Double(totalIssues) * 100)
                context.console.print("[\(progress)] Processing \(issue.key)...")
                
                markdown += "### \(formatTypeLabel(issue.issueType)) \(issue.key) - \(issue.summary)\n\n"
                
                // 상세 정보 가져오기 (옵션)
                if !signature.skipDetails {
                    do {
                        let detail = try await apiClient.fetchIssueDetail(issueKey: issue.key)
                        
                        // Meta
                        let assignee = detail.fields.assignee?.displayName ?? "미배정"
                        let status = detail.fields.status.name
                        markdown += "**Status:** \(status) | **Assignee:** \(assignee)\n\n"
                        markdown += "🔗 [Jira Link](https://kurly0521.atlassian.net/browse/\(issue.key))\n\n"
                        
                        // Description
                        if let desc = detail.fields.description {
                            let plainText = desc.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
                            if !plainText.isEmpty {
                                markdown += "#### Description\n\n"
                                markdown += plainText + "\n\n"
                            }
                        }
                        
                        // Attachments
                        if let attachments = detail.fields.attachment, !attachments.isEmpty {
                            markdown += "#### Attachments (\(attachments.count))\n\n"
                            for att in attachments {
                                let size = formatFileSize(att.size)
                                markdown += "- [\(att.filename)](\(att.content)) (\(size))\n"
                            }
                            markdown += "\n"
                        }
                        
                        // Comments
                        if let comments = detail.fields.comment, !comments.comments.isEmpty {
                            markdown += "#### Comments (\(comments.total))\n\n"
                            for comment in comments.comments {
                                let author = comment.author?.displayName ?? "Unknown"
                                let date = formatDate(comment.created)
                                let body = comment.body?.toPlainText().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                if !body.isEmpty {
                                    markdown += "> **@\(author)** (\(date)):\n> \(body.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
                                }
                            }
                        }
                        
                    } catch {
                        // 상세 정보 실패시 기본 정보만
                        let assignee = issue.assigneeName ?? "미배정"
                        markdown += "**Assignee:** \(assignee)\n\n"
                        markdown += "🔗 [Jira Link](\(issue.link))\n\n"
                    }
                    
                    // Rate limiting 방지
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1초
                } else {
                    // Skip details - 기본 정보만
                    let assignee = issue.assigneeName ?? "미배정"
                    markdown += "**Assignee:** \(assignee)\n\n"
                    markdown += "🔗 [Jira Link](\(issue.link))\n\n"
                }
                
                markdown += "---\n\n"
            }
        }
        
        // 5. 파일 저장
        let fileURL = URL(fileURLWithPath: outputPath)
        
        // 디렉토리 생성
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // 파일 쓰기
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        
        context.console.print("")
        context.console.print("✅ Export completed!")
        context.console.print("📄 File: \(outputPath)")
        context.console.print("📊 Total: \(issues.count) tickets")
    }
    
    // MARK: - Helpers
    
    private func rollupToParent(issues: [ProcessedIssue]) -> [ProcessedIssue] {
        var displayIssues: [String: ProcessedIssue] = [:]
        
        for issue in issues {
            let displayKey = issue.displayParentKey ?? issue.parentKey ?? issue.key
            
            if displayIssues[displayKey] == nil {
                if displayKey == issue.key {
                    displayIssues[displayKey] = issue
                } else {
                    let parentSummary = issue.displayParentSummary ?? issue.parentSummary ?? issue.summary
                    let parentType = issue.parentType ?? "Story"
                    displayIssues[displayKey] = ProcessedIssue(
                        key: displayKey,
                        summary: parentSummary,
                        createdDate: issue.createdDate,
                        labels: [],
                        versions: issue.versions,
                        link: "https://kurly0521.atlassian.net/browse/\(displayKey)",
                        projectKey: issue.projectKey,
                        parentKey: nil,
                        parentSummary: nil,
                        parentType: nil,
                        displayParentKey: nil,
                        displayParentSummary: nil,
                        issueType: parentType,
                        isSubtask: false,
                        typeClass: issue.typeClass,
                        releaseDate: issue.releaseDate,
                        assigneeAccountId: issue.assigneeAccountId,
                        assigneeName: issue.assigneeName,
                        isMyTicket: issue.isMyTicket
                    )
                }
            }
        }
        
        return Array(displayIssues.values)
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
        case "외부 요청", "Service Request with Approvals": return "[외부요청]"
        default: return "[\(issueType)]"
        }
    }
    
    private func formatDate(_ isoString: String) -> String {
        let parts = isoString.components(separatedBy: "T")
        guard parts.count >= 2 else { return isoString }
        return parts[0]
    }
    
    private func formatCurrentDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
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
