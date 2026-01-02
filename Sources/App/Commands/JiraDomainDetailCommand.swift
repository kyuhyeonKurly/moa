import Vapor
import Foundation

/// 특정 도메인의 상세 데이터 추출 (댓글, 첨부파일 포함)
/// Usage: swift run App jira-domain-detail --domain search --start 2021 --end 2025
struct JiraDomainDetailCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "domain", short: "d", help: "Domain to extract (required): search, cart, home, category, mykurly, experiment, platform, design, product, filter, mmp, ai")
        var domain: String?
        
        @Option(name: "start", short: "s", help: "Start year (default: 2021)")
        var startYear: Int?
        
        @Option(name: "end", short: "e", help: "End year (default: current year)")
        var endYear: Int?
        
        @Option(name: "output", short: "o", help: "Output file path")
        var output: String?
    }
    
    var help: String {
        "Extract detailed domain data including comments and attachments"
    }
    
    // 도메인 키워드 매핑 (JiraDomainGuidelineCommand와 동일)
    private let domainKeywords: [String: DomainConfig] = [
        "search": DomainConfig(
            displayName: "🔍 검색 (Search)",
            keywords: ["검색", "search", "자동완성", "autocomplete", "키워드", "srp", "검색결과", "네이버 sa", "검색 탭", "검색탭"],
            subTopics: [
                "자동완성": ["자동완성", "autocomplete", "추천검색어"],
                "검색결과": ["검색결과", "srp", "search result", "오가닉"],
                "검색UX": ["검색탭", "검색 탭", "검색화면", "search tab"],
                "광고/추천": ["광고", "몰로코", "네이티브광고", "연관상품"]
            ]
        ),
        "cart": DomainConfig(
            displayName: "🛒 장바구니 (Cart)",
            keywords: ["장바구니", "cart", "담기", "체크박스", "계산대"],
            subTopics: [
                "장바구니UI": ["장바구니", "cart", "체크박스"],
                "담기기능": ["담기", "add to cart", "숏컷"],
                "계산/결제연동": ["계산대", "결제", "배송비"]
            ]
        ),
        "home": DomainConfig(
            displayName: "🏠 홈/전시 (Home & Display)",
            keywords: ["홈", "home", "컬리추천", "메인", "퀵메뉴", "둥둥이", "전시", "섹션"],
            subTopics: [
                "홈화면": ["홈", "home", "메인탭"],
                "컬리추천": ["컬리추천", "추천", "recommendation"],
                "전시/템플릿": ["전시", "템플릿", "섹션", "collection"],
                "UI컴포넌트": ["퀵메뉴", "둥둥이", "플로팅", "배너"]
            ]
        ),
        "category": DomainConfig(
            displayName: "📂 카테고리/컬렉션 (Category)",
            keywords: ["카테고리", "category", "컬렉션", "collection", "베스트", "신상품"],
            subTopics: [
                "카테고리": ["카테고리", "3차카테고리", "서브탭"],
                "컬렉션": ["컬렉션", "collection", "그룹"],
                "상품목록": ["상품목록", "productlist", "리스팅"]
            ]
        ),
        "mykurly": DomainConfig(
            displayName: "👤 마이컬리/회원 (MyKurly)",
            keywords: ["마이컬리", "mykurly", "회원", "로그인", "인증", "멤버십"],
            subTopics: [
                "로그인/인증": ["로그인", "인증", "auth"],
                "마이페이지": ["마이컬리", "마이페이지"],
                "멤버십": ["멤버십", "등급", "컬리패스"]
            ]
        ),
        "experiment": DomainConfig(
            displayName: "🧪 실험 (Experiment)",
            keywords: ["growthbook", "growhbook", "그로스북", "ab테스트", "a/b 테스트", "실험", "피쳐플래그", "feature flag", "firebase config", "remote config"],
            subTopics: [
                "그로스북": ["growthbook", "growhbook", "그로스북", "ab테스트"],
                "파이어베이스": ["firebase config", "remote config", "파베"],
                "피쳐플래그": ["피쳐플래그", "feature flag", "실험"]
            ]
        ),
        "platform": DomainConfig(
            displayName: "🏗️ 플랫폼/인프라 (Platform & Infra)",
            keywords: ["리팩토링", "모듈", "spm", "tuist", "의존성", "빌드", "xcode", "ci", "cd", "attributedstring", "uilabel", "uikit", "코어", "dynamiclinks", "외부라이브러리", "marqueelabel", "pinlayout", "내재화"],
            subTopics: [
                "모듈화": ["모듈", "spm", "package"],
                "빌드시스템": ["tuist", "빌드", "xcode"],
                "CI/CD": ["ci", "cd", "자동화", "파이프라인"],
                "리팩토링": ["리팩토링", "개선", "레거시"]
            ]
        ),
        "design": DomainConfig(
            displayName: "🎨 디자인시스템 (KPDS)",
            keywords: ["kpds", "디자인", "컴포넌트", "네비게이션", "탑바", "gnb", "디자인시스템"],
            subTopics: [
                "네비게이션": ["네비게이션", "gnb", "탑바", "appbar"],
                "컴포넌트": ["컴포넌트", "버튼", "셀"],
                "스타일": ["폰트", "컬러", "스타일", "spacing"]
            ]
        ),
        "product": DomainConfig(
            displayName: "🛍️ 상품 (Product)",
            keywords: ["상품", "product", "상세", "썸네일", "pdp"],
            subTopics: [
                "상품상세": ["상품상세", "pdp", "product detail"],
                "상품카드": ["썸네일", "상품카드", "그리드"],
                "상품정보": ["가격", "할인", "태그"]
            ]
        ),
        "filter": DomainConfig(
            displayName: "🗂️ 필터 (Filter & Sort)",
            keywords: ["필터", "filter", "정렬", "sort", "브랜드필터", "bat"],
            subTopics: [
                "필터UI": ["필터", "filter", "bat"],
                "정렬": ["정렬", "sort", "순서"]
            ]
        ),
        "mmp": DomainConfig(
            displayName: "📊 MMP/마케팅 (Marketing & Attribution)",
            keywords: ["appsflyer", "앱스플라이어", "mmp", "어트리뷰션", "attribution", "마케팅", "branch", "링크", "sdk 설치", "이벤트 트래커"],
            subTopics: [
                "Appsflyer": ["appsflyer", "앱스플라이어"],
                "Branch": ["branch", "브랜치"],
                "어트리뷰션": ["어트리뷰션", "attribution", "mmp"]
            ]
        ),
        "ai": DomainConfig(
            displayName: "🤖 AI",
            keywords: ["foundation model", "ai", "llm", "관심사 추론", "개인화 알림", "온디바이스", "siri", "app intents", "agent skill", "에이전트 스킬"],
            subTopics: [
                "온디바이스AI": ["foundation model", "온디바이스", "llm", "siri"],
                "개인화": ["관심사 추론", "개인화 알림"],
                "AgentSkill": ["agent skill", "에이전트 스킬"]
            ]
        )
    ]
    
    // 강제 도메인 매핑 (JiraDomainGuidelineCommand에서 가져옴)
    private let forcedDomainMapping: [String: String] = [
        // 검색 도메인
        "KMA-5541": "search", "KMA-5539": "search", "KMA-5538": "search",
        "KMA-5388": "search", "KMA-5386": "search", "KMA-5385": "search",
        "KMA-5157": "search", "KMA-4987": "search", "KMA-4970": "search",
        "KMA-4848": "search", "KMA-4797": "search", "KMA-4789": "search",
        "KMA-4716": "search", "KMA-3910": "search", "KMA-3786": "search",
        "KMA-3738": "search", "KMA-3627": "search", "KMA-3592": "search",
        "KMA-3580": "search", "KMA-3406": "search", "KMA-3389": "search",
        "KMA-2815": "search", "KMA-5528": "search", "KMA-5481": "search",
        "KMA-4923": "search",
        
        // MMP 도메인
        "KMA-5302": "mmp", "KMA-5231": "mmp", "KMA-5201": "mmp",
        "KMA-3767": "mmp", "KMA-3715": "mmp", "KMA-3575": "mmp",
        "KMA-2697": "mmp", "KMA-2680": "mmp", "KMA-5303": "mmp",
        "KMA-5118": "mmp",
        
        // 플랫폼 도메인
        "KMA-4648": "platform", "KMA-4675": "platform", "KMA-4663": "platform",
        "KMA-4587": "platform", "KMA-4586": "platform", "KMA-4585": "platform",
        "KMA-4571": "platform", "KMA-4509": "platform", "KMA-4508": "platform",
        "KMA-4405": "platform", "KMA-4342": "platform", "KMA-4098": "platform",
        "KMA-3966": "platform", "KMA-3955": "platform", "KMA-3864": "platform",
        "KMA-3756": "platform", "KMA-5258": "platform", "KMA-3751": "platform",
        
        // 홈/전시 도메인
        "KMA-3737": "home", "KMA-3679": "home", "KMA-3482": "home",
        "KMA-3455": "home", "KMA-3454": "home", "KMA-3433": "home",
        "KMA-3376": "home", "KMA-3302": "home", "KMA-3194": "home",
        "KMA-2976": "home", "KMA-2813": "home",
        
        // 마이컬리 도메인
        "KMA-5067": "mykurly", "KMA-4941": "mykurly", "KMA-3694": "mykurly",
        
        // 실험 도메인
        "KMA-3774": "experiment"
    ]
    
    func run(using context: CommandContext, signature: Signature) throws {
        guard let domainFilter = signature.domain?.lowercased() else {
            context.console.error("❌ Domain is required. Use --domain search")
            context.console.print("Available domains: search, cart, home, category, mykurly, experiment, platform, design, product, filter, mmp, ai")
            return
        }
        
        guard domainKeywords[domainFilter] != nil else {
            context.console.error("❌ Unknown domain: \(domainFilter)")
            context.console.print("Available domains: search, cart, home, category, mykurly, experiment, platform, design, product, filter, mmp, ai")
            return
        }
        
        let startYear = signature.startYear ?? 2021
        let endYear = signature.endYear ?? Calendar.current.component(.year, from: Date())
        let outputPath = signature.output ?? "./exports/domain-detail_\(domainFilter)_\(startYear)-\(endYear).md"
        
        guard let email = Environment.get("JIRA_EMAIL"),
              let token = Environment.get("JIRA_TOKEN") else {
            context.console.error("❌ JIRA_EMAIL and JIRA_TOKEN must be set in .env")
            return
        }
        
        let app = context.application
        let client = JiraAPIClient(client: app.client, email: email, token: token)
        
        context.console.print("📦 Extracting Domain Detail: \(domainFilter)")
        context.console.print("   Years: \(startYear) - \(endYear)")
        context.console.print("")
        
        // 동기 실행
        let group = DispatchGroup()
        
        final class ResultBox: @unchecked Sendable {
            var domainIssues: [DetailedIssue] = []
            var currentUser: JiraUser?
            var errorMessage: String?
        }
        let box = ResultBox()
        
        group.enter()
        Task { @MainActor in
            do {
                box.currentUser = try await client.getMyself()
                context.console.print("👤 User: \(box.currentUser?.displayName ?? "Unknown")")
                
                // 1단계: 기본 이슈 목록 수집 (도메인 필터링)
                var allIssues: [BasicIssue] = []
                for year in startYear...endYear {
                    context.console.print("📅 Fetching \(year)...")
                    let issues = try await self.fetchYearlyIssues(client: client, year: year)
                    allIssues.append(contentsOf: issues)
                }
                context.console.print("📊 Total issues: \(allIssues.count)")
                
                // 2단계: parent 정보 수집
                context.console.print("🔗 Fetching parent info...")
                var parentInfo: [String: ParentInfo] = [:]
                let parentKeys = Set(allIssues.compactMap { $0.parentKey })
                for parentKey in parentKeys {
                    if let info = try? await self.fetchParentInfo(client: client, issueKey: parentKey) {
                        parentInfo[parentKey] = info
                    }
                }
                
                // 3단계: 도메인 필터링
                context.console.print("🔍 Filtering domain: \(domainFilter)...")
                let filteredIssues = self.filterByDomain(
                    issues: allIssues,
                    parentInfo: parentInfo,
                    targetDomain: domainFilter
                )
                context.console.print("📊 Filtered issues: \(filteredIssues.count)")
                
                // 4단계: 상세 데이터 수집 (댓글, 첨부파일)
                context.console.print("📝 Fetching details (comments, attachments)...")
                var detailedIssues: [DetailedIssue] = []
                
                for (index, issue) in filteredIssues.enumerated() {
                    if (index + 1) % 10 == 0 {
                        context.console.print("   Progress: \(index + 1)/\(filteredIssues.count)")
                    }
                    
                    do {
                        let detail = try await client.fetchIssueDetail(issueKey: issue.key)
                        let detailedIssue = DetailedIssue(
                            key: issue.key,
                            summary: issue.summary,
                            description: detail.fields.description?.toPlainText() ?? "",
                            createdDate: issue.createdDate,
                            year: Calendar.current.component(.year, from: issue.createdDate),
                            quarter: issue.quarter,
                            parentKey: issue.parentKey,
                            parentSummary: issue.parentSummary,
                            parentType: issue.parentType,
                            issueType: issue.issueType,
                            status: issue.status,
                            link: issue.link,
                            comments: detail.fields.comment?.comments.map { comment in
                                CommentData(
                                    author: comment.author?.displayName ?? "Unknown",
                                    body: comment.body?.toPlainText() ?? "",
                                    created: comment.created
                                )
                            } ?? [],
                            attachments: detail.fields.attachment?.map { attachment in
                                AttachmentData(
                                    filename: attachment.filename,
                                    mimeType: attachment.mimeType ?? "unknown",
                                    size: attachment.size,
                                    url: attachment.content
                                )
                            } ?? []
                        )
                        detailedIssues.append(detailedIssue)
                    } catch {
                        context.console.warning("⚠️ Failed to fetch detail for \(issue.key): \(error)")
                        // 기본 정보만으로 추가
                        let detailedIssue = DetailedIssue(
                            key: issue.key,
                            summary: issue.summary,
                            description: "",
                            createdDate: issue.createdDate,
                            year: Calendar.current.component(.year, from: issue.createdDate),
                            quarter: issue.quarter,
                            parentKey: issue.parentKey,
                            parentSummary: issue.parentSummary,
                            parentType: issue.parentType,
                            issueType: issue.issueType,
                            status: issue.status,
                            link: issue.link,
                            comments: [],
                            attachments: []
                        )
                        detailedIssues.append(detailedIssue)
                    }
                }
                
                box.domainIssues = detailedIssues
                context.console.success("✅ Detail extraction complete!")
                
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
        let domainConfig = domainKeywords[domainFilter]!
        let output = generateDetailMarkdown(
            domain: domainFilter,
            config: domainConfig,
            issues: box.domainIssues,
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
    
    private func fetchYearlyIssues(client: JiraAPIClient, year: Int) async throws -> [BasicIssue] {
        let nextYear = year + 1
        let jql = """
        assignee = currentUser() AND \
        created >= "\(year)-01-01" AND created < "\(nextYear)-01-01" \
        AND project NOT IN (KQA) \
        ORDER BY created ASC
        """
        
        var allIssues: [JiraIssue] = []
        var nextPageToken: String? = nil
        
        repeat {
            let response = try await client.searchIssues(
                jql: jql,
                fields: ["summary", "created", "status", "issuetype", "labels", "fixVersions", "parent", "assignee"],
                maxResults: 100,
                nextPageToken: nextPageToken
            )
            allIssues.append(contentsOf: response.issues)
            nextPageToken = response.nextPageToken
        } while nextPageToken != nil
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        return allIssues.map { issue in
            let createdString = issue.fields.created
            var createdDate = dateFormatter.date(from: createdString)
                ?? fallbackFormatter.date(from: createdString)
                ?? Date()
            
            if createdDate == Date() {
                let components = createdString.components(separatedBy: "-")
                if components.count >= 2 {
                    let monthStr = components[1]
                    if let month = Int(monthStr) {
                        var dateComponents = DateComponents()
                        dateComponents.year = Int(components[0])
                        dateComponents.month = month
                        dateComponents.day = 15
                        createdDate = Calendar.current.date(from: dateComponents) ?? Date()
                    }
                }
            }
            
            let month = Calendar.current.component(.month, from: createdDate)
            let quarter = (month - 1) / 3 + 1
            
            return BasicIssue(
                key: issue.key,
                summary: issue.fields.summary,
                createdDate: createdDate,
                quarter: quarter,
                labels: issue.fields.labels,
                parentKey: issue.fields.parent?.key,
                parentSummary: issue.fields.parent?.fields.summary,
                parentType: issue.fields.parent?.fields.issuetype?.name,
                issueType: issue.fields.issuetype.name,
                status: issue.fields.status.name,
                link: "https://kurly0521.atlassian.net/browse/\(issue.key)"
            )
        }
    }
    
    private func fetchParentInfo(client: JiraAPIClient, issueKey: String) async throws -> ParentInfo {
        let response = try await client.searchIssues(
            jql: "key = \(issueKey)",
            fields: ["summary", "issuetype", "parent", "labels"],
            maxResults: 1,
            nextPageToken: nil
        )
        
        guard let issue = response.issues.first else {
            throw Abort(.notFound, reason: "Issue \(issueKey) not found")
        }
        
        return ParentInfo(
            key: issue.key,
            summary: issue.fields.summary,
            issueType: issue.fields.issuetype.name,
            labels: issue.fields.labels,
            grandParentKey: issue.fields.parent?.key,
            grandParentSummary: issue.fields.parent?.fields.summary
        )
    }
    
    // MARK: - Domain Classification
    
    private func filterByDomain(
        issues: [BasicIssue],
        parentInfo: [String: ParentInfo],
        targetDomain: String
    ) -> [BasicIssue] {
        // 상위 티켓 도메인 캐시
        var parentDomainCache: [String: String] = [:]
        
        // 강제 매핑 먼저
        for (issueKey, domain) in forcedDomainMapping {
            parentDomainCache[issueKey] = domain
        }
        
        for (parentKey, info) in parentInfo {
            if parentDomainCache[parentKey] != nil { continue }
            
            let parentText = "\(info.summary) \(info.labels.joined(separator: " "))".lowercased()
            var parentDomain = classifyTextToDomain(parentText)
            
            if parentDomain == "etc", let grandParentKey = info.grandParentKey,
               let grandParentInfo = parentInfo[grandParentKey] {
                let grandParentText = "\(grandParentInfo.summary) \(grandParentInfo.labels.joined(separator: " "))".lowercased()
                parentDomain = classifyTextToDomain(grandParentText)
            }
            
            parentDomainCache[parentKey] = parentDomain
        }
        
        return issues.filter { issue in
            // 강제 매핑 체크
            if let forcedDomain = forcedDomainMapping[issue.key] {
                return forcedDomain == targetDomain
            }
            
            // 상위 티켓 도메인 상속
            if let parentKey = issue.parentKey,
               let parentDomain = parentDomainCache[parentKey],
               parentDomain != "etc" {
                return parentDomain == targetDomain
            }
            
            // 자체 분류
            let issueDomain = classifyIssueToDomain(issue)
            return issueDomain == targetDomain
        }
    }
    
    private func classifyTextToDomain(_ text: String) -> String {
        let lowercased = text.lowercased()
        
        for (key, config) in domainKeywords {
            if key == "etc" { continue }
            for keyword in config.keywords {
                if lowercased.contains(keyword.lowercased()) {
                    return key
                }
            }
        }
        
        return "etc"
    }
    
    private func classifyIssueToDomain(_ issue: BasicIssue) -> String {
        let text = "\(issue.summary) \(issue.labels.joined(separator: " "))".lowercased()
        return classifyTextToDomain(text)
    }
    
    // MARK: - Markdown Generation
    
    private func generateDetailMarkdown(
        domain: String,
        config: DomainConfig,
        issues: [DetailedIssue],
        user: JiraUser?,
        startYear: Int,
        endYear: Int
    ) -> String {
        var md = """
        # \(config.displayName) - 상세 데이터
        
        > **추출 일시**: \(ISO8601DateFormatter().string(from: Date()))
        > **담당자**: \(user?.displayName ?? "Unknown")
        > **기간**: \(startYear) - \(endYear)
        > **총 이슈**: \(issues.count)건
        
        ---
        
        ## 📊 요약
        
        """
        
        // 연도별 통계
        let yearStats = Dictionary(grouping: issues) { $0.year }
            .mapValues { $0.count }
            .sorted { $0.key < $1.key }
        
        md += "### 연도별 분포\n\n"
        md += "| 연도 | 이슈 수 |\n"
        md += "|------|--------|\n"
        for (year, count) in yearStats {
            md += "| \(year) | \(count) |\n"
        }
        md += "\n"
        
        // 쿼터별 통계
        let quarterStats = Dictionary(grouping: issues) { "\($0.year)-Q\($0.quarter)" }
            .mapValues { $0.count }
            .sorted { $0.key < $1.key }
        
        md += "### 쿼터별 분포\n\n"
        md += "| 기간 | 이슈 수 |\n"
        md += "|------|--------|\n"
        for (quarter, count) in quarterStats {
            md += "| \(quarter) | \(count) |\n"
        }
        md += "\n"
        
        // 상위 티켓(Epic/Story) 그룹별 통계
        let parentStats = Dictionary(grouping: issues.filter { $0.parentKey != nil }) { $0.parentKey! }
        md += "### 상위 티켓별 분포\n\n"
        md += "| Epic/Story | 이슈 수 |\n"
        md += "|------------|--------|\n"
        for (parentKey, groupIssues) in parentStats.sorted(by: { $0.value.count > $1.value.count }).prefix(20) {
            let parentSummary = groupIssues.first?.parentSummary ?? parentKey
            md += "| [\(parentKey)] \(parentSummary.prefix(40)) | \(groupIssues.count) |\n"
        }
        md += "\n"
        
        md += "---\n\n"
        md += "## 📋 상세 이슈 목록\n\n"
        
        // 연도/쿼터별로 그룹화
        let groupedIssues = Dictionary(grouping: issues) { "\($0.year)-Q\($0.quarter)" }
            .sorted { $0.key < $1.key }
        
        for (period, periodIssues) in groupedIssues {
            md += "### 📅 \(period)\n\n"
            
            for issue in periodIssues.sorted(by: { $0.createdDate < $1.createdDate }) {
                md += "---\n\n"
                md += "#### [\(issue.key)](\(issue.link)) \(issue.summary)\n\n"
                
                // 메타 정보
                md += "- **상태**: \(issue.status)\n"
                md += "- **타입**: \(issue.issueType)\n"
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                md += "- **생성일**: \(dateFormatter.string(from: issue.createdDate))\n"
                
                if let parentKey = issue.parentKey, let parentSummary = issue.parentSummary {
                    md += "- **상위 티켓**: [\(parentKey)] \(parentSummary)\n"
                }
                md += "\n"
                
                // 설명 (Description)
                if !issue.description.isEmpty {
                    md += "**📝 설명**\n\n"
                    md += "```\n"
                    md += issue.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000)
                    md += "\n```\n\n"
                }
                
                // 첨부파일
                if !issue.attachments.isEmpty {
                    md += "**📎 첨부파일 (\(issue.attachments.count))**\n\n"
                    for attachment in issue.attachments {
                        let sizeKB = attachment.size / 1024
                        md += "- `\(attachment.filename)` (\(attachment.mimeType), \(sizeKB)KB)\n"
                    }
                    md += "\n"
                }
                
                // 댓글
                if !issue.comments.isEmpty {
                    md += "**💬 댓글 (\(issue.comments.count))**\n\n"
                    for (index, comment) in issue.comments.prefix(10).enumerated() {
                        md += "<details>\n"
                        md += "<summary>\(index + 1). \(comment.author) - \(comment.created.prefix(10))</summary>\n\n"
                        md += "```\n"
                        md += comment.body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)
                        md += "\n```\n\n"
                        md += "</details>\n\n"
                    }
                    if issue.comments.count > 10 {
                        md += "_... 외 \(issue.comments.count - 10)개 댓글_\n\n"
                    }
                }
                
                md += "\n"
            }
        }
        
        return md
    }
}

// MARK: - Supporting Types

struct BasicIssue {
    let key: String
    let summary: String
    let createdDate: Date
    let quarter: Int
    let labels: [String]
    let parentKey: String?
    let parentSummary: String?
    let parentType: String?
    let issueType: String
    let status: String
    let link: String
}

struct DetailedIssue {
    let key: String
    let summary: String
    let description: String
    let createdDate: Date
    let year: Int
    let quarter: Int
    let parentKey: String?
    let parentSummary: String?
    let parentType: String?
    let issueType: String
    let status: String
    let link: String
    let comments: [CommentData]
    let attachments: [AttachmentData]
}

struct CommentData {
    let author: String
    let body: String
    let created: String
}

struct AttachmentData {
    let filename: String
    let mimeType: String
    let size: Int
    let url: String
}
