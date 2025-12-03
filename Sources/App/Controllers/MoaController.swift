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
        let platform = req.query[String.self, at: "platform"] ?? req.content[String.self, at: "platform"] ?? ""

        return try await req.view.render("loading", [
            "year": "\(year)",
            "assignee": assignee,
            "email": email,
            "token": token,
            "spaceKey": spaceKey,
            "platform": platform
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
            let platform: String? // "iOS" or "Android"
        }
        
        let params = try req.content.decode(ReportRequest.self)
        req.logger.info("[Debug] ReportRequest received. Platform: \(params.platform ?? "nil")")
        
        // 공백 제거 (복사/붙여넣기 실수 방지)
        let cleanEmail = params.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = params.token.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let jiraClient = JiraAPIClient(client: req.client, email: cleanEmail, token: cleanToken)
        let jiraService = JiraService(apiClient: jiraClient)
        
        // 1. 이슈 모으기
        // assignee가 빈 문자열이면 nil로 처리
        let assignee = (params.assignee?.isEmpty ?? true) ? nil : params.assignee
        let issues = try await jiraService.fetchIssues(year: params.year, assignee: assignee, platform: params.platform)
        
        // 2. 데이터 가공 (Context 생성)
        let context = ReportGenerator.generateContext(issues: issues, year: params.year, spaceKey: params.spaceKey, platform: params.platform)
        
        // 3. Leaf 템플릿 렌더링
        let view = try await req.view.render("report", context).get()
        
        // 4. Response 생성 및 쿠키 설정
        let response = try await view.encodeResponse(for: req).get()
        
        // 로그인 성공 시 쿠키에 저장 (30일 유지)
        response.cookies["moa_email"] = HTTPCookies.Value(string: cleanEmail, maxAge: 60*60*24*30, sameSite: .lax)
        response.cookies["moa_token"] = HTTPCookies.Value(string: cleanToken, maxAge: 60*60*24*30, sameSite: .lax)
        
        if let spaceKey = params.spaceKey, !spaceKey.isEmpty {
            response.cookies["moa_space_key"] = HTTPCookies.Value(string: spaceKey, maxAge: 60*60*24*30, sameSite: .lax)
        }
        
        return response
    }
    
    func createDraft(req: Request) async throws -> Response {
        // 1. 파라미터 받기
        let year = try req.content.get(Int.self, at: "year")
        let spaceKey = try req.content.get(String.self, at: "spaceKey")
        let platform = req.content[String.self, at: "platform"]
        
        let email = req.cookies["moa_email"]?.string
        let token = req.cookies["moa_token"]?.string
        
        guard let email = email, let token = token else {
            throw Abort(.unauthorized, reason: "로그인이 필요합니다.")
        }
        
        // 2. 데이터 다시 조회
        let jiraClient = JiraAPIClient(client: req.client, email: email, token: token)
        
        // 사용자 정보 조회 (이름 포함)
        let user = try await jiraClient.getMyself()
        
        let jiraService = JiraService(apiClient: jiraClient)
        let issues = try await jiraService.fetchIssues(year: year, platform: platform)
        
        // 3. 전체 데이터 컨텍스트 생성
        let context = ReportGenerator.generateContext(issues: issues, year: year, spaceKey: spaceKey, platform: platform)
        
        // 4. HTML 테이블 생성 (연간 평가 템플릿 스타일)
        let tableHtml = generateYearlyReportHtml(context: context, year: year, userName: user.displayName)
        let title = "Jira 티켓으로 돌아보는 \(year)년 (\(user.displayName))"
        
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
    
    private func generateYearlyReportHtml(context: ReportContext, year: Int, userName: String) -> String {
        var html = """
        <p>Jira 티켓으로 돌아보는 \(year)년 (\(userName))</p>
        """
        
        // 0. 회고 (Self Review) 섹션 추가
        html += """
        <h2>🚀 \(year)년 회고 (Self Review)</h2>
        <p><em>한 해를 돌아보며 아래 내용을 자유롭게 작성해보세요.</em></p>
        
        <table data-layout="default">
            <colgroup>
                <col style="width: 50%;" />
                <col style="width: 50%;" />
            </colgroup>
            <tbody>
                <tr>
                    <th style="background-color: #E3FCEF;"><strong>👍 잘한 점 (Highlights)</strong></th>
                    <th style="background-color: #FFEBE6;"><strong>🤔 아쉬운 점 (Lowlights)</strong></th>
                </tr>
                <tr>
                    <td style="vertical-align: top; height: 150px;">
                        <ul>
                            <li>성과 1</li>
                            <li>성과 2</li>
                        </ul>
                    </td>
                    <td style="vertical-align: top; height: 150px;">
                        <ul>
                            <li>아쉬운 점 1</li>
                            <li>개선할 점 2</li>
                        </ul>
                    </td>
                </tr>
                <tr>
                    <th style="background-color: #DEEBFF;"><strong>💡 배운 점 (Learnings)</strong></th>
                    <th style="background-color: #EAE6FF;"><strong>🎯 내년 목표 (Next Year Goals)</strong></th>
                </tr>
                <tr>
                    <td style="vertical-align: top; height: 150px;">
                        <ul>
                            <li>배운 기술/지식</li>
                            <li>깨달은 점</li>
                        </ul>
                    </td>
                    <td style="vertical-align: top; height: 150px;">
                        <ul>
                            <li>목표 1</li>
                            <li>목표 2</li>
                        </ul>
                    </td>
                </tr>
            </tbody>
        </table>
        <br/>
        """
        
        // 요약 정보 추가
        html += """
        <h3>📊 요약</h3>
        <ul>
            <li><strong>총 티켓 수:</strong> \(context.totalCount)개</li>
            <li><strong>작업 유형별:</strong> 
        """
        
        let typeSummary = context.typeCounts.map { "\($0.type) \($0.count)개" }.joined(separator: ", ")
        html += "\(typeSummary)</li></ul>"
        
        // 안내 문구 추가
        html += """
        <p style="color: #6B778C; font-size: 0.9em;">
            ※ 이 리포트는 <strong>릴리스된 티켓</strong> 중 <strong>최상위 유형(Epic 등)</strong>을 기준으로 정리되었습니다.<br/>
            (Sub-task나 하위 Story는 부모 티켓에 포함되어 계산됩니다.)
        </p>
        """
        
        html += """
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
                
                // 월별 티켓 수 계산
                let count = context.monthlyGrid.first(where: { $0.monthIndex == m })?.issues.count ?? 0
                let countText = count > 0 ? " (\(count))" : ""
                
                html += "<th style='background-color: \(color); text-align: left;'><strong>\(m)월\(countText)</strong></th>"
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
                        // [Modified] Wiki 생성 시 플랫폼 필터링 적용
                        // JiraService는 Sorting만 하므로, 여기서 필터링 수행
                        let targetVersions: [VersionInfo]
                        if let platform = context.platform, !platform.isEmpty {
                            targetVersions = issue.versions.filter { $0.name.localizedCaseInsensitiveContains(platform) }
                        } else {
                            targetVersions = issue.versions
                        }
                        
                        if let version = targetVersions.first {
                            issuesByVersion[version, default: []].append(issue)
                        } else {
                            // 플랫폼 필터링으로 인해 버전이 없어졌거나 원래 없던 경우
                            // 원래 버전이 있었는데 필터링된 경우라면 '버전 없음'으로 가거나 제외해야 함.
                            // 여기서는 '버전 없음'으로 처리하거나, 원래 로직대로 첫번째 버전을 사용하되 필터링된게 없으면 원본 사용?
                            // 사용자의 의도는 "Wiki에는 해당 플랫폼 버전만 나오길 원함"
                            
                            if !issue.versions.isEmpty && (context.platform != nil) {
                                // 원래 버전은 있는데 필터링되어 사라진 경우 -> 이 이슈는 해당 플랫폼 이슈가 아닐 수 있음.
                                // 하지만 JiraService에서 Sorting을 했으므로, 만약 해당 플랫폼 버전이 있었다면 맨 앞에 왔을 것.
                                // 맨 앞 버전이 매칭되지 않는다면, 그 이슈는 해당 플랫폼 버전이 없는 것.
                                // 그래도 이슈 자체는 표시해야 하나?
                                // "릴리즈 버전 iOS, 안드로이드 둘다 찍히네" -> Wiki에서는 하나만 찍히길 원함.
                                // 이슈 자체를 숨길지, 버전만 숨길지?
                                // 보통 에픽은 양쪽 플랫폼 다 나가는 경우가 많음.
                                // 필터링된 버전이 없으면 -> 그냥 표시 안함? 아니면 '기타'로 표시?
                                // 일단 필터링된 버전이 없으면 noVersionIssues로 보냄.
                                noVersionIssues.append(issue)
                            } else {
                                noVersionIssues.append(issue)
                            }
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
                        // [Modified] 플랫폼 필터링 시, 버전이 매칭되지 않는 이슈들은 표시하지 않거나 별도 표시
                        // 여기서는 일단 표시하되, 사용자가 원치 않으면 제거 가능.
                        // 사용자의 요구: "Wiki 작성하는거에서... (갯수) 하면 안되나?" -> 이건 다른 요구사항.
                        // "원래대로 복구해줘" -> Web Report는 복구.
                        // Wiki는 필터링 적용.
                        
                        // 만약 플랫폼이 지정되었는데 버전이 매칭 안된 이슈들이라면, Wiki에 넣지 않는게 맞을 수도 있음.
                        // 하지만 안전하게 표시.
                        
                        // html += "<p><strong>버전 없음 / 타 플랫폼</strong></p>"
                        // html += "<ul>"
                        // for issue in noVersionIssues {
                        //     html += #"<li><a href="\#(issue.link)" data-card-appearance="inline">\#(issue.link)</a></li>"#
                        // }
                        // html += "</ul>"
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
