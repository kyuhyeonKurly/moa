import Vapor
import Foundation

/// 도메인별 세분화된 가이드라인 생성 - 에픽/주제 단위로 분기/월별 마일스톤 포함
/// Usage: swift run App jira-domain-guideline --start 2021 --end 2025 --output ./exports/domain-guideline.md
struct JiraDomainGuidelineCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "start", short: "s", help: "Start year (default: 2021)")
        var startYear: Int?
        
        @Option(name: "end", short: "e", help: "End year (default: current year)")
        var endYear: Int?
        
        @Option(name: "output", short: "o", help: "Output file path")
        var output: String?
        
        @Option(name: "domain", short: "d", help: "Filter by specific domain (search, cart, home, etc.)")
        var domain: String?
    }
    
    var help: String {
        "Generate domain-specific guidelines with granular milestones (epic/topic level)"
    }
    
    // 도메인 키워드 매핑 (더 세분화)
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
                "그로스북": ["growthbook", "growhbook", "그로스북", "ab테스트", "a/b 테스트"],
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
                "리팩토링": ["리팩토링", "개선", "레거시"],
                "iOS코어": ["attributedstring", "uilabel", "uikit", "코어"],
                "라이브러리": ["dynamiclinks", "외부라이브러리", "marqueelabel", "pinlayout", "내재화"]
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
                "검색결과": ["검색", "search", "srp"],
                "카테고리": ["카테고리", "category"],
                "컴렉션": ["컴렉션", "collection"]
            ]
        ),
        "mmp": DomainConfig(
            displayName: "📊 MMP/마케팅 (Marketing & Attribution)",
            keywords: ["appsflyer", "mmp", "어트리뷰션", "attribution", "마케팅", "branch", "링크"],
            subTopics: [
                "Appsflyer": ["appsflyer", "apps flyer"],
                "Branch": ["branch", "브랜치"],
                "어트리뷰션": ["어트리뷰션", "attribution", "mmp"]
            ]
        ),
        "ai": DomainConfig(
            displayName: "🤖 AI",
            keywords: ["foundation model", "ai", "llm", "관심사 추론", "개인화 알림", "온디바이스", "siri", "app intents", "agent skill", "에이전트 스킬"],
            subTopics: [
                "온디바이스AI": ["foundation model", "온디바이스", "llm", "siri", "app intents"],
                "개인화": ["관심사 추론", "개인화 알림", "실시간 개인화"],
                "AgentSkill": ["agent skill", "에이전트 스킬", "에이전트스킬"]
            ]
        ),
        "etc": DomainConfig(
            displayName: "📦 기타 (Uncategorized)",
            keywords: [],  // 빈 배열 - 분류 안되는 것들이 여기로
            subTopics: [
                "미분류": ["etc", "other"]
            ]
        ),
        "bugfix": DomainConfig(
            displayName: "🐛 버그수정 (Bug Fixes)",
            keywords: [],  // 빈 배열 - 버그 타입으로 분류
            subTopics: [:]
        ),
        "backlog": DomainConfig(
            displayName: "📋 백로그 (Backlog)",
            keywords: [],  // 빈 배열 - 미완료 티켓으로 분류
            subTopics: [:]
        )
    ]
    
    func run(using context: CommandContext, signature: Signature) throws {
        let startYear = signature.startYear ?? 2021
        let endYear = signature.endYear ?? Calendar.current.component(.year, from: Date())
        let outputPath = signature.output ?? "./exports/domain-guideline_\(startYear)-\(endYear).md"
        let filterDomain = signature.domain?.lowercased()
        
        guard let email = Environment.get("JIRA_EMAIL"),
              let token = Environment.get("JIRA_TOKEN") else {
            context.console.error("❌ JIRA_EMAIL and JIRA_TOKEN must be set in .env")
            return
        }
        
        let app = context.application
        let client = JiraAPIClient(client: app.client, email: email, token: token)
        
        context.console.print("📊 Generating Domain Guidelines...")
        context.console.print("   Years: \(startYear) - \(endYear)")
        if let domain = filterDomain {
            context.console.print("   Domain: \(domain)")
        }
        context.console.print("")
        
        // 동기 실행
        let group = DispatchGroup()
        
        final class ResultBox: @unchecked Sendable {
            var yearlyData: [Int: [GuidelineIssue]] = [:]
            var epicDetails: [String: EpicDetail] = [:]
            var parentInfo: [String: ParentInfo] = [:] // 상위 티켓 정보 캐시 (담당자 무관)
            var currentUser: JiraUser?
            var errorMessage: String?
        }
        let box = ResultBox()
        
        group.enter()
        Task { @MainActor in
            do {
                box.currentUser = try await client.getMyself()
                context.console.print("👤 User: \(box.currentUser?.displayName ?? "Unknown")")
                
                // 연도별 이슈 수집
                for year in startYear...endYear {
                    context.console.print("📅 Fetching \(year)...")
                    let issues = try await self.fetchYearlyIssues(client: client, year: year)
                    box.yearlyData[year] = issues
                }
                
                // 상위 티켓(parent) 정보 별도 조회 - 담당자 무관하게 조회
                context.console.print("🔗 Fetching parent issue details...")
                let allParentKeys = Set(box.yearlyData.values.flatMap { $0 }.compactMap { $0.parentKey })
                for parentKey in allParentKeys {
                    if let parentInfo = try? await self.fetchParentInfo(client: client, issueKey: parentKey) {
                        box.parentInfo[parentKey] = parentInfo
                    }
                }
                
                // 에픽 상세 정보 수집
                context.console.print("🔍 Fetching epic details...")
                let allEpicKeys = Set(box.yearlyData.values.flatMap { $0 }.compactMap { $0.parentKey })
                for epicKey in allEpicKeys.prefix(50) { // 최대 50개 에픽
                    if let epicDetail = try? await self.fetchEpicDetail(client: client, epicKey: epicKey) {
                        box.epicDetails[epicKey] = epicDetail
                    }
                }
                
                context.console.print("✅ Data collection complete!")
                let totalIssues = box.yearlyData.values.flatMap { $0 }.count
                context.console.print("📊 Total issues fetched: \(totalIssues)")
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
        
        // 도메인별로 분류
        let domainData = classifyByDomain(
            yearlyData: box.yearlyData,
            epicDetails: box.epicDetails,
            parentInfo: box.parentInfo,
            filterDomain: filterDomain
        )
        
        // 분류된 총 이슈 수 확인
        let classifiedTotal = domainData.values.map { $0.totalCount }.reduce(0, +)
        context.console.print("📊 Classified issues: \(classifiedTotal)")
        
        // 마크다운 생성
        let output = generateGuidelineMarkdown(
            domainData: domainData,
            parentInfoCache: box.parentInfo,
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
    
    private func fetchYearlyIssues(client: JiraAPIClient, year: Int) async throws -> [GuidelineIssue] {
        let nextYear = year + 1
        // KQA(QA팀 리그레이션) 프로젝트 제외 - 개발 성과로 보기 어려움
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
                fields: ["summary", "created", "status", "issuetype", "labels", "fixVersions", "parent", "assignee", "resolutiondate", "description"],
                maxResults: 100,
                nextPageToken: nextPageToken
            )
            allIssues.append(contentsOf: response.issues)
            nextPageToken = response.nextPageToken
        } while nextPageToken != nil
        
        // Jira 날짜 형식 파싱: "2024-03-15T10:30:00.000+0900"
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // 폴백용 기본 포맷터
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        
        return allIssues.map { issue in
            let createdString = issue.fields.created
            var createdDate = dateFormatter.date(from: createdString) 
                ?? fallbackFormatter.date(from: createdString) 
                ?? Date()
            
            // 디버그: 파싱 실패 시 수동 파싱 시도
            if createdDate == Date() {
                // "2024-03-15T10:30:00.000+0900" 형식에서 연/월 추출
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
            
            return GuidelineIssue(
                key: issue.key,
                summary: issue.fields.summary,
                description: "", // description은 JiraFields에 없으므로 빈 문자열
                createdDate: createdDate,
                month: month,
                quarter: quarter,
                labels: issue.fields.labels,
                link: "https://kurly0521.atlassian.net/browse/\(issue.key)",
                parentKey: issue.fields.parent?.key,
                parentSummary: issue.fields.parent?.fields.summary,
                parentType: issue.fields.parent?.fields.issuetype?.name,
                issueType: issue.fields.issuetype.name,
                status: issue.fields.status.name
            )
        }
    }
    
    private func fetchEpicDetail(client: JiraAPIClient, epicKey: String) async throws -> EpicDetail {
        let jql = "parent = \(epicKey) ORDER BY created ASC"
        
        let response = try await client.searchIssues(
            jql: jql,
            fields: ["summary", "created", "status", "issuetype"],
            maxResults: 50,
            nextPageToken: nil
        )
        
        return EpicDetail(
            key: epicKey,
            childCount: response.issues.count,
            childKeys: response.issues.map { $0.key }
        )
    }
    
    /// 상위 티켓 정보 조회 (담당자 무관하게 API로 직접 조회)
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
    
    // MARK: - Classification
    
    private func classifyByDomain(
        yearlyData: [Int: [GuidelineIssue]],
        epicDetails: [String: EpicDetail],
        parentInfo: [String: ParentInfo],
        filterDomain: String?
    ) -> [String: DomainData] {
        var result: [String: DomainData] = [:]
        
        // 초기화
        for (key, config) in domainKeywords {
            if let filter = filterDomain, key != filter { continue }
            result[key] = DomainData(config: config)
        }
        
        // 1단계: 상위 티켓 도메인 캐시 구축 (API로 조회한 parentInfo 활용)
        var parentDomainCache: [String: String] = [:] // parentKey -> domain
        
        for (parentKey, info) in parentInfo {
            // 상위 티켓 summary + labels로 도메인 분류
            let parentText = "\(info.summary) \(info.labels.joined(separator: " "))".lowercased()
            var parentDomain = classifyTextToDomain(parentText)
            
            // 상위 티켓도 etc면 grandParent(에픽) 확인
            if parentDomain == "etc", let grandParentKey = info.grandParentKey,
               let grandParentInfo = parentInfo[grandParentKey] {
                let grandParentText = "\(grandParentInfo.summary) \(grandParentInfo.labels.joined(separator: " "))".lowercased()
                parentDomain = classifyTextToDomain(grandParentText)
            }
            
            parentDomainCache[parentKey] = parentDomain
        }
        
        // 폴백: API 조회 못한 parent는 issue의 parentSummary 사용
        let allIssues = yearlyData.values.flatMap { $0 }
        for issue in allIssues {
            if let parentKey = issue.parentKey,
               parentDomainCache[parentKey] == nil,
               let parentSummary = issue.parentSummary {
                let parentText = parentSummary.lowercased()
                parentDomainCache[parentKey] = classifyTextToDomain(parentText)
            }
        }
        
        // 완료 상태 정규화 함수
        // 주의: CLOSE는 "취소"를 의미하므로 완료가 아님
        func isCompleted(_ status: String) -> Bool {
            let normalized = status.lowercased().replacingOccurrences(of: " ", with: "")
            // 완료 상태: done, resolved, resolve, 완료, 해결됨 (close/closed는 취소이므로 제외)
            return ["완료", "해결됨", "done", "resolved", "resolve"].contains(where: { normalized.contains($0) })
        }
        
        // 버그 타입 확인 함수
        func isBugType(_ issueType: String) -> Bool {
            let normalized = issueType.lowercased()
            return normalized.contains("bug") || normalized.contains("버그")
        }
        
        // 2단계: 이슈 분류 (버그/백로그 우선, 그 다음 상위 티켓 도메인 상속)
        for (year, issues) in yearlyData {
            for issue in issues {
                var domainKey: String
                
                // 1) 버그 타입 → 버그수정 카테고리
                if isBugType(issue.issueType) {
                    domainKey = "bugfix"
                }
                // 2) 미완료 티켓 → 백로그 카테고리
                else if !isCompleted(issue.status) {
                    domainKey = "backlog"
                }
                // 3) 상위 티켓 도메인 상속 우선, 없으면 자체 분류
                else if let parentKey = issue.parentKey,
                   let parentDomain = parentDomainCache[parentKey],
                   parentDomain != "etc" && parentDomain != "bugfix" && parentDomain != "backlog" {
                    domainKey = parentDomain
                } else {
                    domainKey = classifyIssueToDomain(issue)
                }
                
                if let filter = filterDomain, domainKey != filter { continue }
                
                if result[domainKey] == nil { continue }
                
                // 연도별 추가
                if result[domainKey]?.yearlyIssues[year] == nil {
                    result[domainKey]?.yearlyIssues[year] = []
                }
                result[domainKey]?.yearlyIssues[year]?.append(issue)
                
                // 서브토픽 분류 (bugfix/backlog는 원래 도메인 기반으로)
                let originalDomain: String
                if domainKey == "bugfix" || domainKey == "backlog" {
                    // 원래 분류될 도메인 찾기
                    if let parentKey = issue.parentKey,
                       let parentDomain = parentDomainCache[parentKey],
                       parentDomain != "etc" && parentDomain != "bugfix" && parentDomain != "backlog" {
                        originalDomain = parentDomain
                    } else {
                        originalDomain = classifyIssueToDomain(issue)
                    }
                } else {
                    originalDomain = domainKey
                }
                
                let subTopic: String
                if domainKey == "bugfix" || domainKey == "backlog" {
                    // 버그/백로그는 원래 도메인명을 서브토픽으로
                    subTopic = domainKeywords[originalDomain]?.displayName ?? "기타"
                } else {
                    subTopic = classifySubTopic(issue, config: domainKeywords[domainKey]!)
                }
                
                let topicKey = "\(year)-\(issue.quarter)Q-\(subTopic)"
                if result[domainKey]?.topicGroups[topicKey] == nil {
                    result[domainKey]?.topicGroups[topicKey] = TopicGroup(
                        year: year,
                        quarter: issue.quarter,
                        topic: subTopic
                    )
                }
                result[domainKey]?.topicGroups[topicKey]?.issues.append(issue)
                
                // 에픽별 그룹
                if let parentKey = issue.parentKey {
                    if result[domainKey]?.epicGroups[parentKey] == nil {
                        result[domainKey]?.epicGroups[parentKey] = EpicGroup(
                            epicKey: parentKey,
                            epicSummary: issue.parentSummary ?? parentKey,
                            childDetail: epicDetails[parentKey]
                        )
                    }
                    result[domainKey]?.epicGroups[parentKey]?.issues.append(issue)
                    result[domainKey]?.epicGroups[parentKey]?.years.insert(year)
                }
            }
        }
        
        return result
    }
    
    /// 텍스트 기반 도메인 분류 (상위 티켓 summary용)
    private func classifyTextToDomain(_ text: String) -> String {
        let lowercased = text.lowercased()
        
        // 우선순위대로 도메인 체크
        for domainKey in domainPriority {
            guard let config = domainKeywords[domainKey] else { continue }
            for keyword in config.keywords {
                if lowercased.contains(keyword.lowercased()) {
                    return domainKey
                }
            }
        }
        
        // 우선순위에 없는 도메인도 체크
        for (key, config) in domainKeywords {
            if key == "etc" || domainPriority.contains(key) { continue }
            for keyword in config.keywords {
                if lowercased.contains(keyword.lowercased()) {
                    return key
                }
            }
        }
        
        return "etc"
    }
    
    /// 특정 티켓 키에 대한 강제 도메인 매핑
    /// - KMA-4732: 개발자 모드 관련 딥링크 → 플랫폼/인프라
    /// - KMA-1922: 리모트 컨피그 딥링크 처리 → 실험
    /// - KMA-4540: 검색 > 딥링크 버그 → 검색
    private let forcedDomainMapping: [String: String] = [
        "KMA-4732": "platform",
        "KMA-1922": "experiment",
        "KMA-4540": "search"
    ]
    
    /// 도메인 우선순위 (특수 키워드 도메인이 일반 도메인보다 먼저 체크됨)
    /// experiment/mmp/platform/ai/filter 같은 특수 도메인이 product 같은 일반 도메인보다 우선
    /// search는 복합 키워드(검색 탭)가 design의 일반 키워드(컴포넌트)보다 우선해야 함
    private let domainPriority: [String] = [
        "experiment", // 실험 (그로스북, 피쳐플래그) - 최우선
        "mmp",        // MMP/마케팅 (Appsflyer, Branch)
        "filter",     // 필터/정렬 - 검색/카테고리보다 우선
        "ai",         // Foundation Model, 온디바이스 등
        "search",     // 검색 (검색 탭 등 복합 키워드)
        "platform",   // 리팩토링, 모듈화, iOS 코어
        "design",     // 디자인시스템
        "mykurly",    // 마이컬리
        "cart",       // 장바구니
        "category",   // 카테고리
        "home",       // 홈/전시
        "product",    // 상품 (일반)
    ]
    
    private func classifyIssueToDomain(_ issue: GuidelineIssue) -> String {
        // 1. 강제 매핑 우선 체크
        if let forcedDomain = forcedDomainMapping[issue.key] {
            return forcedDomain
        }
        
        let text = "\(issue.summary) \(issue.labels.joined(separator: " ")) \(issue.description)".lowercased()
        
        // 2. 우선순위대로 도메인 체크
        for domainKey in domainPriority {
            guard let config = domainKeywords[domainKey] else { continue }
            for keyword in config.keywords {
                if text.contains(keyword.lowercased()) {
                    return domainKey
                }
            }
        }
        
        // 3. 우선순위에 없는 도메인도 체크 (안전장치)
        for (key, config) in domainKeywords {
            if key == "etc" || domainPriority.contains(key) { continue }
            for keyword in config.keywords {
                if text.contains(keyword.lowercased()) {
                    return key
                }
            }
        }
        
        return "etc" // 분류 불가 시 etc로
    }
    
    private func classifySubTopic(_ issue: GuidelineIssue, config: DomainConfig) -> String {
        let text = "\(issue.summary) \(issue.labels.joined(separator: " "))".lowercased()
        
        for (topic, keywords) in config.subTopics {
            for keyword in keywords {
                if text.contains(keyword.lowercased()) {
                    return topic
                }
            }
        }
        
        return "작업" // 서브토픽 미분류
    }
    
    // MARK: - Markdown Generation
    
    private func generateGuidelineMarkdown(
        domainData: [String: DomainData],
        parentInfoCache: [String: ParentInfo],
        user: JiraUser?,
        startYear: Int,
        endYear: Int
    ) -> String {
        var md = ""
        
        // 헤더
        md += """
        # 📋 도메인별 개발 가이드라인 (\(startYear)-\(endYear))
        
        > **담당자**: \(user?.displayName ?? "Unknown")
        > **생성일**: \(ISO8601DateFormatter().string(from: Date()))
        > **형식**: 도메인 × 연도 × 분기/월 × 주제(에픽) 세분화
        > **목적**: AI 에이전트 문맥 주입용 - 누락 없는 원시 마일스톤 데이터
        
        ---
        
        ## 📊 도메인별 요약
        
        | 도메인 | 총 티켓 | 에픽 수 | 활동 연도 |
        |--------|---------|---------|-----------|
        
        """
        
        // 요약 테이블
        let sortedDomains = domainData.sorted { $0.value.totalCount > $1.value.totalCount }
        for (_, data) in sortedDomains {
            let totalCount = data.yearlyIssues.values.flatMap { $0 }.count
            let epicCount = data.epicGroups.count
            let years = Set(data.yearlyIssues.keys).sorted().map(String.init).joined(separator: ", ")
            md += "| \(data.config.displayName) | \(totalCount) | \(epicCount) | \(years) |\n"
        }
        
        md += "\n---\n\n"
        
        // 전체 이슈를 key로 인덱싱 (내 담당 티켓만)
        var allIssuesByKey: [String: GuidelineIssue] = [:]
        for (_, data) in domainData {
            for issues in data.yearlyIssues.values {
                for issue in issues {
                    allIssuesByKey[issue.key] = issue
                }
            }
        }
        
        // 각 도메인 상세
        for (domainKey, data) in sortedDomains {
            let totalCount = data.yearlyIssues.values.flatMap { $0 }.count
            if totalCount == 0 { continue }
            
            md += "# \(data.config.displayName)\n\n"
            md += "**총 \(totalCount)건** | **에픽 \(data.epicGroups.count)개**\n\n"
            
            // 버그수정 카테고리는 간단한 플랫 리스트로 출력
            if domainKey == "bugfix" {
                md += generateBugfixSection(data: data)
                continue
            }
            
            // 백로그 카테고리는 상태 표시 포함
            if domainKey == "backlog" {
                md += generateBacklogSection(data: data)
                continue
            }
            
            // 연도별 분기/주제 마일스톤
            let sortedYears = data.yearlyIssues.keys.sorted(by: >)
            
            for year in sortedYears {
                guard let yearIssues = data.yearlyIssues[year], !yearIssues.isEmpty else { continue }
                
                md += "## 📅 \(year)년 (\(yearIssues.count)건)\n\n"
                
                // 분기별 마일스톤 (Q4 → Q1 역순)
                for quarter in (1...4).reversed() {
                    let quarterIssues = yearIssues.filter { $0.quarter == quarter }
                    if quarterIssues.isEmpty { continue }
                    
                    md += "### Q\(quarter) (\(quarterIssues.count)건)\n\n"
                    
                    // 월별 세분화 (역순: 12→10, 9→7 등)
                    let monthStart = (quarter - 1) * 3 + 1
                    let monthEnd = quarter * 3
                    
                    for month in (monthStart...monthEnd).reversed() {
                        let monthIssues = quarterIssues.filter { $0.month == month }
                        if monthIssues.isEmpty { continue }
                        
                        md += "#### \(month)월 (\(monthIssues.count)건)\n\n"
                        
                        // 내 담당 상위 티켓 (에픽 또는 스토리 - 같은 월에 있는)
                        let myParentIssuesInMonth = monthIssues.filter { 
                            let t = $0.issueType.lowercased()
                            return t.contains("에픽") || t == "epic" || t.contains("스토리") || t == "story"
                        }
                        let myParentKeys = Set(myParentIssuesInMonth.map { $0.key })
                        
                        // 같은 월에 있는 티켓들 중 parentKey가 같은 것들 그룹화
                        // (상위 티켓이 내 담당이 아니어도 그룹화)
                        var parentChildrenMap: [String: [GuidelineIssue]] = [:]
                        var processedAsChild: Set<String> = []
                        
                        for issue in monthIssues {
                            let t = issue.issueType.lowercased()
                            let isParentType = t.contains("에픽") || t == "epic" || t.contains("스토리") || t == "story"
                            if isParentType { continue }
                            
                            if let parentKey = issue.parentKey {
                                // 같은 월에 같은 parent를 가진 티켓이 1개 이상이면 그룹화
                                let siblings = monthIssues.filter { $0.parentKey == parentKey }
                                if siblings.count >= 1 {
                                    parentChildrenMap[parentKey, default: []].append(issue)
                                    processedAsChild.insert(issue.key)
                                }
                            }
                        }
                        
                        // 각 이슈의 원래 서브토픽 저장
                        var originalSubTopic: [String: String] = [:]
                        for issue in monthIssues {
                            originalSubTopic[issue.key] = classifySubTopic(issue, config: data.config)
                        }
                        
                        // 상위 티켓(에픽/스토리)의 서브토픽 결정
                        var parentSubTopic: [String: String] = [:]
                        for parentKey in parentChildrenMap.keys {
                            if let myParent = myParentIssuesInMonth.first(where: { $0.key == parentKey }) {
                                // 내 담당 상위 티켓이면 그 서브토픽 사용
                                parentSubTopic[parentKey] = originalSubTopic[myParent.key] ?? "작업"
                            } else if let pInfo = parentInfoCache[parentKey] {
                                // 내 담당이 아닌 상위 티켓은 parentInfoCache에서 서브토픽 분류
                                let fakeIssue = GuidelineIssue(
                                    key: parentKey,
                                    summary: pInfo.summary,
                                    description: "",
                                    createdDate: Date(),
                                    month: month,
                                    quarter: quarter,
                                    labels: pInfo.labels,
                                    link: "https://kurly0521.atlassian.net/browse/\(parentKey)",
                                    parentKey: nil,
                                    parentSummary: nil,
                                    parentType: nil,
                                    issueType: pInfo.issueType,
                                    status: ""
                                )
                                parentSubTopic[parentKey] = classifySubTopic(fakeIssue, config: data.config)
                            } else {
                                parentSubTopic[parentKey] = "작업"
                            }
                        }
                        
                        // 서브토픽 그룹핑
                        var topicGroups: [String: [GuidelineIssue]] = [:]
                        var topicParentGroups: [String: [String]] = [:] // topic -> [parentKeys] (내 담당 아닌 상위 티켓)
                        
                        // 내 담당 상위 티켓 중 children이 있는 것들 (자신의 서브토픽에서 children과 함께 출력)
                        var parentsWithChildren: Set<String> = []
                        for issue in monthIssues {
                            let t = issue.issueType.lowercased()
                            let isParentType = t.contains("에픽") || t == "epic" || t.contains("스토리") || t == "story"
                            if isParentType && parentChildrenMap[issue.key] != nil {
                                parentsWithChildren.insert(issue.key)
                            }
                        }
                        
                        for issue in monthIssues {
                            let t = issue.issueType.lowercased()
                            let isParentType = t.contains("에픽") || t == "epic" || t.contains("스토리") || t == "story"
                            
                            if isParentType {
                                // 내 담당 상위 티켓은 자신의 서브토픽에 추가
                                let topic = originalSubTopic[issue.key] ?? "작업"
                                topicGroups[topic, default: []].append(issue)
                            } else if processedAsChild.contains(issue.key) {
                                // 상위 티켓의 children으로 처리될 티켓은 건너뜀
                                continue
                            } else {
                                // 독립 티켓
                                let topic = originalSubTopic[issue.key] ?? "작업"
                                topicGroups[topic, default: []].append(issue)
                            }
                        }
                        
                        // 내 담당이 아닌 상위 티켓을 해당 서브토픽에 추가
                        // (내 담당 상위 티켓은 이미 topicGroups에 추가되었으므로 제외)
                        // (이미 다른 상위 티켓의 child로 처리된 티켓도 제외)
                        // (monthIssues에 있는 티켓 - 즉 내 담당 티켓은 이미 topicGroups에 추가됨)
                        let monthIssueKeys = Set(monthIssues.map { $0.key })
                        for (parentKey, _) in parentChildrenMap {
                            if myParentKeys.contains(parentKey) { continue } // 내 담당 상위 티켓은 자신의 서브토픽에서 처리됨
                            if processedAsChild.contains(parentKey) { continue } // 이미 다른 상위의 child로 출력됨
                            if monthIssueKeys.contains(parentKey) { continue } // 내 담당 티켓은 topicGroups에서 처리됨
                            let topic = parentSubTopic[parentKey] ?? "작업"
                            topicParentGroups[topic, default: []].append(parentKey)
                        }
                        
                        // 토픽별 총 건수 계산
                        var topicCounts: [String: Int] = [:]
                        for (topic, issues) in topicGroups {
                            var count = issues.count
                            // 내 담당 에픽의 children 수
                            for issue in issues {
                                if let children = parentChildrenMap[issue.key] {
                                    count += children.count
                                }
                            }
                            topicCounts[topic] = count
                        }
                        // 내 담당 아닌 상위 티켓의 children 수
                        for (topic, parentKeys) in topicParentGroups {
                            for parentKey in parentKeys {
                                let childCount = parentChildrenMap[parentKey]?.count ?? 0
                                topicCounts[topic, default: 0] += childCount
                            }
                        }
                        
                        // 모든 토픽 수집 (topicGroups + topicParentGroups)
                        var allTopics = Set(topicGroups.keys)
                        for topic in topicParentGroups.keys {
                            allTopics.insert(topic)
                        }
                        
                        // 서브토픽 정렬: 건수 내림차순, 단 "작업"은 항상 맨 뒤
                        let sortedTopics = allTopics.sorted { lhs, rhs in
                            if lhs == "작업" { return false }
                            if rhs == "작업" { return true }
                            return (topicCounts[lhs] ?? 0) > (topicCounts[rhs] ?? 0)
                        }
                        
                        for topic in sortedTopics {
                            let totalCount = topicCounts[topic] ?? 0
                            if totalCount == 0 { continue }
                            md += "**[\(topic)]** (\(totalCount)건)\n\n"
                            
                            // 1. 내 담당 에픽/이슈 출력
                            if let issues = topicGroups[topic] {
                                for issue in issues {
                                    let issueIcon = issueTypeIcon(issue.issueType)
                                    let issueStatus = statusIcon(issue.status)
                                    let t = issue.issueType.lowercased()
                                    let isParentType = t.contains("에픽") || t == "epic" || t.contains("스토리") || t == "story"
                                    
                                    // 상위 타입이 아닌 일반 이슈의 parentInfo 처리
                                    var parentInfoStr = ""
                                    if !isParentType, let parentKey = issue.parentKey {
                                        if let parentIssue = allIssuesByKey[parentKey] {
                                            let parentYear = Calendar.current.component(.year, from: parentIssue.createdDate)
                                            let parentQuarter = parentIssue.quarter
                                            let parentTitle = parentIssue.summary
                                            if parentYear != year || parentQuarter != quarter {
                                                parentInfoStr = " ← \(parentKey): \(parentTitle) (\(parentYear) Q\(parentQuarter))"
                                            } else {
                                                parentInfoStr = " ← \(parentKey): \(parentTitle)"
                                            }
                                        } else if let pInfo = parentInfoCache[parentKey] {
                                            parentInfoStr = " ← \(parentKey): \(pInfo.summary)"
                                        } else {
                                            parentInfoStr = " ← \(parentKey)"
                                        }
                                    }
                                    
                                    md += "- \(issueIcon)\(issueStatus) [\(issue.key)](\(issue.link)) - \(issue.summary)\(parentInfoStr)\n"
                                    
                                    // 상위 타입(에픽/스토리)이면 하위 티켓 출력
                                    if isParentType, let children = parentChildrenMap[issue.key] {
                                        for child in children {
                                            let childIcon = issueTypeIcon(child.issueType)
                                            let childStatus = statusIcon(child.status)
                                            let childOriginalTopic = originalSubTopic[child.key] ?? "작업"
                                            
                                            var childSuffix = ""
                                            if childOriginalTopic != topic {
                                                childSuffix = " ← [\(childOriginalTopic)]"
                                            }
                                            
                                            md += "  - \(childIcon)\(childStatus) [\(child.key)](\(child.link)) - \(child.summary)\(childSuffix)\n"
                                        }
                                    }
                                }
                            }
                            
                            // 2. 내 담당이 아닌 상위 티켓 + children 출력
                            if let parentKeys = topicParentGroups[topic] {
                                for parentKey in parentKeys {
                                    guard let children = parentChildrenMap[parentKey], !children.isEmpty else { continue }
                                    
                                    // 상위 티켓 정보 가져오기 (parentInfoCache 우선, 없으면 하위 티켓의 parentSummary 사용)
                                    let parentTitle: String
                                    let parentType: String
                                    if let pInfo = parentInfoCache[parentKey] {
                                        parentTitle = pInfo.summary
                                        parentType = pInfo.issueType
                                    } else if let firstChild = children.first, let summary = firstChild.parentSummary {
                                        parentTitle = summary
                                        parentType = firstChild.parentType ?? "에픽"
                                    } else {
                                        parentTitle = "(상위 티켓)"
                                        parentType = "에픽"
                                    }
                                    
                                    let parentIcon = issueTypeIcon(parentType)
                                    md += "- \(parentIcon) [\(parentKey)](https://kurly0521.atlassian.net/browse/\(parentKey)) - \(parentTitle)\n"
                                    
                                    for child in children {
                                        let childIcon = issueTypeIcon(child.issueType)
                                        let childStatus = statusIcon(child.status)
                                        let childOriginalTopic = originalSubTopic[child.key] ?? "작업"
                                        
                                        var childSuffix = ""
                                        if childOriginalTopic != topic {
                                            childSuffix = " ← [\(childOriginalTopic)]"
                                        }
                                        
                                        md += "  - \(childIcon)\(childStatus) [\(child.key)](\(child.link)) - \(child.summary)\(childSuffix)\n"
                                    }
                                }
                            }
                            
                            md += "\n"
                        }
                    }
                }
            }
            
            md += "---\n\n"
        }
        
        // AI 분석용 서브토픽 인덱스
        md += """
        # 📖 AI 분석용 서브토픽 인덱스
        
        > 각 도메인의 세부 주제 분류 기준입니다.
        
        """
        
        for (_, config) in domainKeywords.sorted(by: { $0.key < $1.key }) {
            md += "## \(config.displayName)\n\n"
            for (topic, keywords) in config.subTopics {
                md += "- **\(topic)**: \(keywords.joined(separator: ", "))\n"
            }
            md += "\n"
        }
        
        return md
    }
    
    /// 버그수정 카테고리 전용 - 플랫 리스트 (트리 구조 없음)
    private func generateBugfixSection(data: DomainData) -> String {
        var md = ""
        let sortedYears = data.yearlyIssues.keys.sorted(by: >)
        
        for year in sortedYears {
            guard let yearIssues = data.yearlyIssues[year], !yearIssues.isEmpty else { continue }
            
            md += "## 📅 \(year)년 (\(yearIssues.count)건)\n\n"
            
            // 분기별 (Q4 → Q1 역순)
            for quarter in (1...4).reversed() {
                let quarterIssues = yearIssues.filter { $0.quarter == quarter }
                if quarterIssues.isEmpty { continue }
                
                md += "### Q\(quarter) (\(quarterIssues.count)건)\n\n"
                
                // 월별 (역순)
                let monthStart = (quarter - 1) * 3 + 1
                let monthEnd = quarter * 3
                
                for month in (monthStart...monthEnd).reversed() {
                    let monthIssues = quarterIssues.filter { $0.month == month }
                    if monthIssues.isEmpty { continue }
                    
                    md += "#### \(month)월 (\(monthIssues.count)건)\n\n"
                    
                    // 플랫하게 버그 티켓만 나열
                    for issue in monthIssues {
                        let issueIcon = issueTypeIcon(issue.issueType)
                        let issueStatus = statusIcon(issue.status)
                        md += "- \(issueIcon)\(issueStatus) [\(issue.key)](\(issue.link)) - \(issue.summary)\n"
                    }
                    
                    md += "\n"
                }
            }
        }
        
        md += "---\n\n"
        return md
    }
    
    /// 백로그 카테고리 전용 - 상태 표시 포함 (CLOSE = 취소됨)
    private func generateBacklogSection(data: DomainData) -> String {
        var md = ""
        let sortedYears = data.yearlyIssues.keys.sorted(by: >)
        
        for year in sortedYears {
            guard let yearIssues = data.yearlyIssues[year], !yearIssues.isEmpty else { continue }
            
            md += "## 📅 \(year)년 (\(yearIssues.count)건)\n\n"
            
            // 분기별 (Q4 → Q1 역순)
            for quarter in (1...4).reversed() {
                let quarterIssues = yearIssues.filter { $0.quarter == quarter }
                if quarterIssues.isEmpty { continue }
                
                md += "### Q\(quarter) (\(quarterIssues.count)건)\n\n"
                
                // 월별 (역순)
                let monthStart = (quarter - 1) * 3 + 1
                let monthEnd = quarter * 3
                
                for month in (monthStart...monthEnd).reversed() {
                    let monthIssues = quarterIssues.filter { $0.month == month }
                    if monthIssues.isEmpty { continue }
                    
                    md += "#### \(month)월 (\(monthIssues.count)건)\n\n"
                    
                    // 상태별로 표시 (CLOSE = 취소됨)
                    for issue in monthIssues {
                        let issueIcon = issueTypeIcon(issue.issueType)
                        let statusLabel = backlogStatusLabel(issue.status)
                        md += "- \(issueIcon) [\(issue.key)](\(issue.link)) - \(issue.summary) `\(statusLabel)`\n"
                    }
                    
                    md += "\n"
                }
            }
        }
        
        md += "---\n\n"
        return md
    }
    
    /// 백로그 상태 라벨 (CLOSE는 취소됨으로 표시)
    private func backlogStatusLabel(_ status: String) -> String {
        let normalized = status.lowercased().replacingOccurrences(of: " ", with: "")
        if normalized.contains("close") {
            return "취소됨"
        } else if normalized.contains("hold") || normalized == "대기" {
            return "보류"
        } else if normalized.contains("progress") || normalized.contains("진행") {
            return "진행중"
        } else if normalized.contains("qa") || normalized.contains("review") {
            return "QA/리뷰"
        } else {
            return status // 원본 상태 표시 (해야 할 일 등)
        }
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
    
    private func statusIcon(_ status: String) -> String {
        // 공백 제거 후 비교
        let normalized = status.lowercased().replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "done", "완료", "closed", "해결됨", "resolved": return "✅"
        case "inprogress", "진행중": return "🔄"
        case "review", "리뷰": return "👀"
        default: return ""
        }
    }
}

// MARK: - Models

struct DomainConfig {
    let displayName: String
    let keywords: [String]
    let subTopics: [String: [String]]
}

struct GuidelineIssue {
    let key: String
    let summary: String
    let description: String
    let createdDate: Date
    let month: Int
    let quarter: Int
    let labels: [String]
    let link: String
    let parentKey: String?
    let parentSummary: String?
    let parentType: String?
    let issueType: String
    let status: String
}

struct DomainData {
    let config: DomainConfig
    var yearlyIssues: [Int: [GuidelineIssue]] = [:]
    var topicGroups: [String: TopicGroup] = [:]
    var epicGroups: [String: EpicGroup] = [:]
    
    var totalCount: Int {
        yearlyIssues.values.flatMap { $0 }.count
    }
}

struct TopicGroup {
    let year: Int
    let quarter: Int
    let topic: String
    var issues: [GuidelineIssue] = []
}

struct EpicGroup {
    let epicKey: String
    let epicSummary: String
    let childDetail: EpicDetail?
    var issues: [GuidelineIssue] = []
    var years: Set<Int> = []
}

struct EpicDetail {
    let key: String
    let childCount: Int
    let childKeys: [String]
}

/// 상위 티켓(parent) 정보 - 담당자 무관하게 API 조회
struct ParentInfo {
    let key: String
    let summary: String
    let issueType: String
    let labels: [String]
    let grandParentKey: String?     // 상위의 상위 (에픽)
    let grandParentSummary: String?
}
