import Vapor

struct MoaController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("", use: index)
        let moa = routes.grouped("moa")
        
        // 화면 진입 (Loading 페이지)
        moa.get("collect", use: showLoadingPage)
        moa.post("collect", use: showLoadingPage)
        
        // 실제 데이터 처리 (API)
        moa.post("api", "report", use: generateReport)
        
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

    func showLoadingPage(req: Request) async throws -> View {
        // 파라미터 수집 (Query or Content or Cookie)
        let year = req.query[Int.self, at: "year"] ?? req.content[Int.self, at: "year"] ?? 2023
        let assignee = req.query[String.self, at: "assignee"] ?? req.content[String.self, at: "assignee"] ?? ""
        let email = req.query[String.self, at: "email"] ?? req.content[String.self, at: "email"] ?? req.cookies["moa_email"]?.string ?? ""
        let token = req.query[String.self, at: "token"] ?? req.content[String.self, at: "token"] ?? req.cookies["moa_token"]?.string ?? ""
        let spaceKey = req.query[String.self, at: "spaceKey"] ?? req.content[String.self, at: "spaceKey"] ?? req.cookies["moa_space_key"]?.string ?? ""

        return try await req.view.render("loading", [
            "year": "\(year)",
            "assignee": assignee,
            "email": email,
            "token": token,
            "spaceKey": spaceKey
        ])
    }

    func generateReport(req: Request) async throws -> Response {
        // API 요청은 JSON Body로 받는다고 가정
        struct ReportRequest: Content {
            let year: Int
            let assignee: String?
            let email: String
            let token: String
            let spaceKey: String?
        }
        
        let params = try req.content.decode(ReportRequest.self)
        
        let jiraClient = JiraAPIClient(client: req.client, email: params.email, token: params.token)
        let jiraService = JiraService(apiClient: jiraClient)
        
        // 1. 이슈 모으기
        // assignee가 빈 문자열이면 nil로 처리
        let assignee = (params.assignee?.isEmpty ?? true) ? nil : params.assignee
        let issues = try await jiraService.fetchIssues(year: params.year, assignee: assignee)
        
        // 2. 데이터 가공 (Context 생성)
        let context = ReportGenerator.generateContext(issues: issues, year: params.year, spaceKey: params.spaceKey)
        
        // 3. Leaf 템플릿 렌더링
        let view = try await req.view.render("report", context).get()
        
        // 4. Response 생성 및 쿠키 설정
        let response = try await view.encodeResponse(for: req).get()
        
        // 로그인 성공 시 쿠키에 저장 (30일 유지)
        response.cookies["moa_email"] = HTTPCookies.Value(string: params.email, maxAge: 60*60*24*30, sameSite: .lax)
        response.cookies["moa_token"] = HTTPCookies.Value(string: params.token, maxAge: 60*60*24*30, sameSite: .lax)
        
        if let spaceKey = params.spaceKey, !spaceKey.isEmpty {
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
        let jiraClient = JiraAPIClient(client: req.client, email: email, token: token)
        let jiraService = JiraService(apiClient: jiraClient)
        let issues = try await jiraService.fetchIssues(year: year)
        
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
                    var issuesByVersion: [VersionInfo: [ProcessedIssue]] = [:]
                    var noVersionIssues: [ProcessedIssue] = []
                    
                    for issue in monthData.issues {
                        if let version = issue.versions.first {
                            issuesByVersion[version, default: []].append(issue)
                        } else {
                            noVersionIssues.append(issue)
                        }
                    }
                    
                    // 버전 정렬 (릴리즈 날짜 순)
                    let sortedVersions = issuesByVersion.keys.sorted { v1, v2 in
                        if let d1 = v1.releaseDate, let d2 = v2.releaseDate {
                            return d1 < d2
                        }
                        return v1.name < v2.name
                    }
                    
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yy/MM/dd"
                    
                    for version in sortedVersions {
                        let dateStr = version.releaseDate.map { dateFormatter.string(from: $0) } ?? ""
                        let issues = issuesByVersion[version] ?? []
                        let projectKey = issues.first?.projectKey ?? "KMA"
                        let versionUrl = "https://kurly0521.atlassian.net/projects/\(projectKey)/versions/\(version.id)"
                        
                        html += "<p><a href='\(versionUrl)'><strong>\(version.name) (\(dateStr))</strong></a></p>"
                        html += "<ul>"
                        for issue in issues {
                            html += #"<li><a href="\#(issue.link)" data-card-appearance="inline">\#(issue.link)</a></li>"#
                        }
                        html += "</ul>"
                    }
                    
                    if !noVersionIssues.isEmpty {
                        html += "<p><strong>버전 없음</strong></p>"
                        html += "<ul>"
                        for issue in noVersionIssues {
                            html += #"<li><a href="\#(issue.link)" data-card-appearance="inline">\#(issue.link)</a></li>"#
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
