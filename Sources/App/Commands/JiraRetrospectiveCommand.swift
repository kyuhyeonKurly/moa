import Vapor
import Foundation

/// 연도별 Jira 티켓을 도메인별로 분석하여 에이전트 문맥 주입용 마크다운 생성
/// Usage: swift run App jira-retrospective --start 2021 --end 2025 --output ./context.md
struct JiraRetrospectiveCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "start", short: "s", help: "Start year (default: 2021)")
        var startYear: Int?
        
        @Option(name: "end", short: "e", help: "End year (default: current year)")
        var endYear: Int?
        
        @Option(name: "output", short: "o", help: "Output file path")
        var output: String?
        
        @Flag(name: "include-trees", short: "t", help: "Include epic tree structures (slower)")
        var includeTrees: Bool
    }
    
    var help: String {
        "Generate retrospective context for AI agent injection"
    }
    
    // 도메인 키워드 매핑
    private let domainKeywords: [String: [String]] = [
        "🔍 검색 (Search)": ["검색", "search", "자동완성", "autocomplete", "키워드"],
        "🛒 장바구니 (Cart)": ["장바구니", "cart", "담기", "체크박스"],
        "🏠 홈 (Home)": ["홈", "home", "컬리추천", "메인", "퀵메뉴", "둥둥이"],
        "📂 카테고리 (Category)": ["카테고리", "category", "컬렉션", "필터", "정렬"],
        "👤 마이컬리 (MyKurly)": ["마이컬리", "mykurly", "회원", "로그인", "인증"],
        "📊 분석 (Analytics)": ["앰플리튜드", "amplitude", "이벤트", "로그", "트래킹", "appsflyer", "branch"],
        "🎨 디자인시스템 (KPDS)": ["kpds", "디자인", "컴포넌트", "ui", "네비게이션", "탑바"],
        "🏗️ 아키텍처 (Architecture)": ["리팩토링", "모듈", "spm", "tuist", "의존성", "빌드"],
        "🔔 푸시/알림 (Push)": ["푸시", "push", "알림", "notification"],
        "💳 결제 (Payment)": ["결제", "payment", "pg", "컬리패스"],
        "🔗 딥링크 (DeepLink)": ["딥링크", "deeplink", "브랜치", "유니버셜"],
        "🛍️ 상품 (Product)": ["상품", "product", "썸네일", "상세"],
        "🎁 프로모션 (Promotion)": ["프로모션", "이벤트", "특가", "할인"],
        "🚚 배송 (Delivery)": ["배송", "샛별", "배송지", "주소"],
        "🔧 기타 (Etc)": []
    ]
    
    func run(using context: CommandContext, signature: Signature) throws {
        let startYear = signature.startYear ?? 2021
        let endYear = signature.endYear ?? Calendar.current.component(.year, from: Date())
        let _ = signature.includeTrees
        let outputPath = signature.output ?? "./exports/retrospective_\(startYear)-\(endYear).md"
        
        guard let email = Environment.get("JIRA_EMAIL"),
              let token = Environment.get("JIRA_TOKEN") else {
            context.console.error("❌ JIRA_EMAIL and JIRA_TOKEN must be set in .env")
            return
        }
        
        let app = context.application
        let client = JiraAPIClient(client: app.client, email: email, token: token)
        
        context.console.print("📊 Generating retrospective context...")
        context.console.print("   Years: \(startYear) - \(endYear)")
        context.console.print("")
        
        // 동기 실행
        let group = DispatchGroup()
        
        final class ResultBox: @unchecked Sendable {
            var yearlyData: [Int: [ProcessedIssue]] = [:]
            var epics: [String: EpicInfo] = [:]
            var currentUser: JiraUser?
            var errorMessage: String?
        }
        let box = ResultBox()
        
        group.enter()
        Task { @MainActor in
            do {
                // 현재 사용자 확인
                box.currentUser = try await client.getMyself()
                context.console.print("👤 User: \(box.currentUser?.displayName ?? "Unknown")")
                
                // 연도별 이슈 수집
                for year in startYear...endYear {
                    context.console.print("📅 Fetching \(year)...")
                    let issues = try await self.fetchYearlyIssues(client: client, year: year)
                    box.yearlyData[year] = issues
                    
                    // 에픽 정보 수집
                    for issue in issues {
                        if issue.issueType.lowercased().contains("에픽") || issue.issueType.lowercased() == "epic" {
                            if box.epics[issue.key] == nil {
                                box.epics[issue.key] = EpicInfo(
                                    key: issue.key,
                                    summary: issue.summary,
                                    years: [year],
                                    childCount: 0
                                )
                            } else {
                                box.epics[issue.key]?.years.append(year)
                            }
                        }
                    }
                }
                
                context.console.print("✅ Data collection complete!")
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
        
        // 마크다운 생성
        let output = generateContextMarkdown(
            yearlyData: box.yearlyData,
            epics: box.epics,
            user: box.currentUser,
            startYear: startYear,
            endYear: endYear
        )
        
        // 파일 저장
        do {
            let url = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try output.write(to: url, atomically: true, encoding: .utf8)
            context.console.success("✅ Exported to: \(outputPath)")
        } catch {
            context.console.error("❌ Failed to export: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Data Fetching
    
    private func fetchYearlyIssues(client: JiraAPIClient, year: Int) async throws -> [ProcessedIssue] {
        let nextYear = year + 1
        let jql = """
        assignee = currentUser() AND \
        created >= "\(year)-01-01" AND created < "\(nextYear)-01-01" \
        ORDER BY created ASC
        """
        
        var allIssues: [JiraIssue] = []
        var nextPageToken: String? = nil
        
        repeat {
            let response = try await client.searchIssues(
                jql: jql,
                fields: ["summary", "created", "status", "issuetype", "labels", "fixVersions", "parent", "assignee", "resolutiondate"],
                maxResults: 100,
                nextPageToken: nextPageToken
            )
            allIssues.append(contentsOf: response.issues)
            nextPageToken = response.nextPageToken
        } while nextPageToken != nil
        
        return allIssues.map { issue in
            ProcessedIssue(
                key: issue.key,
                summary: issue.fields.summary,
                createdDate: ISO8601DateFormatter().date(from: issue.fields.created) ?? Date(),
                labels: issue.fields.labels,
                versions: [],
                link: "https://kurly0521.atlassian.net/browse/\(issue.key)",
                projectKey: String(issue.key.split(separator: "-").first ?? ""),
                parentKey: issue.fields.parent?.key,
                parentSummary: issue.fields.parent?.fields.summary,
                parentType: issue.fields.parent?.fields.issuetype?.name,
                issueType: issue.fields.issuetype.name,
                isSubtask: issue.fields.issuetype.subtask,
                typeClass: issue.fields.issuetype.name,
                releaseDate: nil,
                assigneeAccountId: issue.fields.assignee?.accountId,
                assigneeName: issue.fields.assignee?.displayName
            )
        }
    }
    
    // MARK: - Markdown Generation
    
    private func generateContextMarkdown(
        yearlyData: [Int: [ProcessedIssue]],
        epics: [String: EpicInfo],
        user: JiraUser?,
        startYear: Int,
        endYear: Int
    ) -> String {
        var md = ""
        
        // 헤더
        md += """
        # 🎯 컬리 iOS 개발 회고 (\(startYear)-\(endYear))
        
        > **담당자**: \(user?.displayName ?? "Unknown")
        > **생성일**: \(ISO8601DateFormatter().string(from: Date()))
        > **목적**: AI 에이전트 문맥 주입용 - 도메인별 업무 히스토리 및 성과 분석
        
        ---
        
        ## 📊 전체 요약
        
        | 연도 | 총 티켓 | 에픽 | 스토리 | 작업 | 버그 | 개선 |
        |------|---------|------|--------|------|------|------|
        
        """
        
        // 연도별 요약 테이블
        let sortedYears = yearlyData.keys.sorted()
        for year in sortedYears {
            guard let issues = yearlyData[year] else { continue }
            let stats = countByType(issues)
            md += "| \(year) | \(issues.count) | \(stats["에픽"] ?? 0) | \(stats["스토리"] ?? 0) | \(stats["작업"] ?? 0) | \(stats["버그"] ?? 0) | \(stats["개선"] ?? 0) |\n"
        }
        
        let totalCount = yearlyData.values.flatMap { $0 }.count
        md += "\n**총 \(totalCount)건**의 Jira 티켓 처리\n\n"
        
        // 도메인별 분석
        md += "---\n\n## 🏷️ 도메인별 업무 분석\n\n"
        
        let domainAnalysis = analyzeDomains(yearlyData: yearlyData)
        for (domain, analysis) in domainAnalysis.sorted(by: { $0.value.totalCount > $1.value.totalCount }) {
            if analysis.totalCount == 0 { continue }
            
            md += "### \(domain)\n\n"
            md += "- **총 티켓**: \(analysis.totalCount)건\n"
            md += "- **활동 기간**: \(analysis.years.sorted().map(String.init).joined(separator: ", "))\n"
            md += "- **연속성**: \(analysis.years.count)년간 지속\n\n"
            
            md += "**연도별 주요 이슈:**\n\n"
            for year in analysis.years.sorted() {
                let yearIssues = analysis.issuesByYear[year] ?? []
                let topIssues = yearIssues.prefix(5)
                md += "- **\(year)년** (\(yearIssues.count)건)\n"
                for issue in topIssues {
                    md += "  - [\(issue.key)](\(issue.link)) - \(issue.summary)\n"
                }
                if yearIssues.count > 5 {
                    md += "  - ... 외 \(yearIssues.count - 5)건\n"
                }
            }
            md += "\n"
        }
        
        // 연도별 마일스톤
        md += "---\n\n## 📅 연도별 마일스톤\n\n"
        
        for year in sortedYears {
            guard let issues = yearlyData[year] else { continue }
            md += "### \(year)년\n\n"
            md += "**총 \(issues.count)건** 처리\n\n"
            
            // 에픽 목록
            let yearEpics = issues.filter { 
                $0.issueType.lowercased().contains("에픽") || $0.issueType.lowercased() == "epic" 
            }
            if !yearEpics.isEmpty {
                md += "**주요 에픽:**\n"
                for epic in yearEpics.prefix(10) {
                    md += "- 🟣 [\(epic.key)](\(epic.link)) - \(epic.summary)\n"
                }
                md += "\n"
            }
            
            // 월별 분포
            let monthlyCount = countByMonth(issues)
            md += "**월별 분포:**\n"
            md += "```\n"
            for month in 1...12 {
                let count = monthlyCount[month] ?? 0
                let bar = String(repeating: "█", count: min(count / 2, 20))
                md += String(format: "%2d월: %3d건 %@\n", month, count, bar)
            }
            md += "```\n\n"
        }
        
        // 장기 에픽 (여러 해에 걸친)
        md += "---\n\n## 🔄 장기 진행 에픽 (다년간 연속)\n\n"
        
        let longTermEpics = epics.filter { $0.value.years.count > 1 }
            .sorted { $0.value.years.count > $1.value.years.count }
        
        if !longTermEpics.isEmpty {
            for (key, info) in longTermEpics.prefix(20) {
                let yearsStr = info.years.sorted().map(String.init).joined(separator: " → ")
                md += "- 🟣 **[\(key)](https://kurly0521.atlassian.net/browse/\(key))** - \(info.summary)\n"
                md += "  - 기간: \(yearsStr) (\(info.years.count)년)\n"
            }
        } else {
            md += "_장기 진행 에픽 없음_\n"
        }
        
        // AI 분석용 raw 데이터 섹션
        md += "\n---\n\n## 📋 AI 분석용 키워드 인덱스\n\n"
        md += """
        > 이 섹션은 AI가 문맥을 이해하는 데 활용됩니다.
        
        **주요 기술 키워드:**
        - Swift, SwiftUI, UIKit, Combine, RxSwift
        - Vapor, Leaf, Fluent
        - Amplitude, Appsflyer, Branch, Firebase
        - KPDS (Kurly Product Design System)
        - SPM, Tuist, Xcode Cloud
        
        **도메인 키워드:**
        - 검색, 장바구니, 홈, 카테고리, 마이컬리
        - 필터, 정렬, 컬렉션, 상품목록
        - 딥링크, 푸시알림, 결제
        
        **프로젝트 코드:**
        - KMA: 마켓컬리 앱
        - KPDS: 디자인 시스템
        - SBQN: 검색 백엔드
        - AM: 앰플리튜드 이벤트
        
        """
        
        // 연도별 전체 티켓 목록 (접힌 상태)
        md += "\n---\n\n## 📝 전체 티켓 목록 (연도별)\n\n"
        
        for year in sortedYears {
            guard let issues = yearlyData[year] else { continue }
            md += "<details>\n<summary><b>\(year)년</b> (\(issues.count)건)</summary>\n\n"
            
            for issue in issues {
                let typeIcon = issueTypeIcon(issue.issueType)
                md += "- \(typeIcon) [\(issue.key)](\(issue.link)) - \(issue.summary)\n"
            }
            
            md += "\n</details>\n\n"
        }
        
        return md
    }
    
    // MARK: - Analysis Helpers
    
    private func countByType(_ issues: [ProcessedIssue]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for issue in issues {
            counts[issue.issueType, default: 0] += 1
        }
        return counts
    }
    
    private func countByMonth(_ issues: [ProcessedIssue]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for issue in issues {
            let month = Calendar.current.component(.month, from: issue.createdDate)
            counts[month, default: 0] += 1
        }
        return counts
    }
    
    private func analyzeDomains(yearlyData: [Int: [ProcessedIssue]]) -> [String: DomainAnalysis] {
        var analysis: [String: DomainAnalysis] = [:]
        
        // 초기화
        for domain in domainKeywords.keys {
            analysis[domain] = DomainAnalysis()
        }
        
        // 이슈 분류
        for (year, issues) in yearlyData {
            for issue in issues {
                let domain = classifyDomain(issue)
                analysis[domain]?.totalCount += 1
                analysis[domain]?.years.insert(year)
                if analysis[domain]?.issuesByYear[year] == nil {
                    analysis[domain]?.issuesByYear[year] = []
                }
                analysis[domain]?.issuesByYear[year]?.append(issue)
            }
        }
        
        return analysis
    }
    
    private func classifyDomain(_ issue: ProcessedIssue) -> String {
        let text = "\(issue.summary) \(issue.labels.joined(separator: " "))".lowercased()
        
        for (domain, keywords) in domainKeywords {
            if keywords.isEmpty { continue }
            for keyword in keywords {
                if text.contains(keyword.lowercased()) {
                    return domain
                }
            }
        }
        
        return "🔧 기타 (Etc)"
    }
    
    private func issueTypeIcon(_ typeName: String) -> String {
        switch typeName.lowercased() {
        case "epic", "에픽": return "🟣"
        case "story", "스토리": return "🟢"
        case "task", "작업": return "🔵"
        case "sub-task", "하위 작업": return "⚪"
        case "bug", "버그": return "🔴"
        case "improvement", "개선": return "🟡"
        default: return "⬜"
        }
    }
}

// MARK: - Models

struct EpicInfo {
    let key: String
    let summary: String
    var years: [Int]
    var childCount: Int
}

struct DomainAnalysis {
    var totalCount: Int = 0
    var years: Set<Int> = []
    var issuesByYear: [Int: [ProcessedIssue]] = [:]
}
