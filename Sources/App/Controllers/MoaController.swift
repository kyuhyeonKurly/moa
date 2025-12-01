import Vapor

struct MoaController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("", use: index)
        let moa = routes.grouped("moa")
        moa.get("collect", use: collectAndPublish)
        moa.post("collect", use: collectAndPublish)
    }

    func index(req: Request) async throws -> View {
        let savedEmail = req.cookies["moa_email"]?.string
        let hasTokenCookie = req.cookies["moa_token"] != nil
        
        return try await req.view.render("index", [
            "savedEmail": savedEmail,
            "hasTokenCookie": hasTokenCookie
        ])
    }

    func collectAndPublish(req: Request) async throws -> Response {
        let year = req.query[Int.self, at: "year"] ?? req.content[Int.self, at: "year"] ?? 2023
        let assignee = req.query[String.self, at: "assignee"] ?? req.content[String.self, at: "assignee"]
        
        // 우선순위: 1. 폼 입력/쿼리  2. 쿠키  3. 환경변수(백업)
        let email = req.query[String.self, at: "email"] ?? req.content[String.self, at: "email"] ?? req.cookies["moa_email"]?.string
        let token = req.query[String.self, at: "token"] ?? req.content[String.self, at: "token"] ?? req.cookies["moa_token"]?.string
        
        let jiraService = JiraService(client: req.client)
        
        // 1. 이슈 모으기
        let issues = try await jiraService.fetchIssues(year: year, assignee: assignee, email: email, token: token, req: req)
        
        // 2. 데이터 가공 (Context 생성)
        let context = ReportGenerator.generateContext(issues: issues, year: year)
        
        // 3. Leaf 템플릿 렌더링 및 쿠키 설정
        let view = try await req.view.render("report", context)
        let response = try await view.encodeResponse(for: req)
        
        // 로그인 성공 시 쿠키에 저장 (30일 유지)
        if let email = email, let token = token {
            let cookieOptions = HTTPCookies.Value.SameSite.lax
            response.cookies["moa_email"] = .init(string: email, maxAge: 60*60*24*30, sameSite: cookieOptions)
            response.cookies["moa_token"] = .init(string: token, maxAge: 60*60*24*30, sameSite: cookieOptions)
        }
        
        return response
    }
}
