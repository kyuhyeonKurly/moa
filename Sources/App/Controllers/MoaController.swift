import Vapor

struct MoaController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("", use: index)
        let moa = routes.grouped("moa")
        moa.get("collect", use: collectAndPublish)
        moa.post("collect", use: collectAndPublish)
    }

    func index(req: Request) async throws -> View {
        let hasToken = Environment.get("JIRA_TOKEN") != nil && !Environment.get("JIRA_TOKEN")!.isEmpty
        let hasEmail = Environment.get("JIRA_EMAIL") != nil && !Environment.get("JIRA_EMAIL")!.isEmpty
        return try await req.view.render("index", ["hasToken": hasToken, "hasEmail": hasEmail])
    }

    func collectAndPublish(req: Request) async throws -> View {
        let year = req.query[Int.self, at: "year"] ?? req.content[Int.self, at: "year"] ?? 2023
        let assignee = req.query[String.self, at: "assignee"] ?? req.content[String.self, at: "assignee"]
        
        let email = req.query[String.self, at: "email"] ?? req.content[String.self, at: "email"]
        let token = req.query[String.self, at: "token"] ?? req.content[String.self, at: "token"]
        
        let jiraService = JiraService(client: req.client)
        
        // 1. 이슈 모으기
        let issues = try await jiraService.fetchIssues(year: year, assignee: assignee, email: email, token: token, req: req)
        
        // 2. 데이터 가공 (Context 생성)
        let context = ReportGenerator.generateContext(issues: issues, year: year)
        
        // 3. Leaf 템플릿 렌더링
        return try await req.view.render("report", context)
    }
}
