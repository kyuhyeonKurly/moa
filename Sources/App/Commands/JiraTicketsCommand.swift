import Vapor

struct JiraTicketsCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "year", short: "y", help: "Filter by release year (e.g. 2025)")
        var year: String?
        
        @Option(name: "assignee", short: "a", help: "Filter by assignee email (default: current user)")
        var assignee: String?
        
        @Option(name: "platform", short: "p", help: "Filter by platform (e.g. KMA, KMC)")
        var platform: String?
        
        @Flag(name: "group", short: "g", help: "Group tickets by version")
        var groupByVersion: Bool
        
        @Flag(name: "typed", short: "t", help: "Show with issue type prefix [에픽], [스토리], etc.")
        var showType: Bool
    }

    var help: String {
        "Extracts ticket keys and titles (same as web /moa/collect). Output: KEY - Title"
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
        
        // 웹과 동일한 로직: JiraService.fetchIssues() 사용
        let issues = try await jiraService.fetchIssues(
            year: targetYear, 
            assignee: signature.assignee, 
            platform: signature.platform
        )
        
        if issues.isEmpty {
            context.console.print("⚠️ No tickets found for year \(targetYear)")
            return
        }
        
        // 웹과 동일한 로직: ReportGenerator.generateContext() 사용
        let reportContext = ReportGenerator.generateContext(
            issues: issues, 
            year: targetYear, 
            spaceKey: nil, 
            platform: signature.platform
        )
        
        context.console.print("📦 Found \(reportContext.totalCount) ticket(s)\n")
        
        if signature.groupByVersion {
            // 버전별 보기
            printVersionGrouped(context: context, reportContext: reportContext, showType: signature.showType)
        } else if signature.showType {
            // 월별 + 타입 표시 보기
            printMonthlyWithType(context: context, issues: issues)
        } else {
            // 월별 보기 (기본)
            printMonthlyGrid(context: context, reportContext: reportContext)
        }
        
        context.console.print("\n✅ Total: \(reportContext.totalCount) tickets")
    }
    
    // MARK: - 월별 보기 (기본)
    private func printMonthlyGrid(context: CommandContext, reportContext: ReportContext) {
        for monthItem in reportContext.monthlyGrid {
            if monthItem.issues.isEmpty { continue }
            
            context.console.print("### \(monthItem.monthName) (\(monthItem.issues.count)건)")
            context.console.print("")
            
            for issue in monthItem.issues {
                let assignee = issue.assigneeName ?? "미배정"
                context.console.print("\(issue.key) - \(issue.summary) [@\(assignee)]")
            }
            context.console.print("")
        }
    }
    
    // MARK: - 월별 + 타입 표시 보기
    private func printMonthlyWithType(context: CommandContext, issues: [ProcessedIssue]) {
        let calendar = Calendar.current
        let monthNames = ["January", "February", "March", "April", "May", "June", 
                          "July", "August", "September", "October", "November", "December"]
        
        // 월별 그룹핑 (releaseDate 또는 createdDate 기준)
        let issuesByMonth = Dictionary(grouping: issues) { issue -> Int in
            let date = issue.releaseDate ?? issue.createdDate
            return calendar.component(.month, from: date)
        }
        
        for month in 1...12 {
            guard let monthIssues = issuesByMonth[month], !monthIssues.isEmpty else { continue }
            
            // 에픽/스토리 등 최상위 티켓만 표시 (서브태스크는 부모로 롤업)
            var displayIssues: [String: ProcessedIssue] = [:]
            
            for issue in monthIssues {
                // 부모가 있으면 부모 키 사용, 없으면 자기 자신
                let displayKey = issue.displayParentKey ?? issue.parentKey ?? issue.key
                
                // 이미 있으면 스킵 (부모 티켓이 직접 있을 수 있음)
                if displayIssues[displayKey] == nil {
                    if displayKey == issue.key {
                        // 자기 자신이 루트
                        displayIssues[displayKey] = issue
                    } else {
                        // 부모 정보로 가상 티켓 생성
                        let parentSummary = issue.displayParentSummary ?? issue.parentSummary ?? issue.summary
                        let parentType = issue.parentType ?? "Story"
                        displayIssues[displayKey] = ProcessedIssue(
                            key: displayKey,
                            summary: parentSummary,
                            createdDate: issue.createdDate,
                            labels: [],
                            versions: issue.versions,
                            link: issue.link,
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
            
            let sortedIssues = displayIssues.values.sorted { $0.key < $1.key }
            
            context.console.print("### \(monthNames[month - 1]) (\(sortedIssues.count)건)")
            context.console.print("")
            
            for issue in sortedIssues {
                let typeLabel = formatTypeLabel(issue.issueType)
                let assignee = issue.assigneeName ?? "미배정"
                context.console.print("\(typeLabel) \(issue.key) - \(issue.summary) [@\(assignee)]")
            }
            context.console.print("")
        }
    }
    
    // MARK: - 버전별 보기
    private func printVersionGrouped(context: CommandContext, reportContext: ReportContext, showType: Bool) {
        for project in reportContext.versionProjects {
            context.console.print("## 📁 \(project.name)")
            context.console.print("")
            
            for group in project.groups {
                context.console.print("### \(group.title) (\(group.count)건)")
                context.console.print("")
                
                for root in group.roots {
                    printIssueTree(context: context, node: root, indent: 0, showType: showType)
                }
                context.console.print("")
            }
        }
    }
    
    // MARK: - 트리 출력 (재귀)
    private func printIssueTree(context: CommandContext, node: ReportContext.IssueNode, indent: Int, showType: Bool = false) {
        let prefix = String(repeating: "  ", count: indent)
        let bullet = indent == 0 ? "•" : "└─"
        let assignee = node.issue.assigneeName ?? "미배정"
        
        if showType {
            let typeLabel = formatTypeLabel(node.issue.issueType)
            context.console.print("\(prefix)\(bullet) \(typeLabel) \(node.issue.key) - \(node.issue.summary) [@\(assignee)]")
        } else {
            context.console.print("\(prefix)\(bullet) \(node.issue.key) - \(node.issue.summary) [@\(assignee)]")
        }
        
        for child in node.children {
            printIssueTree(context: context, node: child, indent: indent + 1, showType: showType)
        }
    }
    
    // MARK: - 타입 라벨 포맷
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
}
