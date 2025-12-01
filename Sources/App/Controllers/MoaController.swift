import Vapor

struct MoaController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let moa = routes.grouped("moa")
        moa.get("collect", use: collectAndPublish)
    }

    func collectAndPublish(req: Request) async throws -> View {
        let year = req.query[Int.self, at: "year"] ?? 2023
        let assignee = req.query[String.self, at: "assignee"]
        let jiraService = JiraService(client: req.client)
        
        // 1. 이슈 모으기
        let issues = try await jiraService.fetchIssues(year: year, assignee: assignee, req: req)
        
        // 2. 데이터 가공 (Context 생성)
        let context = ReportGenerator.generateContext(issues: issues, year: year)
        
        // 3. Leaf 템플릿 렌더링
        return try await req.view.render("report", context)
    }
}
