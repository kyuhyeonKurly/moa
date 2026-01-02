import Vapor

struct ConfluenceWikiCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "space", short: "s", help: "Confluence space key (e.g., appr)")
        var spaceKey: String?
        
        @Option(name: "start-year", help: "Start year (default: current year)")
        var startYear: Int?
        
        @Option(name: "end-year", help: "End year (default: current year)")
        var endYear: Int?
        
        @Option(name: "email", short: "e", help: "Jira/Confluence email")
        var email: String?
        
        @Option(name: "token", short: "t", help: "Jira/Confluence API token")
        var token: String?
        
        @Flag(name: "export", short: "x", help: "Export to markdown file")
        var export: Bool
    }
    
    var help: String {
        "특정 Confluence 스페이스에서 연도별로 작성한 위키 페이지 목록을 조회합니다."
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        let app = context.application
        
        // 환경변수 또는 인자에서 자격증명 가져오기
        let email = signature.email ?? Environment.get("JIRA_EMAIL") ?? ""
        let token = signature.token ?? Environment.get("JIRA_TOKEN") ?? ""
        let spaceKey = signature.spaceKey ?? "appr"
        
        guard !email.isEmpty, !token.isEmpty else {
            context.console.error("❌ Email and token are required. Set JIRA_EMAIL/JIRA_TOKEN or use --email/--token options.")
            return
        }
        
        let currentYear = Calendar.current.component(.year, from: Date())
        let startYear = signature.startYear ?? currentYear
        let endYear = signature.endYear ?? currentYear
        let shouldExport = signature.export
        
        context.console.print("📚 Fetching Confluence pages from space '\(spaceKey)' (\(startYear)-\(endYear))...")
        
        // nonisolated 클로저를 위한 복사
        let client = app.client
        
        // Thread-safe container
        final class ResultBox: @unchecked Sendable {
            var resultsByYear: [Int: [ConfluenceContent]] = [:]
            var fetchError: Error?
            let lock = NSLock()
            
            func setResults(_ results: [Int: [ConfluenceContent]]) {
                lock.lock()
                defer { lock.unlock() }
                self.resultsByYear = results
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
                let results = try await service.searchPagesForYears(
                    spaceKey: spaceKey,
                    startYear: startYear,
                    endYear: endYear,
                    email: email,
                    token: token
                )
                box.setResults(results)
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
        
        let resultsByYear = box.resultsByYear
        
        // 결과 출력
        let output = Self.generateOutput(resultsByYear: resultsByYear, spaceKey: spaceKey, startYear: startYear, endYear: endYear)
        
        context.console.print(output)
        
        // 파일 내보내기
        if shouldExport {
            let markdownOutput = Self.generateMarkdown(resultsByYear: resultsByYear, spaceKey: spaceKey, startYear: startYear, endYear: endYear)
            let filename = "wiki-pages_\(spaceKey)_\(startYear)-\(endYear).md"
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
    
    // MARK: - Output Generation
    
    private static func generateOutput(resultsByYear: [Int: [ConfluenceContent]], spaceKey: String, startYear: Int, endYear: Int) -> String {
        var lines: [String] = []
        let totalPages = resultsByYear.values.reduce(0) { $0 + $1.count }
        
        lines.append("📖 Confluence Wiki Pages (Space: \(spaceKey))")
        lines.append("=" .padding(toLength: 50, withPad: "=", startingAt: 0))
        lines.append("")
        
        for year in (startYear...endYear).reversed() {
            guard let pages = resultsByYear[year], !pages.isEmpty else { continue }
            
            lines.append("## \(year)년 (\(pages.count)건)")
            lines.append("")
            
            // 월별로 그룹핑
            let groupedByMonth = groupPagesByMonth(pages)
            
            for month in (1...12).reversed() {
                guard let monthPages = groupedByMonth[month], !monthPages.isEmpty else { continue }
                
                lines.append("### \(month)월 (\(monthPages.count)건)")
                
                for page in monthPages {
                    let title = page.title
                    let createdDate = formatDate(page.history?.createdDate)
                    let link = "https://kurly0521.atlassian.net/wiki\(page._links?.webui ?? "")"
                    lines.append("- [\(title)](\(link)) - \(createdDate)")
                }
                lines.append("")
            }
        }
        
        lines.append("=" .padding(toLength: 50, withPad: "=", startingAt: 0))
        lines.append("✅ Total: \(totalPages) pages")
        
        return lines.joined(separator: "\n")
    }
    
    private static func generateMarkdown(resultsByYear: [Int: [ConfluenceContent]], spaceKey: String, startYear: Int, endYear: Int) -> String {
        var lines: [String] = []
        let totalPages = resultsByYear.values.reduce(0) { $0 + $1.count }
        
        lines.append("# Confluence Wiki Pages")
        lines.append("")
        lines.append("> Space: `\(spaceKey)` | Period: \(startYear) - \(endYear) | Total: \(totalPages) pages")
        lines.append("")
        lines.append("---")
        lines.append("")
        
        for year in (startYear...endYear).reversed() {
            guard let pages = resultsByYear[year], !pages.isEmpty else { continue }
            
            lines.append("## \(year)년 (\(pages.count)건)")
            lines.append("")
            
            // 월별로 그룹핑
            let groupedByMonth = groupPagesByMonth(pages)
            
            for month in (1...12).reversed() {
                guard let monthPages = groupedByMonth[month], !monthPages.isEmpty else { continue }
                
                lines.append("### \(month)월 (\(monthPages.count)건)")
                lines.append("")
                lines.append("| 제목 | 작성일 |")
                lines.append("|------|--------|")
                
                for page in monthPages {
                    let title = page.title.replacingOccurrences(of: "|", with: "\\|")
                    let createdDate = formatDate(page.history?.createdDate)
                    let link = "https://kurly0521.atlassian.net/wiki\(page._links?.webui ?? "")"
                    lines.append("| [\(title)](\(link)) | \(createdDate) |")
                }
                lines.append("")
            }
        }
        
        lines.append("---")
        lines.append("")
        lines.append("*Generated by Moa*")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Helpers
    
    private static func groupPagesByMonth(_ pages: [ConfluenceContent]) -> [Int: [ConfluenceContent]] {
        var grouped: [Int: [ConfluenceContent]] = [:]
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        
        for page in pages {
            guard let dateString = page.history?.createdDate else { continue }
            
            var date: Date?
            date = dateFormatter.date(from: dateString)
            if date == nil {
                date = fallbackFormatter.date(from: dateString)
            }
            
            if let date = date {
                let month = Calendar.current.component(.month, from: date)
                grouped[month, default: []].append(page)
            }
        }
        
        // 각 월별로 날짜 내림차순 정렬
        for (month, monthPages) in grouped {
            grouped[month] = monthPages.sorted { p1, p2 in
                (p1.history?.createdDate ?? "") > (p2.history?.createdDate ?? "")
            }
        }
        
        return grouped
    }
    
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
