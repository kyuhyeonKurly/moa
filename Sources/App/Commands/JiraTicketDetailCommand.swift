import Vapor
import Foundation

/// 특정 티켓 리스트의 상세 정보 조회 및 도메인 분류
/// Usage: swift run App jira-ticket-detail "KMA-4817,KMA-4764,KMA-4799"
struct JiraTicketDetailCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "keys", help: "Comma-separated issue keys")
        var keys: String
        
        @Option(name: "output", short: "o", help: "Output file path")
        var output: String?
    }
    
    var help: String {
        "Fetch detailed information for specific tickets and classify by domain"
    }
    
    // 도메인 키워드 매핑
    private let domainKeywords: [String: (emoji: String, keywords: [String])] = [
        "검색": ("🔍", ["검색", "search", "자동완성", "autocomplete", "srp", "검색결과"]),
        "장바구니": ("🛒", ["장바구니", "cart", "담기", "add_to_cart"]),
        "홈/전시": ("🏠", ["홈", "home", "컬리추천", "전시", "메인", "섹션", "배너"]),
        "카테고리": ("📂", ["카테고리", "category", "컬렉션", "collection"]),
        "마이컬리": ("👤", ["마이컬리", "mykurly", "회원", "멤버십"]),
        "실험": ("🧪", ["growthbook", "그로스북", "ab테스트", "실험", "피쳐플래그"]),
        "플랫폼/인프라": ("🏗️", ["리팩토링", "모듈", "spm", "tuist", "빌드", "ci", "cd", "코어", "내재화"]),
        "디자인시스템": ("🎨", ["kpds", "디자인", "컴포넌트", "네비게이션"]),
        "상품": ("🛍️", ["상품", "product", "pdp", "상세"]),
        "필터": ("🗂️", ["필터", "filter", "정렬", "sort"]),
        "MMP/마케팅": ("📊", ["appsflyer", "앱스플라이어", "mmp", "branch", "마케팅"]),
        "AI": ("🤖", ["ai", "llm", "온디바이스", "siri", "app intents"]),
        "이벤트/트래킹": ("📈", ["amplitude", "앰플리튜드", "이벤트", "트래킹", "로그"])
    ]
    
    func run(using context: CommandContext, signature: Signature) throws {
        let keys = signature.keys.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let outputPath = signature.output ?? "./exports/ticket-detail_\(keys.count)_\(Date().timeIntervalSince1970).md"
        
        guard let email = Environment.get("JIRA_EMAIL"),
              let token = Environment.get("JIRA_TOKEN") else {
            context.console.error("❌ JIRA_EMAIL and JIRA_TOKEN must be set in .env")
            return
        }
        
        let app = context.application
        let client = JiraAPIClient(client: app.client, email: email, token: token)
        
        context.console.print("🔍 Fetching \(keys.count) tickets...")
        
        let group = DispatchGroup()
        
        final class ResultBox: @unchecked Sendable {
            var tickets: [TicketDetail] = []
            var errorMessage: String?
        }
        let box = ResultBox()
        
        group.enter()
        Task { @MainActor in
            do {
                for key in keys {
                    context.console.print("   Fetching \(key)...")
                    
                    do {
                        let detail = try await client.fetchIssueDetail(issueKey: key)
                        
                        let ticket = TicketDetail(
                            key: key,
                            summary: detail.fields.summary,
                            description: detail.fields.description?.toPlainText() ?? "",
                            status: detail.fields.status.name,
                            issueType: detail.fields.issuetype.name,
                            created: detail.fields.created,
                            updated: detail.fields.updated,
                            resolutionDate: detail.fields.resolutiondate,
                            link: "https://kurly0521.atlassian.net/browse/\(key)",
                            comments: detail.fields.comment?.comments.map { comment in
                                CommentInfo(
                                    author: comment.author?.displayName ?? "Unknown",
                                    body: comment.body?.toPlainText() ?? "",
                                    created: comment.created
                                )
                            } ?? [],
                            attachments: detail.fields.attachment?.map { attachment in
                                AttachmentInfo(
                                    filename: attachment.filename,
                                    mimeType: attachment.mimeType ?? "unknown",
                                    size: attachment.size,
                                    url: attachment.content
                                )
                            } ?? [],
                            subtaskCount: detail.fields.subtasks?.count ?? 0,
                            linkedIssueCount: detail.fields.issuelinks?.count ?? 0,
                            labels: detail.fields.labels ?? []
                        )
                        
                        box.tickets.append(ticket)
                    } catch {
                        context.console.warning("⚠️ Failed: \(key)")
                    }
                }
                
                context.console.success("✅ Fetched \(box.tickets.count) tickets")
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
        
        // 도메인별 분류
        let domainGroups = classifyTicketsByDomain(tickets: box.tickets)
        
        // 마크다운 생성
        let output = generateMarkdown(domainGroups: domainGroups, totalCount: box.tickets.count)
        
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
    
    // MARK: - Domain Classification
    
    private func classifyTicketsByDomain(tickets: [TicketDetail]) -> [String: [TicketDetail]] {
        var groups: [String: [TicketDetail]] = [:]
        
        for ticket in tickets {
            let domain = detectDomain(from: ticket.summary)
            if groups[domain] == nil {
                groups[domain] = []
            }
            groups[domain]?.append(ticket)
        }
        
        return groups
    }
    
    private func detectDomain(from text: String) -> String {
        let lowercased = text.lowercased()
        
        for (domain, config) in domainKeywords {
            for keyword in config.keywords {
                if lowercased.contains(keyword.lowercased()) {
                    return domain
                }
            }
        }
        
        return "기타"
    }
    
    // MARK: - Markdown Generation
    
    private func generateMarkdown(domainGroups: [String: [TicketDetail]], totalCount: Int) -> String {
        var md = """
        # 티켓 상세 분석
        
        > **생성일시**: \(ISO8601DateFormatter().string(from: Date()))
        > **총 티켓**: \(totalCount)건
        
        ---
        
        ## 📊 도메인별 요약
        
        """
        
        let sortedDomains = domainGroups.keys.sorted()
        
        for domain in sortedDomains {
            let tickets = domainGroups[domain]!
            let emoji = domainKeywords[domain]?.emoji ?? "📦"
            md += "### \(emoji) \(domain) (\(tickets.count)건)\n\n"
            
            for ticket in tickets {
                md += "- **[\(ticket.key)](\(ticket.link))** \(ticket.summary)\n"
            }
            md += "\n"
        }
        
        md += "---\n\n"
        md += "## 📋 상세 내역\n\n"
        
        for domain in sortedDomains {
            let tickets = domainGroups[domain]!
            let emoji = domainKeywords[domain]?.emoji ?? "📦"
            
            md += "## \(emoji) \(domain)\n\n"
            
            for ticket in tickets {
                md += "---\n\n"
                md += "### [\(ticket.key)](\(ticket.link)) \(ticket.summary)\n\n"
                
                md += "- **상태**: \(ticket.status)\n"
                md += "- **타입**: \(ticket.issueType)\n"
                md += "- **생성일**: \(ticket.created.prefix(10))\n"
                
                if let updated = ticket.updated {
                    md += "- **업데이트**: \(updated.prefix(10))\n"
                }
                
                if let resolutionDate = ticket.resolutionDate {
                    md += "- **완료일**: \(resolutionDate.prefix(10))\n"
                }
                
                if ticket.subtaskCount > 0 {
                    md += "- **서브태스크**: \(ticket.subtaskCount)개\n"
                }
                
                if ticket.linkedIssueCount > 0 {
                    md += "- **연관 이슈**: \(ticket.linkedIssueCount)개\n"
                }
                
                if !ticket.labels.isEmpty {
                    md += "- **라벨**: \(ticket.labels.joined(separator: ", "))\n"
                }
                
                md += "\n"
                
                if !ticket.description.isEmpty {
                    md += "**📝 설명**\n\n"
                    md += "```\n"
                    md += ticket.description.prefix(2000)
                    md += "\n```\n\n"
                }
                
                if !ticket.attachments.isEmpty {
                    md += "**📎 첨부파일 (\(ticket.attachments.count))**\n\n"
                    for attachment in ticket.attachments {
                        let sizeKB = attachment.size / 1024
                        md += "- `\(attachment.filename)` (\(attachment.mimeType), \(sizeKB)KB)\n"
                    }
                    md += "\n"
                }
                
                if !ticket.comments.isEmpty {
                    md += "**💬 댓글 (\(ticket.comments.count))**\n\n"
                    for (index, comment) in ticket.comments.prefix(5).enumerated() {
                        md += "<details>\n"
                        md += "<summary>\(index + 1). \(comment.author) - \(comment.created.prefix(10))</summary>\n\n"
                        md += "```\n"
                        md += comment.body.prefix(1000)
                        md += "\n```\n\n"
                        md += "</details>\n\n"
                    }
                    if ticket.comments.count > 5 {
                        md += "_... 외 \(ticket.comments.count - 5)개 댓글_\n\n"
                    }
                }
                
                md += "\n"
            }
        }
        
        return md
    }
}

// MARK: - Supporting Types

struct TicketDetail {
    let key: String
    let summary: String
    let description: String
    let status: String
    let issueType: String
    let created: String
    let updated: String?
    let resolutionDate: String?
    let link: String
    let comments: [CommentInfo]
    let attachments: [AttachmentInfo]
    let subtaskCount: Int
    let linkedIssueCount: Int
    let labels: [String]
}

struct CommentInfo {
    let author: String
    let body: String
    let created: String
}

struct AttachmentInfo {
    let filename: String
    let mimeType: String
    let size: Int
    let url: String
}
