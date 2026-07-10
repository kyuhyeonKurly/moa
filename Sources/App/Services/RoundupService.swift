import Vapor

/// 모드 2 "상반기 성과 취합" 수집·분류 오케스트레이터.
///
/// 흐름:
///  1) 내 완료(Done) leaf 티켓을 반기 인근 window로 수집 (paginated)
///  2) 부모 에픽을 최대 4홉까지 해석 (라벨 포함) → root 에픽 확정
///  3) fixVersion(없으면 상속) → GitHub 배포일 달력으로 반기 귀속 판정
///  4) root 에픽 정체로 버킷 분류 (KTLO/크래시 자동, 기획/기술은 프리필 후 사람 확정)
///
/// 레거시 JiraService는 건드리지 않는다 (독립 수집 경로).
struct RoundupService {
    let apiClient: JiraAPIClient
    let calendar: ReleaseCalendar
    let logger: Logger

    private static let fields = [
        "summary", "status", "labels", "resolutiondate",
        "fixVersions", "parent", "issuetype", "assignee", "created"
    ]

    func collect(request: RoundupRequest) async throws -> RoundupContext {
        // 0) 인증 검증
        _ = try await apiClient.getMyself()

        let platform = request.platform ?? ""
        let (winStart, winEnd) = Self.collectionWindow(year: request.year, half: request.half)
        let assigneeClause = (request.assignee?.isEmpty == false)
            ? "assignee = \"\(request.assignee!)\"" : "assignee = currentUser()"
        let jql = """
        \(assigneeClause) AND project = KMA AND statusCategory = Done \
        AND resolutiondate >= "\(winStart)" AND resolutiondate <= "\(winEnd)" \
        ORDER BY resolutiondate ASC
        """
        logger.info("[Roundup] window \(winStart)~\(winEnd), platform=\(platform.isEmpty ? "전체" : platform)")

        // 1) 내 완료 leaf 수집
        let leaves = try await searchAll(jql: jql)
        logger.info("[Roundup] fetched \(leaves.count) leaf issues")

        // 2) 조상 에픽 해석 (라벨 포함), 최대 4홉
        var known: [String: JiraIssue] = [:]
        for i in leaves { known[i.key] = i }
        for _ in 0..<4 {
            let needed = Set(known.values.compactMap { $0.fields.parent?.key })
                .subtracting(known.keys)
            if needed.isEmpty { break }
            let fetched = try await searchAll(jql: "key in (\(needed.joined(separator: ",")))")
            if fetched.isEmpty { break }
            for f in fetched { known[f.key] = f }
        }

        // 3~4) leaf별 귀속·분류
        let (halfStart, halfEndExclusive) = Self.halfRange(year: request.year, half: request.half)

        var ktlo: [RoundupTicket] = []
        var crash: [RoundupTicket] = []
        var unversioned: [RoundupTicket] = []
        // 기획/기술 미분류: rootKey → (root 정보 + leaf 티켓들)
        var groups: [String: (root: JiraIssue?, key: String, tickets: [RoundupTicket], leafSummaries: [String])] = [:]

        for leaf in leaves {
            // 반기 귀속 판정
            let attribution = attribute(leaf: leaf, known: known, platform: platform,
                                        halfStart: halfStart, halfEndExclusive: halfEndExclusive)
            switch attribution {
            case .otherPlatform, .otherHalf:
                continue // 이 반기·플랫폼 작업 아님 → 정상 제외
            case .unversioned:
                unversioned.append(makeTicket(leaf, versionName: nil, shipDate: nil))
                continue
            case let .included(versionName, shipDate):
                let ticket = makeTicket(leaf, versionName: versionName, shipDate: shipDate)
                let rKey = rootKey(of: leaf.key, known: known)
                let root = known[rKey]
                let bucket = RoundupClassifier.autoBucket(
                    rootLabels: root?.fields.labels ?? [],
                    rootKey: rKey,
                    rootSummary: root?.fields.summary
                )
                switch bucket {
                case .ktlo:  ktlo.append(ticket)
                case .crash: crash.append(ticket)
                case .unclassified:
                    var g = groups[rKey] ?? (root: root, key: rKey, tickets: [], leafSummaries: [])
                    g.tickets.append(ticket)
                    g.leafSummaries.append(leaf.fields.summary)
                    groups[rKey] = g
                }
            }
        }

        // 그룹 → RoundupEpicGroup (프리필 포함), 티켓 수 desc 정렬
        let unclassified: [RoundupEpicGroup] = groups.values.map { g in
            let rootSummary = g.root?.fields.summary ?? g.tickets.first?.summary ?? g.key
            let guess = RoundupClassifier.guessPlanningOrTechnical(
                epicSummary: rootSummary, leafSummaries: g.leafSummaries
            )
            return RoundupEpicGroup(
                epicKey: g.key,
                epicSummary: rootSummary,
                epicLink: "\(apiClient.apiBaseURL)/browse/\(g.key)",
                guess: guess.rawValue,
                tickets: g.tickets.sorted { $0.key < $1.key },
                ticketCount: g.tickets.count
            )
        }
        .sorted { ($0.ticketCount, $1.epicKey) > ($1.ticketCount, $0.epicKey) }

        let total = ktlo.count + crash.count + unversioned.count + unclassified.reduce(0) { $0 + $1.ticketCount }

        return RoundupContext(
            year: request.year,
            half: request.half,
            halfLabel: Self.halfLabel(year: request.year, half: request.half),
            platform: platform.isEmpty ? nil : platform,
            spaceKey: request.spaceKey,
            totalCount: total,
            ktlo: ktlo.sorted { $0.shipDateText < $1.shipDateText },
            crash: crash.sorted { $0.shipDateText < $1.shipDateText },
            unclassified: unclassified,
            unversioned: unversioned,
            ktloCount: ktlo.count,
            crashCount: crash.count,
            unclassifiedCount: unclassified.reduce(0) { $0 + $1.ticketCount },
            unversionedCount: unversioned.count
        )
    }

    // MARK: - Attribution

    private enum Attribution {
        case included(versionName: String, shipDate: Date)
        case unversioned
        case otherPlatform
        case otherHalf
    }

    private func attribute(leaf: JiraIssue, known: [String: JiraIssue], platform: String,
                           halfStart: Date, halfEndExclusive: Date) -> Attribution {
        let allVers = effectiveVersions(of: leaf.key, known: known)
        if !allVers.isEmpty {
            let platformVers = platform.isEmpty
                ? allVers
                : allVers.filter { $0.name.localizedCaseInsensitiveContains(platform) }
            if platformVers.isEmpty { return .otherPlatform }

            // 배포일 해석 (GitHub 달력). 가장 이른 배포 버전으로 귀속.
            let dated: [(name: String, date: Date)] = platformVers.compactMap { v in
                calendar.shipDate(forVersionName: v.name).map { (v.name, $0) }
            }
            if let earliest = dated.min(by: { $0.date < $1.date }) {
                if earliest.date >= halfStart && earliest.date < halfEndExclusive {
                    return .included(versionName: earliest.name, shipDate: earliest.date)
                }
                return .otherHalf
            }
            // 버전은 있으나 배포일 미해석(버전 할당 대기 등) → 검토
            return .unversioned
        }
        // 버전 자체 없음(앱 릴리즈 미탑재 인프라/백엔드 작업) → 완료일(resolutiondate) 기준 폴백
        guard let rd = leaf.fields.resolutiondate, let d = Self.parseDate(rd) else { return .unversioned }
        if d >= halfStart && d < halfEndExclusive {
            return .included(versionName: "완료일 기준", shipDate: d)
        }
        return .otherHalf
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f.date(from: String(s.prefix(10)))
    }

    /// leaf 자신의 fixVersion, 없으면 조상에서 상속.
    private func effectiveVersions(of key: String, known: [String: JiraIssue]) -> [JiraFields.JiraVersion] {
        var cur = key
        var visited = Set<String>()
        while let issue = known[cur] {
            if let vs = issue.fields.fixVersions, !vs.isEmpty { return vs }
            guard let p = issue.fields.parent?.key, !visited.contains(cur) else { break }
            visited.insert(cur)
            cur = p
        }
        return []
    }

    /// 부모 체인을 타고 올라가 최상위(알고 있는) 티켓 key 반환.
    private func rootKey(of key: String, known: [String: JiraIssue]) -> String {
        var cur = key
        var visited = Set<String>()
        while let p = known[cur]?.fields.parent?.key, !visited.contains(cur), known[p] != nil {
            visited.insert(cur)
            cur = p
        }
        return cur
    }

    private func makeTicket(_ issue: JiraIssue, versionName: String?, shipDate: Date?) -> RoundupTicket {
        RoundupTicket(
            key: issue.key,
            summary: issue.fields.summary,
            link: "\(apiClient.apiBaseURL)/browse/\(issue.key)",
            versionLabel: versionName ?? "-",
            shipDateText: shipDate.map { Self.md.string(from: $0) } ?? "-"
        )
    }

    // MARK: - Fetch (paginated)

    private func searchAll(jql: String) async throws -> [JiraIssue] {
        var result: [JiraIssue] = []
        var token: String? = nil
        repeat {
            let page = try await apiClient.searchIssues(
                jql: jql, fields: Self.fields, maxResults: 100, nextPageToken: token
            )
            result.append(contentsOf: page.issues)
            token = (page.nextPageToken?.isEmpty == false) ? page.nextPageToken : nil
        } while token != nil
        return result
    }

    // MARK: - Date helpers

    private static let md: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        return f
    }()

    private static var kst: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    /// 반기 실제 경계 (KST). [start, endExclusive)
    static func halfRange(year: Int, half: Int) -> (Date, Date) {
        let cal = kst
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: 0, minute: 0, second: 0))!
        }
        if half == 1 {
            return (date(year, 1, 1), date(year, 7, 1))
        } else {
            return (date(year, 7, 1), date(year + 1, 1, 1))
        }
    }

    /// resolutiondate 수집 window (반기 인근 여유폭). "yyyy-MM-dd".
    static func collectionWindow(year: Int, half: Int) -> (String, String) {
        if half == 1 {
            return ("\(year - 1)-12-01", "\(year)-07-15")
        } else {
            return ("\(year)-06-01", "\(year + 1)-01-15")
        }
    }

    static func halfLabel(year: Int, half: Int) -> String {
        half == 1 ? "\(year)년 상반기 (1~6월)" : "\(year)년 하반기 (7~12월)"
    }
}
