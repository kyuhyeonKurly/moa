import Vapor

/// 반기 성과 취합 → Confluence draft 생성 (CLI).
/// Usage: swift run App roundup-wiki -y 2026 --half 1 -s ~616f8e32860f78006bbc5560 [-p iOS]
/// 자격증명은 .env(JIRA_EMAIL / JIRA_TOKEN) 사용. 결과는 draft 페이지 편집 URL.
struct RoundupWikiCommand: Command {
    struct Signature: CommandSignature {
        @Option(name: "year", short: "y", help: "연도 (기본 2026)")
        var year: Int?
        @Option(name: "half", help: "반기 1=상반기 / 2=하반기 (기본 1)")
        var half: Int?
        @Option(name: "space", short: "s", help: "Confluence Space Key (예: ~616f8e...)")
        var space: String?
        @Option(name: "platform", short: "p", help: "iOS | Android | 비우면 전체")
        var platform: String?
    }

    var help: String { "반기 성과 취합 결과를 Confluence draft로 생성" }

    func run(using context: CommandContext, signature: Signature) throws {
        guard let email = Environment.get("JIRA_EMAIL"),
              let token = Environment.get("JIRA_TOKEN") else {
            context.console.error("❌ .env에 JIRA_EMAIL / JIRA_TOKEN 필요")
            return
        }
        guard let space = signature.space, !space.isEmpty else {
            context.console.error("❌ --space (Confluence Space Key) 필요")
            return
        }
        let year = signature.year ?? 2026
        let half = signature.half ?? 1
        let platform = signature.platform ?? ""
        let app = context.application

        context.console.print("🔍 \(year)년 \(half == 1 ? "상반기" : "하반기") 성과 취합 중...")

        final class ResultBox: @unchecked Sendable {
            var editUrl: String?
            var summary: String?
            var error: String?
        }
        let box = ResultBox()
        let group = DispatchGroup()
        group.enter()

        Task {
            do {
                let jira = JiraAPIClient(client: app.client, email: email, token: token)
                let calendar = try ReleaseCalendar.load(on: app)
                let service = RoundupService(apiClient: jira, calendar: calendar, logger: app.logger)
                let request = RoundupRequest(
                    year: year, half: half, platform: platform,
                    assignee: nil, email: email, token: token, spaceKey: space,
                    epicOverrides: nil
                )
                let ctx = try await service.collect(request: request)
                let user = try await jira.getMyself()
                let html = RoundupWikiRenderer.html(context: ctx, decisions: [:], userName: user.displayName)

                let confluence = ConfluenceService(client: app.client)
                let pageId = try await confluence.createPage(
                    spaceKey: space,
                    title: "\(ctx.halfLabel) 성과 취합 (\(user.displayName))",
                    htmlContent: html,
                    email: email,
                    token: token
                )
                box.editUrl = "https://kurly0521.atlassian.net/wiki/spaces/\(space)/pages/edit-v2/\(pageId)"
                box.summary = "총 \(ctx.totalCount) · 기획과제 \(ctx.planningCount) · 기술과제 \(ctx.technicalCount) · KTLO \(ctx.ktloCount) · 크래시 \(ctx.crashCount) · 검토 \(ctx.unversionedCount)"
            } catch {
                box.error = "\(error)"
            }
            group.leave()
        }

        group.wait()

        if let error = box.error {
            context.console.error("❌ 실패: \(error)")
            return
        }
        context.console.print("📊 \(box.summary ?? "")")
        context.console.print("✅ Draft 생성: \(box.editUrl ?? "")")
    }
}
