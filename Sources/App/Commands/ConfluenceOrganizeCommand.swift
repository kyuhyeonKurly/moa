import Vapor
import Foundation

struct ConfluenceOrganizeCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "pageIds", help: "Confluence page IDs (comma-separated)")
        var pageIds: String
        
        @Option(name: "rules", short: "r", help: "Organization rules file path (JSON)")
        var rulesFile: String?
        
        @Option(name: "older-than", short: "o", help: "Organize pages older than N months")
        var olderThanMonths: Int?
        
        @Option(name: "depth-limit", short: "d", help: "Maximum depth before flattening (default: 3)")
        var depthLimit: Int?
        
        @Option(name: "archive-folder", short: "a", help: "Target archive folder name")
        var archiveFolder: String?
        
        @Option(name: "email", short: "e", help: "Confluence email")
        var email: String?
        
        @Option(name: "token", short: "t", help: "Confluence API token")
        var token: String?
        
        @Option(name: "confluence-token", short: "c", help: "Confluence API token (overrides JIRA_TOKEN)")
        var confluenceToken: String?
        
        @Flag(name: "dry-run", short: "n", help: "Preview changes without executing")
        var dryRun: Bool
        
        @Flag(name: "force", short: "f", help: "Execute without confirmation")
        var force: Bool
        
        @Flag(name: "export", short: "x", help: "Export plan to markdown")
        var export: Bool
    }
    
    var help: String {
        "Confluence 페이지 구조를 자동으로 정리하고 재구성합니다."
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        let app = context.application
        
        // 환경변수 또는 인자에서 자격증명 가져오기
        let email = signature.email ?? Environment.get("JIRA_EMAIL") ?? ""
        let jiraToken = Environment.get("JIRA_TOKEN") ?? ""
        let confluenceToken = signature.confluenceToken ?? Environment.get("CONFLUENCE_TOKEN") ?? jiraToken
        
        guard !email.isEmpty, !confluenceToken.isEmpty else {
            context.console.error("❌ Email and Confluence token are required. Set JIRA_EMAIL/CONFLUENCE_TOKEN or use --email/--confluence-token options.")
            return
        }
        
        // 쉼표로 구분된 페이지 ID들 파싱
        let pageIds = signature.pageIds.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        
        guard !pageIds.isEmpty else {
            context.console.error("❌ At least one page ID is required.")
            return
        }
        
        let olderThanMonths = signature.olderThanMonths ?? 6
        let depthLimit = signature.depthLimit ?? 3
        let archiveFolder = signature.archiveFolder ?? "Archive"
        let shouldExport = signature.export
        let isDryRun = signature.dryRun
        let shouldForce = signature.force
        
        context.console.print("🔧 Confluence Page Organizer")
        context.console.print("=" .padding(toLength: 50, withPad: "=", startingAt: 0))
        context.console.print("")
        
        // Organization 규칙 로드
        var rules: [ConfluenceOrganizationRule] = []
        if let rulesFile = signature.rulesFile {
            do {
                let rulesData = try Data(contentsOf: URL(fileURLWithPath: rulesFile))
                rules = try JSONDecoder().decode([ConfluenceOrganizationRule].self, from: rulesData)
                context.console.print("📋 Loaded \(rules.count) rules from \(rulesFile)")
            } catch {
                context.console.error("❌ Failed to load rules file: \(error)")
                return
            }
        } else {
            // 기본 규칙 생성
            rules = createDefaultRules(olderThanMonths: olderThanMonths, depthLimit: depthLimit, archiveFolder: archiveFolder)
            context.console.print("📋 Using default rules (older than \(olderThanMonths) months, depth limit \(depthLimit))")
        }
        
        // nonisolated 클로저를 위한 복사
        let client = app.client
        
        // Thread-safe container for results
        final class ResultBox: @unchecked Sendable {
            var pageTrees: [[ConfluencePageNode]] = []
            var organizationPlan: [ConfluenceOrganizationResult] = []
            var fetchError: Error?
            let lock = NSLock()
            
            func setPageTrees(_ trees: [[ConfluencePageNode]]) {
                lock.lock()
                defer { lock.unlock() }
                self.pageTrees = trees
            }
            
            func setOrganizationPlan(_ plan: [ConfluenceOrganizationResult]) {
                lock.lock()
                defer { lock.unlock() }
                self.organizationPlan = plan
            }
            
            func setError(_ error: Error) {
                lock.lock()
                defer { lock.unlock() }
                self.fetchError = error
            }
        }
        
        let box = ResultBox()
        let group = DispatchGroup()
        
        group.enter()
        
        Task {
            do {
                let service = ConfluenceService(client: client)
                var pageTrees: [[ConfluencePageNode]] = []
                var allPages: [ConfluenceContent] = []
                
                for pageId in pageIds {
                    let tree = try await service.getPageTreeWithChildren(pageId: pageId, email: email, token: confluenceToken)
                    pageTrees.append(tree)
                    allPages.append(contentsOf: tree.map { $0.page })
                }
                
                box.setPageTrees(pageTrees)
                
                // Organization 계획 생성
                let plan = generateOrganizationPlan(pages: allPages, rules: rules, archiveFolder: archiveFolder)
                box.setOrganizationPlan(plan)
                
            } catch {
                box.setError(error)
            }
            group.leave()
        }
        
        group.wait()
        
        if let error = box.fetchError {
            context.console.error("❌ Error: \(error)")
            return
        }
        
        let pageTrees = box.pageTrees
        let organizationPlan = box.organizationPlan
        
        // 분석 결과 출력
        let totalPages = pageTrees.flatMap { $0 }.count
        let analysisOutput = generateAnalysisOutput(pageTrees: pageTrees, totalPages: totalPages)
        context.console.print(analysisOutput)
        
        // Organization 계획 출력
        let planOutput = generatePlanOutput(organizationPlan: organizationPlan, isDryRun: isDryRun)
        context.console.print(planOutput)
        
        // 실행 확인
        if !isDryRun && !shouldForce {
            context.console.print("\n⚠️  This will modify Confluence pages.")
            context.console.print("   Pages to modify: \(organizationPlan.filter { $0.status == "success" }.count)")
            let _ = context.console.confirm("   Do you want to continue? [y/N]")
        }
        
        // 실제 실행 또는 내보내기
        if shouldExport {
            let markdownOutput = generateMarkdownOutput(
                pageTrees: pageTrees,
                organizationPlan: organizationPlan,
                rules: rules,
                isDryRun: isDryRun
            )
            let filename = "confluence-organization-plan_\(Date().timeIntervalSince1970).md"
            let exportPath = FileManager.default.currentDirectoryPath + "/exports/\(filename)"
            
            do {
                try FileManager.default.createDirectory(
                    atPath: FileManager.default.currentDirectoryPath + "/exports",
                    withIntermediateDirectories: true
                )
                try markdownOutput.write(toFile: exportPath, atomically: true, encoding: .utf8)
                context.console.print("\n✅ Exported to: \(exportPath)")
            } catch {
                context.console.error("❌ Failed to export: \(error)")
            }
        }
    }
    
    // MARK: - Default Rules Creation
    
    private func createDefaultRules(olderThanMonths: Int, depthLimit: Int, archiveFolder: String) -> [ConfluenceOrganizationRule] {
        return [
            ConfluenceOrganizationRule(
                action: .archive,
                condition: "createdOlderThan",
                target: "\(archiveFolder)",
                description: "Pages older than \(olderThanMonths) months move to \(archiveFolder)"
            ),
            ConfluenceOrganizationRule(
                action: .move,
                condition: "depthExceeds",
                target: "flatten",
                description: "Pages deeper than level \(depthLimit) get flattened"
            ),
            ConfluenceOrganizationRule(
                action: .addLabel,
                condition: "createdOlderThan",
                target: "legacy",
                description: "Pages older than 12 months get 'legacy' label"
            ),
            ConfluenceOrganizationRule(
                action: .rename,
                condition: "titleContains",
                target: "standardized",
                description: "Standardize page titles with date prefixes"
            )
        ]
    }
    
    // MARK: - Organization Plan Generation
    
    private func generateOrganizationPlan(pages: [ConfluenceContent], rules: [ConfluenceOrganizationRule], archiveFolder: String) -> [ConfluenceOrganizationResult] {
        var plan: [ConfluenceOrganizationResult] = []
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        
        for page in pages {
            for rule in rules {
                let shouldApply = evaluateRule(page: page, rule: rule, cutoffDate: cutoffDate)
                
                if shouldApply {
                    let result = ConfluenceOrganizationResult(
                        pageId: page.id,
                        title: page.title,
                        action: rule.action,
                        oldLocation: extractCurrentLocation(page: page),
                        newLocation: rule.target,
                        status: "success",
                        message: "Will apply rule: \(rule.description)"
                    )
                    plan.append(result)
                    break // 한 페이지에 여러 규칙 적용 방지
                }
            }
        }
        
        return plan
    }
    
    private func evaluateRule(page: ConfluenceContent, rule: ConfluenceOrganizationRule, cutoffDate: Date) -> Bool {
        guard let createdDateString = page.history?.createdDate,
              let createdDate = parseISODate(createdDateString) else {
            return false
        }
        
        switch rule.action {
        case .archive:
            if rule.condition == "createdOlderThan" {
                return createdDate < cutoffDate
            }
        case .addLabel:
            if rule.condition == "createdOlderThan" {
                let yearCutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
                return createdDate < yearCutoff
            }
        case .move, .rename:
            // 추가 로직 필요
            return false
        }
        
        return false
    }
    
    private func extractCurrentLocation(page: ConfluenceContent) -> String {
        return page.space?.key ?? "Unknown"
    }
    
    private func parseISODate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: dateString)
    }
    
    // MARK: - Output Generation
    
    private func generateAnalysisOutput(pageTrees: [[ConfluencePageNode]], totalPages: Int) -> String {
        var lines: [String] = []
        
        lines.append("📊 Analysis Results")
        lines.append("=" .padding(toLength: 50, withPad: "=", startingAt: 0))
        lines.append("")
        lines.append("📄 Total pages analyzed: \(totalPages)")
        lines.append("🌳 Total page trees: \(pageTrees.count)")
        lines.append("")
        
        for (index, tree) in pageTrees.enumerated() {
            lines.append("Tree \(index + 1):")
            lines.append("  📁 Root: \(tree.first?.title ?? "Unknown")")
            lines.append("  📏 Max depth: \(tree.map { $0.depth }.max() ?? 0)")
            lines.append("  📄 Total pages: \(tree.count)")
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generatePlanOutput(organizationPlan: [ConfluenceOrganizationResult], isDryRun: Bool) -> String {
        var lines: [String] = []
        let mode = isDryRun ? "DRY RUN" : "EXECUTION PLAN"
        
        lines.append("🔧 Organization Plan (\(mode))")
        lines.append("=" .padding(toLength: 50, withPad: "=", startingAt: 0))
        lines.append("")
        
        let successCount = organizationPlan.filter { $0.status == "success" }.count
        
        lines.append("📋 Planned actions: \(successCount)")
        lines.append("")
        
        for result in organizationPlan {
            let emoji = result.status == "success" ? "✅" : "⚠️"
            lines.append("\(emoji) [\(result.action.rawValue.uppercased())] \(result.title)")
            lines.append("   From: \(result.oldLocation ?? "Unknown")")
            lines.append("   To: \(result.newLocation ?? "Unknown")")
            if let message = result.message {
                lines.append("   Note: \(message)")
            }
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func generateMarkdownOutput(
        pageTrees: [[ConfluencePageNode]],
        organizationPlan: [ConfluenceOrganizationResult],
        rules: [ConfluenceOrganizationRule],
        isDryRun: Bool
    ) -> String {
        var lines: [String] = []
        
        lines.append("# Confluence Organization Plan")
        lines.append("")
        lines.append("> Mode: \(isDryRun ? "Dry Run" : "Execution") | Generated: \(Date())")
        lines.append("")
        lines.append("---")
        lines.append("")
        
        // Rules section
        lines.append("## 📋 Organization Rules")
        lines.append("")
        for rule in rules {
            lines.append("- **\(rule.action.rawValue.uppercased())**: \(rule.description)")
        }
        lines.append("")
        
        // Analysis section
        lines.append("## 📊 Current Structure Analysis")
        lines.append("")
        lines.append("| Tree | Root Page | Max Depth | Total Pages |")
        lines.append("|------|------------|------------|-------------|")
        
        for (index, tree) in pageTrees.enumerated() {
            let rootTitle = tree.first?.title ?? "Unknown"
            let maxDepth = tree.map { $0.depth }.max() ?? 0
            let pageCount = tree.count
            lines.append("| \(index + 1) | \(rootTitle) | \(maxDepth) | \(pageCount) |")
        }
        lines.append("")
        
        // Plan section
        lines.append("## 🔧 Organization Plan")
        lines.append("")
        lines.append("| Action | Page | From | To | Status |")
        lines.append("|--------|------|------|----|--------|")
        
        for result in organizationPlan {
            let status = result.status == "success" ? "✅ Success" : "⚠️ \(result.status)"
            lines.append("| \(result.action.rawValue) | \(result.title) | \(result.oldLocation ?? "Unknown") | \(result.newLocation ?? "Unknown") | \(status) |")
        }
        lines.append("")
        
        lines.append("---")
        lines.append("")
        lines.append("*Generated by Moa Confluence Organizer*")
        
        return lines.joined(separator: "\n")
    }
}