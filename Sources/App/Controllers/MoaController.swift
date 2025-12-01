import Vapor

struct MoaController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("", use: index)
        let moa = routes.grouped("moa")
        moa.get("collect", use: collectAndPublish)
        moa.post("collect", use: collectAndPublish)
        moa.post("create-draft", use: createDraft)
    }

    func index(req: Request) async throws -> View {
        let savedEmail = req.cookies["moa_email"]?.string
        let savedSpaceKey = req.cookies["moa_space_key"]?.string
        let hasTokenCookie = req.cookies["moa_token"] != nil
        
        return try await req.view.render("index", [
            "savedEmail": savedEmail,
            "savedSpaceKey": savedSpaceKey,
            "hasTokenCookie": hasTokenCookie ? "true" : nil
        ])
    }

    func collectAndPublish(req: Request) async throws -> Response {
        let year = req.query[Int.self, at: "year"] ?? req.content[Int.self, at: "year"] ?? 2023
        let assignee = req.query[String.self, at: "assignee"] ?? req.content[String.self, at: "assignee"]
        
        // 우선순위: 1. 폼 입력/쿼리  2. 쿠키  3. 환경변수(백업)
        let email = req.query[String.self, at: "email"] ?? req.content[String.self, at: "email"] ?? req.cookies["moa_email"]?.string
        let token = req.query[String.self, at: "token"] ?? req.content[String.self, at: "token"] ?? req.cookies["moa_token"]?.string
        let spaceKey = req.query[String.self, at: "spaceKey"] ?? req.content[String.self, at: "spaceKey"] ?? req.cookies["moa_space_key"]?.string
        
        let jiraService = JiraService(client: req.client)
        
        // 1. 이슈 모으기
        let issues = try await jiraService.fetchIssues(year: year, assignee: assignee, email: email, token: token, req: req)
        
        // 2. 데이터 가공 (Context 생성)
        let context = ReportGenerator.generateContext(issues: issues, year: year, spaceKey: spaceKey)
        
        // 3. Leaf 템플릿 렌더링
        // Vapor 4의 async render는 View를 반환합니다.
        let view = try await req.view.render("report", context).get()
        
        // 4. Response 생성 및 쿠키 설정
        let response = try await view.encodeResponse(for: req).get()
        
        // 로그인 성공 시 쿠키에 저장 (30일 유지)
        if let email = email, let token = token {
            // Vapor 4.x: HTTPCookies.Value(string: ..., sameSite: .lax)
            response.cookies["moa_email"] = HTTPCookies.Value(string: email, maxAge: 60*60*24*30, sameSite: .lax)
            response.cookies["moa_token"] = HTTPCookies.Value(string: token, maxAge: 60*60*24*30, sameSite: .lax)
        }
        
        if let spaceKey = spaceKey, !spaceKey.isEmpty {
            response.cookies["moa_space_key"] = HTTPCookies.Value(string: spaceKey, maxAge: 60*60*24*30, sameSite: .lax)
        }
        
        return response
    }
    
    func createDraft(req: Request) async throws -> Response {
        // 1. 파라미터 받기
        let year = try req.content.get(Int.self, at: "year")
        let spaceKey = try req.content.get(String.self, at: "spaceKey")
        
        let email = req.cookies["moa_email"]?.string
        let token = req.cookies["moa_token"]?.string
        
        guard let email = email, let token = token else {
            throw Abort(.unauthorized, reason: "로그인이 필요합니다.")
        }
        
        // 2. 데이터 다시 조회
        let jiraService = JiraService(client: req.client)
        let issues = try await jiraService.fetchIssues(year: year, email: email, token: token, req: req)
        
        // 3. 전체 데이터 컨텍스트 생성
        let context = ReportGenerator.generateContext(issues: issues, year: year, spaceKey: spaceKey)
        
        // 4. HTML 테이블 생성 (연간 평가 템플릿 스타일)
        let tableHtml = generateYearlyReportHtml(context: context)
        let title = "\(year)년 연간 평가 (Draft)"
        
        // 5. Confluence API 호출
        let confluenceService = ConfluenceService(client: req.client)
        let pageId = try await confluenceService.createPage(
            spaceKey: spaceKey,
            title: title,
            htmlContent: tableHtml,
            email: email,
            token: token
        )
        
        let editUrl = "https://kurly0521.atlassian.net/wiki/spaces/\(spaceKey)/pages/edit-v2/\(pageId)"
        return req.redirect(to: editUrl)
    }
    
    private func generateYearlyReportHtml(context: ReportContext) -> String {
        var html = """
        <p>Moa에서 생성된 연간 평가 초안입니다.</p>
        <table data-layout="default" ac:local-id="12345678-abcd-1234-abcd-1234567890ab">
            <colgroup>
                <col style="width: 33.33%;" />
                <col style="width: 33.33%;" />
                <col style="width: 33.33%;" />
            </colgroup>
            <tbody>
        """
        
        // 1월~12월을 3개씩 4줄로 배치
        // Row 1: Headers (1, 2, 3월)
        // Row 2: Content (1, 2, 3월)
        // ...
        
        let months = [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
            [10, 11, 12]
        ]
        
        for rowMonths in months {
            // Header Row
            html += "<tr>"
            for m in rowMonths {
                let color: String
                switch m {
                case 1, 8, 9: color = "#E3FCEF" // Mint/Green
                case 2, 3, 7: color = "#DEEBFF" // Blue
                case 4, 11: color = "#FFF0B3" // Yellow
                case 5, 12: color = "#FFEBE6" // Red/Pink
                case 6, 10: color = "#EAE6FF" // Purple
                default: color = "#F4F5F7" // Grey
                }
                html += "<th style='background-color: \(color); text-align: left;'><strong>\(m)월</strong></th>"
            }
            html += "</tr>"
            
            // Content Row
            html += "<tr>"
            for m in rowMonths {
                html += "<td style='vertical-align: top;'>"
                if let monthData = context.monthlyGrid.first(where: { $0.monthIndex == m }), !monthData.issues.isEmpty {
                    // 버전별로 그룹화
                    let issuesByVersion = Dictionary(grouping: monthData.issues) { issue -> String in
                        if let version = issue.versions.first {
                            let dateStr = issue.releaseDate.map { ISO8601DateFormatter().string(from: $0).prefix(10) } ?? ""
                            return "\(version) (\(dateStr))"
                        }
                        return "버전 없음"
                    }
                    
                    // 버전 정렬 (릴리즈 날짜 순)
                    let sortedVersions = issuesByVersion.keys.sorted { v1, v2 in
                        if v1 == "버전 없음" { return false }
                        if v2 == "버전 없음" { return true }
                        return v1 < v2 // 문자열 비교지만 날짜가 포함되어 있어 얼추 맞음. 정확히 하려면 별도 로직 필요
                    }
                    
                    for version in sortedVersions {
                        html += "<p><strong>\(version)</strong></p>"
                        html += "<ul>"
                        if let issues = issuesByVersion[version] {
                            for issue in issues {
                                html += #"<li><a href="\#(issue.link)" data-card-appearance="inline">\#(issue.link)</a></li>"#
                            }
                        }
                        html += "</ul>"
                    }
                } else {
                    html += "<p style='color: #999;'>-</p>"
                }
                html += "</td>"
            }
            html += "</tr>"
        }
        
        html += """
            </tbody>
        </table>
        """
        return html
    }
}
