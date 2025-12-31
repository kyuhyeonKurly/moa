import Vapor
import Foundation

/// Jira 이슈의 하위 티켓들을 트리 구조로 출력하는 CLI 커맨드
/// Usage: swift run App jira-tree --issue KMA-5788 [--depth 3] [--export ./output.md]
struct JiraTreeCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "issue", short: "i", help: "Root issue key (Epic, Story, etc.)")
        var issue: String?
        
        @Option(name: "depth", short: "d", help: "Maximum depth to traverse (default: 5)")
        var depth: Int?
        
        @Option(name: "export", short: "e", help: "Export to markdown file")
        var export: String?
        
        @Flag(name: "verbose", short: "v", help: "Show detailed information (description, etc.)")
        var verbose: Bool
        
        @Flag(name: "links", short: "l", help: "Include linked issues and Confluence pages")
        var includeLinks: Bool
    }
    
    var help: String {
        "Display Jira issue hierarchy as a tree structure"
    }
    
    func run(using context: CommandContext, signature: Signature) throws {
        guard let issueKey = signature.issue else {
            context.console.error("❌ --issue (-i) is required. Example: --issue KMA-5788")
            return
        }
        
        let maxDepth = signature.depth ?? 5
        let verbose = signature.verbose
        let includeLinks = signature.includeLinks
        let exportPath = signature.export
        
        guard let email = Environment.get("JIRA_EMAIL"),
              let token = Environment.get("JIRA_TOKEN") else {
            context.console.error("❌ JIRA_EMAIL and JIRA_TOKEN must be set in .env")
            return
        }
        
        let app = context.application
        let client = JiraAPIClient(client: app.client, email: email, token: token)
        
        context.console.print("🌳 Building issue tree for \(issueKey)...")
        context.console.print("   Max depth: \(maxDepth)")
        if includeLinks {
            context.console.print("   Including: Issue Links, Confluence Pages")
        }
        context.console.print("")
        
        // 동기 실행을 위한 DispatchGroup
        let group = DispatchGroup()
        
        // nonisolated 클로저를 위한 Sendable 래퍼
        final class ResultBox: @unchecked Sendable {
            var treeResult: IssueTreeNode?
            var linkedIssues: [LinkedIssueInfo] = []
            var confluenceLinks: [ConfluenceLinkInfo] = []
            var errorMessage: String?
        }
        let box = ResultBox()
        
        group.enter()
        Task { @MainActor in
            do {
                // 루트 이슈 가져오기
                let rootIssue = try await self.fetchIssueForTree(client: client, issueKey: issueKey)
                
                // 트리 구조 빌드
                var visited = Set<String>()
                let tree = try await self.buildTree(
                    client: client,
                    issue: rootIssue,
                    depth: 0,
                    maxDepth: maxDepth,
                    visited: &visited
                )
                box.treeResult = tree
                
                // 연결된 이슈와 Confluence 링크 가져오기
                if includeLinks {
                    box.linkedIssues = try await self.fetchIssueLinks(client: client, issueKey: issueKey)
                    box.confluenceLinks = try await self.fetchConfluenceLinks(client: client, issueKey: issueKey)
                }
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
        
        guard let tree = box.treeResult else {
            context.console.error("❌ Failed to build tree")
            return
        }
        
        // 트리 출력
        var output = ""
        output += "# 📋 Issue Tree: \(issueKey)\n\n"
        output += renderTree(node: tree, prefix: "", isLast: true, verbose: verbose)
        output += "\n"
        
        // 연결된 이슈 출력
        if includeLinks && !box.linkedIssues.isEmpty {
            output += "---\n"
            output += "## 🔗 Linked Issues\n\n"
            for link in box.linkedIssues {
                let icon = issueTypeIcon(link.issueType)
                let statusIcon = self.statusIcon(link.status)
                output += "- \(link.relationship): \(icon) **[\(link.key)](\(link.url))** - \(link.summary)\n"
                output += "  - \(statusIcon) \(link.status)\n"
            }
            output += "\n"
        }
        
        // Confluence 링크 출력
        if includeLinks && !box.confluenceLinks.isEmpty {
            output += "---\n"
            output += "## 📚 Confluence Pages\n\n"
            
            // Wiki Page (직접 연결)와 mentioned in (언급됨) 분리
            let wikiPages = box.confluenceLinks.filter { $0.relationship.lowercased().contains("wiki") }
            let mentions = box.confluenceLinks.filter { $0.relationship.lowercased().contains("mention") }
            
            if !wikiPages.isEmpty {
                output += "### 📄 Wiki Pages (Direct Links)\n"
                for link in wikiPages {
                    output += "- [\(link.title)](\(link.url))\n"
                }
                output += "\n"
            }
            
            if !mentions.isEmpty {
                output += "### 💬 Mentioned In\n"
                for link in mentions {
                    output += "- [\(link.title)](\(link.url))\n"
                }
                output += "\n"
            }
        }
        
        // 통계
        let stats = calculateStats(node: tree)
        output += "---\n"
        output += "## 📊 Statistics\n\n"
        output += "- **Total Issues**: \(stats.total)\n"
        output += "- **By Type**:\n"
        for (type, count) in stats.byType.sorted(by: { $0.key < $1.key }) {
            output += "  - \(type): \(count)\n"
        }
        output += "- **By Status**:\n"
        for (status, count) in stats.byStatus.sorted(by: { $0.key < $1.key }) {
            output += "  - \(status): \(count)\n"
        }
        
        // 출력 또는 파일 저장
        if let exportPath = exportPath {
            do {
                let url = URL(fileURLWithPath: exportPath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try output.write(to: url, atomically: true, encoding: .utf8)
                context.console.success("✅ Exported to: \(exportPath)")
            } catch {
                context.console.error("❌ Failed to export: \(error.localizedDescription)")
            }
        } else {
            context.console.print(output)
        }
    }
    
    // MARK: - Tree Building
    
    private func fetchIssueForTree(client: JiraAPIClient, issueKey: String) async throws -> TreeIssue {
        let fields = ["summary", "status", "issuetype", "assignee", "subtasks", "parent", "description", "issuelinks"]
        let uri = URI(string: "\(client.apiBaseURL)/rest/api/3/issue/\(issueKey)?fields=\(fields.joined(separator: ","))&expand=subtasks")
        
        let response = try await client.client.get(uri, headers: client.headers)
        
        guard response.status == .ok else {
            throw Abort(.notFound, reason: "Issue not found: \(issueKey)")
        }
        
        return try response.content.decode(TreeIssue.self)
    }
    
    // MARK: - Issue Links
    
    private func fetchIssueLinks(client: JiraAPIClient, issueKey: String) async throws -> [LinkedIssueInfo] {
        let uri = URI(string: "\(client.apiBaseURL)/rest/api/3/issue/\(issueKey)?fields=issuelinks")
        let response = try await client.client.get(uri, headers: client.headers)
        
        guard response.status == .ok else { return [] }
        
        let issueData = try response.content.decode(IssueLinkResponse.self)
        guard let links = issueData.fields.issuelinks else { return [] }
        
        var result: [LinkedIssueInfo] = []
        for link in links {
            // inwardIssue: 이 이슈를 참조하는 이슈
            if let inward = link.inwardIssue {
                result.append(LinkedIssueInfo(
                    key: inward.key,
                    summary: inward.fields.summary,
                    status: inward.fields.status.name,
                    issueType: inward.fields.issuetype?.name ?? "Unknown",
                    relationship: "⬅️ \(link.type.inward)",
                    url: "https://kurly0521.atlassian.net/browse/\(inward.key)"
                ))
            }
            // outwardIssue: 이 이슈가 참조하는 이슈
            if let outward = link.outwardIssue {
                result.append(LinkedIssueInfo(
                    key: outward.key,
                    summary: outward.fields.summary,
                    status: outward.fields.status.name,
                    issueType: outward.fields.issuetype?.name ?? "Unknown",
                    relationship: "➡️ \(link.type.outward)",
                    url: "https://kurly0521.atlassian.net/browse/\(outward.key)"
                ))
            }
        }
        return result
    }
    
    // MARK: - Confluence Remote Links
    
    private func fetchConfluenceLinks(client: JiraAPIClient, issueKey: String) async throws -> [ConfluenceLinkInfo] {
        let uri = URI(string: "\(client.apiBaseURL)/rest/api/3/issue/\(issueKey)/remotelink")
        let response = try await client.client.get(uri, headers: client.headers)
        
        guard response.status == .ok else { return [] }
        
        let links = try response.content.decode([RemoteLinkResponse].self)
        
        return links.compactMap { link -> ConfluenceLinkInfo? in
            // Confluence 링크만 필터링
            guard link.application?.type?.contains("confluence") == true else { return nil }
            return ConfluenceLinkInfo(
                title: link.object.title,
                url: link.object.url,
                relationship: link.relationship ?? "Wiki Page"
            )
        }
    }
    
    private func fetchChildIssues(client: JiraAPIClient, parentKey: String) async throws -> [TreeIssue] {
        // Epic의 하위 이슈들 또는 Parent Link로 연결된 이슈들 검색
        let jql = """
        "Epic Link" = \(parentKey) OR parent = \(parentKey) ORDER BY issuetype ASC, key ASC
        """
        
        let searchRequest = JiraSearchRequest(
            jql: jql,
            fields: ["summary", "status", "issuetype", "assignee", "subtasks", "parent", "description"],
            maxResults: 100,
            nextPageToken: nil
        )
        
        let uri = URI(string: "\(client.apiBaseURL)/rest/api/3/search/jql")
        let response = try await client.client.post(uri, headers: client.headers) { req in
            try req.content.encode(searchRequest)
        }
        
        guard response.status == .ok else {
            return []
        }
        
        let searchResponse = try response.content.decode(TreeSearchResponse.self)
        return searchResponse.issues
    }
    
    private func buildTree(
        client: JiraAPIClient,
        issue: TreeIssue,
        depth: Int,
        maxDepth: Int,
        visited: inout Set<String>
    ) async throws -> IssueTreeNode {
        // 순환 참조 방지
        guard !visited.contains(issue.key) else {
            return IssueTreeNode(issue: issue, children: [], depth: depth)
        }
        visited.insert(issue.key)
        
        var children: [IssueTreeNode] = []
        
        if depth < maxDepth {
            // 1. Epic Link 또는 Parent Link로 연결된 하위 이슈들
            let childIssues = try await fetchChildIssues(client: client, parentKey: issue.key)
            
            for childIssue in childIssues {
                if !visited.contains(childIssue.key) {
                    let childNode = try await buildTree(
                        client: client,
                        issue: childIssue,
                        depth: depth + 1,
                        maxDepth: maxDepth,
                        visited: &visited
                    )
                    children.append(childNode)
                }
            }
            
            // 2. Subtasks (별도로 가져오기)
            if let subtasks = issue.fields.subtasks {
                for subtaskRef in subtasks {
                    if !visited.contains(subtaskRef.key) {
                        do {
                            let subtaskIssue = try await fetchIssueForTree(client: client, issueKey: subtaskRef.key)
                            let subtaskNode = try await buildTree(
                                client: client,
                                issue: subtaskIssue,
                                depth: depth + 1,
                                maxDepth: maxDepth,
                                visited: &visited
                            )
                            children.append(subtaskNode)
                        } catch {
                            // Subtask fetch 실패시 스킵
                            continue
                        }
                    }
                }
            }
        }
        
        // 이슈 타입별 정렬 (Epic > Story > Task > Sub-task > Bug)
        children.sort { node1, node2 in
            let priority1 = issueTypePriority(node1.issue.fields.issuetype.name)
            let priority2 = issueTypePriority(node2.issue.fields.issuetype.name)
            if priority1 != priority2 {
                return priority1 < priority2
            }
            return node1.issue.key < node2.issue.key
        }
        
        return IssueTreeNode(issue: issue, children: children, depth: depth)
    }
    
    private func issueTypePriority(_ typeName: String) -> Int {
        switch typeName.lowercased() {
        case "epic", "에픽": return 0
        case "story", "스토리": return 1
        case "task", "작업": return 2
        case "sub-task", "하위 작업": return 3
        case "bug", "버그": return 4
        default: return 5
        }
    }
    
    // MARK: - Tree Rendering
    
    private func renderTree(node: IssueTreeNode, prefix: String, isLast: Bool, verbose: Bool) -> String {
        var output = ""
        
        // 트리 브랜치 문자
        let branch = isLast ? "└── " : "├── "
        let childPrefix = isLast ? "    " : "│   "
        
        // 이슈 타입 아이콘
        let typeIcon = issueTypeIcon(node.issue.fields.issuetype.name)
        
        // 상태 아이콘
        let statusIcon = statusIcon(node.issue.fields.status.name)
        
        // 담당자
        let assignee = node.issue.fields.assignee?.displayName ?? "Unassigned"
        
        // 기본 출력
        if node.depth == 0 {
            output += "\(typeIcon) **\(node.issue.key)** - \(node.issue.fields.summary)\n"
            output += "   Status: \(statusIcon) \(node.issue.fields.status.name) | Assignee: \(assignee)\n"
        } else {
            output += "\(prefix)\(branch)\(typeIcon) **\(node.issue.key)** - \(node.issue.fields.summary)\n"
            output += "\(prefix)\(childPrefix)   \(statusIcon) \(node.issue.fields.status.name) | \(assignee)\n"
        }
        
        // Verbose 모드: description 일부 출력
        if verbose, let desc = node.issue.fields.description?.toPlainText(), !desc.isEmpty {
            let truncated = String(desc.prefix(200)).replacingOccurrences(of: "\n", with: " ")
            let displayPrefix = node.depth == 0 ? "   " : "\(prefix)\(childPrefix)   "
            output += "\(displayPrefix)📝 \(truncated)...\n"
        }
        
        output += "\n"
        
        // 자식 노드 렌더링
        for (index, child) in node.children.enumerated() {
            let isChildLast = index == node.children.count - 1
            let newPrefix = node.depth == 0 ? "" : "\(prefix)\(childPrefix)"
            output += renderTree(node: child, prefix: newPrefix, isLast: isChildLast, verbose: verbose)
        }
        
        return output
    }
    
    private func issueTypeIcon(_ typeName: String) -> String {
        switch typeName.lowercased() {
        case "epic", "에픽": return "🟣"
        case "story", "스토리": return "🟢"
        case "task", "작업": return "🔵"
        case "sub-task", "하위 작업": return "⚪"
        case "bug", "버그": return "🔴"
        case "improvement", "개선": return "🟡"
        case "design", "디자인": return "🎨"
        default: return "⬜"
        }
    }
    
    private func statusIcon(_ statusName: String) -> String {
        let lowered = statusName.lowercased()
        if lowered.contains("done") || lowered.contains("완료") {
            return "✅"
        } else if lowered.contains("progress") || lowered.contains("진행") {
            return "🔄"
        } else if lowered.contains("review") || lowered.contains("검토") {
            return "👀"
        } else {
            return "📋"
        }
    }
    
    // MARK: - Statistics
    
    private func calculateStats(node: IssueTreeNode) -> TreeStats {
        var stats = TreeStats()
        calculateStatsRecursive(node: node, stats: &stats)
        return stats
    }
    
    private func calculateStatsRecursive(node: IssueTreeNode, stats: inout TreeStats) {
        stats.total += 1
        
        let typeName = node.issue.fields.issuetype.name
        stats.byType[typeName, default: 0] += 1
        
        let statusName = node.issue.fields.status.name
        stats.byStatus[statusName, default: 0] += 1
        
        for child in node.children {
            calculateStatsRecursive(node: child, stats: &stats)
        }
    }
}

// MARK: - Models for Tree

struct IssueTreeNode {
    let issue: TreeIssue
    let children: [IssueTreeNode]
    let depth: Int
}

struct TreeIssue: Content {
    let key: String
    let fields: TreeIssueFields
}

struct TreeIssueFields: Content {
    let summary: String
    let status: TreeStatus
    let issuetype: TreeIssueType
    let assignee: TreeAssignee?
    let subtasks: [TreeSubtaskRef]?
    let parent: TreeParentRef?
    let description: ADFDocument?
}

struct TreeStatus: Content {
    let name: String
}

struct TreeIssueType: Content {
    let name: String
    let subtask: Bool?
}

struct TreeAssignee: Content {
    let displayName: String
}

struct TreeSubtaskRef: Content {
    let key: String
}

struct TreeParentRef: Content {
    let key: String
}

struct TreeSearchResponse: Content {
    let issues: [TreeIssue]
    let total: Int?
}

struct TreeStats {
    var total: Int = 0
    var byType: [String: Int] = [:]
    var byStatus: [String: Int] = [:]
}

// MARK: - Issue Links Models

struct LinkedIssueInfo {
    let key: String
    let summary: String
    let status: String
    let issueType: String
    let relationship: String
    let url: String
}

struct ConfluenceLinkInfo {
    let title: String
    let url: String
    let relationship: String
}

struct IssueLinkResponse: Content {
    let fields: IssueLinkFields
}

struct IssueLinkFields: Content {
    let issuelinks: [IssueLink]?
}

struct IssueLink: Content {
    let id: String
    let type: IssueLinkType
    let inwardIssue: LinkedIssue?
    let outwardIssue: LinkedIssue?
}

struct IssueLinkType: Content {
    let name: String
    let inward: String
    let outward: String
}

struct LinkedIssue: Content {
    let key: String
    let fields: LinkedIssueFields
}

struct LinkedIssueFields: Content {
    let summary: String
    let status: LinkedIssueStatus
    let issuetype: LinkedIssueType?
}

struct LinkedIssueStatus: Content {
    let name: String
}

struct LinkedIssueType: Content {
    let name: String
}

// MARK: - Remote Links (Confluence) Models

struct RemoteLinkResponse: Content {
    let id: Int
    let relationship: String?
    let application: RemoteLinkApplication?
    let object: RemoteLinkObject
}

struct RemoteLinkApplication: Content {
    let type: String?
    let name: String?
}

struct RemoteLinkObject: Content {
    let url: String
    let title: String
}
