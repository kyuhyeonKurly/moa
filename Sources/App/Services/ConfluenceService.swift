import Vapor

struct ConfluenceService {
    let client: Client
    let apiBaseURL = "https://kurly0521.atlassian.net/wiki"

    // MARK: - Create Page
    
    func createPage(spaceKey: String, title: String, htmlContent: String, email: String, token: String) async throws -> String {
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Content-Type": "application/json"
        ]
        
        let uri = URI(string: "\(apiBaseURL)/rest/api/content")
        
        let requestBody = ConfluencePageCreateRequest(
            title: title,
            type: "page",
            space: .init(key: spaceKey),
            status: "draft",
            body: .init(storage: .init(value: htmlContent, representation: "storage"))
        )
        
        let response = try await client.post(uri, headers: headers) { req in
            try req.content.encode(requestBody)
        }
        
        guard response.status == .ok || response.status == .created else {
            let body = response.body.map { String(buffer: $0) } ?? "No body"
            throw Abort(.internalServerError, reason: "Confluence API Error (\(response.status)): \(body)")
        }
        
        let result = try response.content.decode(ConfluencePageResponse.self)
        return result.id
    }
    
    // MARK: - Search Pages by Space and Year
    
    /// 현재 사용자 정보를 조회합니다
    func getCurrentUser(email: String, token: String) async throws -> String {
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        let uri = URI(string: "\(apiBaseURL)/rest/api/user/current")
        let response = try await client.get(uri, headers: headers)
        
        guard response.status == .ok else {
            let body = response.body.map { String(buffer: $0) } ?? "No body"
            throw Abort(.internalServerError, reason: "Failed to get current user (\(response.status)): \(body)")
        }
        
        let user = try response.content.decode(ConfluenceCurrentUser.self)
        print("  👤 현재 사용자: \(user.displayName) (\(user.accountId))")
        return user.accountId
    }
    
    /// CQL을 사용하여 특정 스페이스에서 특정 사용자가 작성한 페이지들을 조회
    /// 참고: Confluence Cloud CQL에서 creator 필터가 제대로 작동하지 않아,
    /// 결과를 받은 후 클라이언트 측에서 필터링합니다.
    func searchPages(
        spaceKey: String,
        year: Int,
        email: String,
        token: String,
        userAccountId: String,
        maxResults: Int = 1000,  // 최대 조회 건수 제한
        onProgress: ((Int, Int) -> Void)? = nil  // (fetched, total estimate)
    ) async throws -> [ConfluenceContent] {
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        var seenPageIds: Set<String> = []  // 중복 방지용
        var allResults: [ConfluenceContent] = []
        var start = 0
        let limit = 100
        var pageNum = 1
        var emptyResponseCount = 0  // 연속으로 본인 페이지가 없는 응답 횟수
        
        // CQL: type=page와 날짜 필터만 사용 (creator 필터링은 클라이언트 측에서 수행)
        let startDate = "\(year)-01-01"
        let endDate = "\(year + 1)-01-01"
        let cql = "space = \"\(spaceKey)\" AND type = page AND created >= \"\(startDate)\" AND created < \"\(endDate)\" ORDER BY created DESC"
        
        print("  📄 \(year)년 페이지 조회 시작...")
        print("    👤 필터링 대상: \(userAccountId)")
        
        repeat {
            guard let encodedCQL = cql.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                throw Abort(.badRequest, reason: "Failed to encode CQL query")
            }
            
            let urlString = "\(apiBaseURL)/rest/api/content/search?cql=\(encodedCQL)&start=\(start)&limit=\(limit)&expand=history,history.createdBy,history.lastUpdated,space"
            let uri = URI(string: urlString)
            
            print("    ↳ API 요청 중... (page \(pageNum), offset: \(start))")
            
            let response = try await client.get(uri, headers: headers)
            
            guard response.status == .ok else {
                let body = response.body.map { String(buffer: $0) } ?? "No body"
                throw Abort(.internalServerError, reason: "Confluence Search API Error (\(response.status)): \(body)")
            }
            
            let searchResponse = try response.content.decode(ConfluenceContentListResponse.self)
            
            // 클라이언트 측 필터링: history.createdBy.accountId로 본인 페이지만 선택
            // + 중복 제거: 이미 추가된 페이지 ID는 건너뜀
            let myPages = searchResponse.results.filter { content in
                guard content.history?.createdBy?.accountId == userAccountId else { return false }
                guard !seenPageIds.contains(content.id) else { return false }
                seenPageIds.insert(content.id)
                return true
            }
            
            allResults.append(contentsOf: myPages)
            
            print("    ✓ \(searchResponse.results.count)건 중 \(myPages.count)건 본인 작성 (누적: \(allResults.count)건)")
            onProgress?(allResults.count, allResults.count)
            
            // 본인 페이지가 연속 5회 이상 없으면 조기 종료 (해당 연도에 본인 페이지가 없을 가능성)
            if myPages.isEmpty {
                emptyResponseCount += 1
                if emptyResponseCount >= 5 {
                    print("    ℹ️ 연속 5회 본인 페이지 없음, 조기 종료")
                    break
                }
            } else {
                emptyResponseCount = 0
            }
            
            start += limit
            pageNum += 1
            
            // 더 이상 결과가 없거나 최대 건수 도달 시 종료
            if searchResponse.size < limit || allResults.count >= maxResults {
                if allResults.count >= maxResults {
                    print("    ⚠️ 최대 조회 건수(\(maxResults))에 도달하여 중단")
                }
                break
            }
            
            // 최대 API 호출 횟수 제한 (무한 루프 방지)
            if pageNum > 100 {
                print("    ⚠️ 최대 페이지 수(100) 도달, 종료")
                break
            }
        } while true
        
        print("  ✅ \(year)년 완료: 본인 작성 \(allResults.count)건")
        return allResults
    }
    
    /// 특정 페이지의 하위 페이지(children)를 재귀적으로 가져옵니다 (depth 정보 포함)
    func getChildPagesWithDepth(
        pageId: String,
        email: String,
        token: String,
        depth: Int = 1,
        maxDepth: Int = 10
    ) async throws -> [ConfluencePageNode] {
        guard depth <= maxDepth else {
            print("    ⚠️ 최대 깊이(\(maxDepth)) 도달")
            return []
        }
        
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        var allChildren: [ConfluencePageNode] = []
        var start = 0
        let limit = 100
        let indent = String(repeating: "  ", count: depth + 1)
        
        repeat {
            let urlString = "\(apiBaseURL)/rest/api/content/\(pageId)/child/page?start=\(start)&limit=\(limit)&expand=history,history.createdBy,space"
            let uri = URI(string: urlString)
            
            let response = try await client.get(uri, headers: headers)
            
            guard response.status == .ok else {
                let body = response.body.map { String(buffer: $0) } ?? "No body"
                throw Abort(.internalServerError, reason: "Confluence Child API Error (\(response.status)): \(body)")
            }
            
            let childResponse = try response.content.decode(ConfluenceContentListResponse.self)
            
            for child in childResponse.results {
                // 현재 자식 페이지를 depth와 함께 추가
                allChildren.append(ConfluencePageNode(page: child, depth: depth))
                print("\(indent)↳ [\(child.id)] \(child.title)")
                
                // 재귀적으로 손자 페이지 조회
                let grandChildren = try await getChildPagesWithDepth(
                    pageId: child.id,
                    email: email,
                    token: token,
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
                allChildren.append(contentsOf: grandChildren)
            }
            
            start += limit
            
            if childResponse.size < limit {
                break
            }
        } while true
        
        return allChildren
    }
    
    /// 특정 페이지의 하위 페이지(children)를 재귀적으로 가져옵니다
    func getChildPages(
        pageId: String,
        email: String,
        token: String,
        depth: Int = 0,
        maxDepth: Int = 10
    ) async throws -> [ConfluenceContent] {
        guard depth < maxDepth else {
            print("    ⚠️ 최대 깊이(\(maxDepth)) 도달")
            return []
        }
        
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        var allChildren: [ConfluenceContent] = []
        var start = 0
        let limit = 100
        let indent = String(repeating: "  ", count: depth + 2)
        
        repeat {
            let urlString = "\(apiBaseURL)/rest/api/content/\(pageId)/child/page?start=\(start)&limit=\(limit)&expand=history,history.createdBy,space"
            let uri = URI(string: urlString)
            
            let response = try await client.get(uri, headers: headers)
            
            guard response.status == .ok else {
                let body = response.body.map { String(buffer: $0) } ?? "No body"
                throw Abort(.internalServerError, reason: "Confluence Child API Error (\(response.status)): \(body)")
            }
            
            let childResponse = try response.content.decode(ConfluenceContentListResponse.self)
            
            for child in childResponse.results {
                allChildren.append(child)
                print("\(indent)↳ [\(child.id)] \(child.title)")
                
                // 재귀적으로 손자 페이지 조회
                let grandChildren = try await getChildPages(
                    pageId: child.id,
                    email: email,
                    token: token,
                    depth: depth + 1,
                    maxDepth: maxDepth
                )
                allChildren.append(contentsOf: grandChildren)
            }
            
            start += limit
            
            if childResponse.size < limit {
                break
            }
        } while true
        
        return allChildren
    }
    
    /// 특정 페이지 ID로 페이지 정보를 조회합니다
    func getPage(pageId: String, email: String, token: String) async throws -> ConfluenceContent {
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        
        let urlString = "\(apiBaseURL)/rest/api/content/\(pageId)?expand=history,history.createdBy,space"
        let uri = URI(string: urlString)
        
        let response = try await client.get(uri, headers: headers)
        
        guard response.status == .ok else {
            let body = response.body.map { String(buffer: $0) } ?? "No body"
            throw Abort(.internalServerError, reason: "Confluence API Error (\(response.status)): \(body)")
        }
        
        return try response.content.decode(ConfluenceContent.self)
    }
    
    /// 특정 페이지와 그 하위 페이지들을 모두 조회합니다
    func getPageWithChildren(pageId: String, email: String, token: String) async throws -> [ConfluenceContent] {
        print("\n📄 페이지 ID \(pageId) 및 하위 페이지 조회 중...")
        
        // 부모 페이지 조회
        let parentPage = try await getPage(pageId: pageId, email: email, token: token)
        print("  📌 [\(parentPage.id)] \(parentPage.title)")
        
        var allPages: [ConfluenceContent] = [parentPage]
        
        // 하위 페이지 재귀 조회
        let children = try await getChildPages(pageId: pageId, email: email, token: token)
        allPages.append(contentsOf: children)
        
        print("  ✅ 총 \(allPages.count)건 (부모 1 + 하위 \(children.count))")
        return allPages
    }
    
    /// 특정 페이지와 그 하위 페이지들을 트리 구조로 조회합니다 (depth 정보 포함)
    func getPageTreeWithChildren(pageId: String, email: String, token: String) async throws -> [ConfluencePageNode] {
        print("\n📄 페이지 ID \(pageId) 및 하위 페이지 조회 중...")
        
        // 부모 페이지 조회
        let parentPage = try await getPage(pageId: pageId, email: email, token: token)
        print("  📌 [\(parentPage.id)] \(parentPage.title)")
        
        var allNodes: [ConfluencePageNode] = [ConfluencePageNode(page: parentPage, depth: 0)]
        
        // 하위 페이지 재귀 조회 (depth=1부터 시작)
        let children = try await getChildPagesWithDepth(pageId: pageId, email: email, token: token, depth: 1)
        allNodes.append(contentsOf: children)
        
        print("  ✅ 총 \(allNodes.count)건 (부모 1 + 하위 \(children.count))")
        return allNodes
    }
    
    /// 여러 연도에 걸쳐 페이지 조회
    func searchPagesForYears(
        spaceKey: String,
        startYear: Int,
        endYear: Int,
        email: String,
        token: String
    ) async throws -> [Int: [ConfluenceContent]] {
        var resultsByYear: [Int: [ConfluenceContent]] = [:]
        let totalYears = endYear - startYear + 1
        var currentYearIndex = 0
        
        print("\n🔄 총 \(totalYears)개 연도 조회 예정 (\(startYear) ~ \(endYear))")
        print("─".padding(toLength: 50, withPad: "─", startingAt: 0))
        
        // 먼저 현재 사용자 정보 조회
        let userAccountId = try await getCurrentUser(email: email, token: token)
        
        for year in startYear...endYear {
            currentYearIndex += 1
            print("\n[\(currentYearIndex)/\(totalYears)] \(year)년 조회 중...")
            
            let pages = try await searchPages(spaceKey: spaceKey, year: year, email: email, token: token, userAccountId: userAccountId)
            if !pages.isEmpty {
                resultsByYear[year] = pages
            } else {
                print("  ⚪ \(year)년: 작성한 페이지 없음")
            }
        }
        
        print("\n─".padding(toLength: 50, withPad: "─", startingAt: 0))
        let totalPages = resultsByYear.values.reduce(0) { $0 + $1.count }
        print("🎉 전체 조회 완료: \(totalPages)건\n")
        
        return resultsByYear
    }
}

