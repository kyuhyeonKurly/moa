import Vapor

struct ConfluenceChildrenCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "pageIds", help: "Confluence page IDs (comma-separated)")
        var pageIds: String
        
        @Option(name: "email", short: "e", help: "Jira/Confluence email")
        var email: String?
        
        @Option(name: "token", short: "t", help: "Jira/Confluence API token")
        var token: String?
        
        @Flag(name: "export", short: "x", help: "Export to markdown file")
        var export: Bool
    }
    
    var help: String {
        "특정 Confluence 페이지의 하위 페이지들을 트리 구조로 조회합니다."
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        let app = context.application
        
        // 환경변수 또는 인자에서 자격증명 가져오기
        let email = signature.email ?? Environment.get("JIRA_EMAIL") ?? ""
        let token = signature.token ?? Environment.get("JIRA_TOKEN") ?? ""
        
        guard !email.isEmpty, !token.isEmpty else {
            context.console.error("❌ Email and token are required. Set JIRA_EMAIL/JIRA_TOKEN or use --email/--token options.")
            return
        }
        
        // 쉼표로 구분된 페이지 ID들 파싱
        let pageIds = signature.pageIds.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        
        guard !pageIds.isEmpty else {
            context.console.error("❌ At least one page ID is required.")
            return
        }
        
        let shouldExport = signature.export
        
        context.console.print("🔍 Fetching children for \(pageIds.count) page(s)...")
        
        // nonisolated 클로저를 위한 복사
        let client = app.client
        
        // Thread-safe container for tree nodes
        final class ResultBox: @unchecked Sendable {
            var pageTrees: [[ConfluencePageNode]] = []  // 각 부모 페이지별 트리
            var fetchError: Error?
            let lock = NSLock()
            
            func setResults(_ results: [[ConfluencePageNode]]) {
                lock.lock()
                defer { lock.unlock() }
                self.pageTrees = results
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
                
                for pageId in pageIds {
                    let tree = try await service.getPageTreeWithChildren(pageId: pageId, email: email, token: token)
                    pageTrees.append(tree)
                }
                
                box.setResults(pageTrees)
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
        let totalCount = pageTrees.reduce(0) { $0 + $1.count }
        
        // 결과 출력
        let output = Self.generateTreeOutput(pageTrees: pageTrees)
        context.console.print(output)
        
        // 파일 내보내기
        if shouldExport {
            let markdownOutput = Self.generateTreeMarkdown(pageTrees: pageTrees, pageIds: pageIds)
            let filename = "wiki-tree_\(pageIds.joined(separator: "_")).md"
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
    
    // MARK: - Tree Output Generation
    
    private static func generateTreeOutput(pageTrees: [[ConfluencePageNode]]) -> String {
        var lines: [String] = []
        let totalCount = pageTrees.reduce(0) { $0 + $1.count }
        
        lines.append("")
        lines.append("📖 Confluence Page Tree")
        lines.append("=" .padding(toLength: 60, withPad: "=", startingAt: 0))
        lines.append("")
        
        for tree in pageTrees {
            for node in tree {
                let indent = String(repeating: "  ", count: node.depth)
                let bullet = node.depth == 0 ? "📁" : "└─"
                let title = node.title
                lines.append("\(indent)\(bullet) \(title)")
            }
            lines.append("")
        }
        
        lines.append("=" .padding(toLength: 60, withPad: "=", startingAt: 0))
        lines.append("✅ Total: \(totalCount) pages")
        
        return lines.joined(separator: "\n")
    }
    
    private static func generateTreeMarkdown(pageTrees: [[ConfluencePageNode]], pageIds: [String]) -> String {
        var lines: [String] = []
        let totalCount = pageTrees.reduce(0) { $0 + $1.count }
        
        lines.append("# Confluence Page Tree")
        lines.append("")
        lines.append("> Total: \(totalCount) pages")
        lines.append("")
        lines.append("---")
        lines.append("")
        
        for tree in pageTrees {
            guard let root = tree.first else { continue }
            
            // 트리별 섹션 헤더
            lines.append("## 📁 \(root.title)")
            lines.append("")
            
            for node in tree {
                let indent = String(repeating: "  ", count: node.depth)
                let link = "https://kurly0521.atlassian.net/wiki\(node.webLink ?? "")"
                let author = node.createdBy ?? "Unknown"
                let date = formatDate(node.createdDate)
                
                // 트리 구조로 표현
                lines.append("\(indent)- [\(node.title)](\(link)) `\(date)` *\(author)*")
            }
            lines.append("")
        }
        
        lines.append("---")
        lines.append("")
        lines.append("*Generated by Moa*")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Helpers
    
    private static func formatDate(_ isoString: String?) -> String {
        guard let isoString = isoString else { return "N/A" }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var date = dateFormatter.date(from: isoString)
        if date == nil {
            dateFormatter.formatOptions = [.withInternetDateTime]
            date = dateFormatter.date(from: isoString)
        }
        
        guard let parsedDate = date else { return isoString.prefix(10).description }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd"
        return outputFormatter.string(from: parsedDate)
    }
}
