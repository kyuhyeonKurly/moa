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
        let overrides = RoundupClassifier.parseEpicOverrides(request.epicOverrides)
        let (winStart, winEnd) = Self.collectionWindow(year: request.year, half: request.half)
        let assigneeClause = (request.assignee?.isEmpty == false)
            ? "assignee = \"\(request.assignee!)\"" : "assignee = currentUser()"
        // status "CLOSE"(취소/드랍)는 제외 — 완료(DONE)만 집계. (둘 다 statusCategory=done(green))
        // 하위 작업(sub-task)은 제외 — 성과 단위는 스토리/작업/버그/에픽. 하위 작업은
        // 부모 스토리의 분해라 개별 집계 시 중복(예: KMA-7711 하위 7712/7726/7727/7743).
        let jql = """
        \(assigneeClause) AND project = KMA AND statusCategory = Done AND status != "CLOSE" \
        AND issuetype in standardIssueTypes() \
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
        var excluded: [RoundupExcluded] = []
        var includedCount = 0
        // 기획/기술 과제: rootKey → 누적. root 자신은 헤더라 tickets에서 제외(자기중복 방지).
        struct GroupAcc {
            var root: JiraIssue?
            var tickets: [RoundupTicket] = []
            var leafSummaries: [String] = []
            var autoCat: RoundupClassifier.AutoBucket = .unclassified
            var designated = false   // 지정 에픽(override) = 공통 기술/기획과제
        }
        var groups: [String: GroupAcc] = [:]

        for leaf in leaves {
            // 최상위 에픽이 CLOSE(드랍)면 하위 DONE 티켓도 제외 (과제 자체가 드랍된 것)
            // → 그냥 버리지 않고 사유와 함께 excluded로 남겨 "왜 빠졌나" 검토 가능하게.
            if let topKey = droppedTopEpic(of: leaf.key, known: known) {
                let topSummary = known[topKey]?.fields.summary ?? topKey
                excluded.append(RoundupExcluded(
                    key: leaf.key,
                    summary: leaf.fields.summary,
                    link: "\(apiClient.apiBaseURL)/browse/\(leaf.key)",
                    reason: "상위 에픽 \(topKey)(\(topSummary)) 드랍(CLOSE)"
                ))
                continue
            }

            let attribution = attribute(leaf: leaf, known: known, platform: platform,
                                        halfStart: halfStart, halfEndExclusive: halfEndExclusive)
            switch attribution {
            case .otherPlatform, .otherHalf:
                continue // 이 반기·플랫폼 작업 아님 → 정상 제외
            case .unversioned:
                unversioned.append(makeTicket(leaf, versionName: nil, shipDate: nil))
                continue
            case let .included(versionName, shipDate):
                includedCount += 1
                let ticket = makeTicket(leaf, versionName: versionName, shipDate: shipDate)

                // 0) 지정 에픽 우선 — 하위를 그 에픽 컨테이너로 묶어 지정 카테고리 처리
                //    (버전 분리·라벨·휴리스틱 무시. 공통 팀 에픽용)
                if let (dKey, dCat) = designatedRoot(of: leaf.key, known: known, overrides: overrides) {
                    switch dCat {
                    case "ktlo":
                        ktlo.append(ticket)
                    case "planning", "technical":
                        let ac: RoundupClassifier.AutoBucket = (dCat == "planning") ? .planning : .technical
                        var g = groups[dKey] ?? GroupAcc(root: known[dKey], autoCat: ac)
                        g.autoCat = ac
                        g.designated = true
                        if leaf.key != dKey { g.tickets.append(ticket); g.leafSummaries.append(leaf.fields.summary) }
                        groups[dKey] = g
                    default:
                        break
                    }
                    continue
                }

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
                case .planning, .technical, .unclassified:
                    var g = groups[rKey] ?? GroupAcc(root: root, autoCat: bucket)
                    if leaf.key != rKey { // root 자신은 헤더이므로 하위 목록에서 제외
                        g.tickets.append(ticket)
                        g.leafSummaries.append(leaf.fields.summary)
                    }
                    groups[rKey] = g
                }
            }
        }

        // 그룹 → RoundupEpicGroup
        func build(_ key: String, _ g: GroupAcc) -> RoundupEpicGroup {
            let rootSummary = g.root?.fields.summary ?? g.tickets.first?.summary ?? key
            let locked = (g.autoCat == .planning || g.autoCat == .technical)
            let category: String
            let lockedLabel: String?
            switch g.autoCat {
            case .planning:  category = "planning";  lockedLabel = g.designated ? "공통 기획과제" : RoundupClassifier.planningLabel
            case .technical: category = "technical"; lockedLabel = g.designated ? "공통 기술과제" : RoundupClassifier.technicalLabel
            default:
                category = RoundupClassifier.guessPlanningOrTechnical(
                    epicSummary: rootSummary, leafSummaries: g.leafSummaries).rawValue
                lockedLabel = nil
            }
            return RoundupEpicGroup(
                epicKey: key,
                epicSummary: rootSummary,
                epicLink: "\(apiClient.apiBaseURL)/browse/\(key)",
                category: category,
                locked: locked,
                lockedLabel: locked ? lockedLabel : nil,
                tickets: g.tickets.sorted { $0.key < $1.key },
                ticketCount: g.tickets.count
            )
        }
        let allGroups = groups.map { build($0.key, $0.value) }
        func sortGroups(_ arr: [RoundupEpicGroup]) -> [RoundupEpicGroup] {
            arr.sorted { ($0.ticketCount, $1.epicKey) > ($1.ticketCount, $0.epicKey) }
        }
        let planning = sortGroups(allGroups.filter { $0.category == "planning" })
        let technical = sortGroups(allGroups.filter { $0.category == "technical" })

        return RoundupContext(
            year: request.year,
            half: request.half,
            halfLabel: Self.halfLabel(year: request.year, half: request.half),
            platform: platform.isEmpty ? nil : platform,
            spaceKey: request.spaceKey,
            epicOverrides: request.epicOverrides,
            totalCount: includedCount,
            planning: planning,
            technical: technical,
            ktlo: ktlo.sorted { $0.shipDateText < $1.shipDateText },
            crash: crash.sorted { $0.shipDateText < $1.shipDateText },
            unversioned: unversioned,
            excluded: excluded.sorted { $0.key < $1.key },
            planningCount: planning.count,
            technicalCount: technical.count,
            ktloCount: ktlo.count,
            crashCount: crash.count,
            unversionedCount: unversioned.count,
            excludedCount: excluded.count
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

    /// 노드 자신의 fixVersion 식별자(semver 집합, 플랫폼 무관). 없으면 nil.
    private func ownVersionKey(_ issue: JiraIssue) -> String? {
        guard let vs = issue.fields.fixVersions, !vs.isEmpty else { return nil }
        let semvers = Set(vs.compactMap { ReleaseCalendar.parse(versionName: $0.name)?.version })
        return semvers.isEmpty ? nil : semvers.sorted().joined(separator: ",")
    }

    /// leaf가 실제 실린 배포 버전(가장 가까운 own 버전). 없으면 nil.
    private func shipVersionKey(of key: String, known: [String: JiraIssue]) -> String? {
        var cur = key
        var visited = Set<String>()
        while let issue = known[cur], !visited.contains(cur) {
            if let k = ownVersionKey(issue) { return k }
            visited.insert(cur)
            guard let p = issue.fields.parent?.key else { break }
            cur = p
        }
        return nil
    }

    /// 버전 인지 root: 부모를 타고 올라가되, **부모가 자기 버전을 갖고 그게 leaf 배포버전과 다르면**
    /// 거기서 멈춘다 (분리 배포 = 독립 최상위). 수정버전 = 배포이므로 같은 버전끼리만 묶인다.
    /// (이 프로젝트는 에픽이 버전을 보유하고 자식이 상속 → 공통 케이스는 에픽으로 롤업)
    private func rootKey(of key: String, known: [String: JiraIssue]) -> String {
        let shipVer = shipVersionKey(of: key, known: known)
        var cur = key
        var visited = Set<String>()
        while let p = known[cur]?.fields.parent?.key, !visited.contains(cur), let parent = known[p] {
            // 타 프로젝트(예: KQA=SQE 보드) 부모로는 넘어가지 않는다 — 우리 과제 아님
            if !p.hasPrefix("KMA-") { break }
            if let sv = shipVer, let pOwn = ownVersionKey(parent), pOwn != sv {
                break // 부모는 다른 버전으로 배포됨 → cur가 이 배포의 최상위
            }
            visited.insert(cur)
            cur = p
        }
        return cur
    }

    /// leaf의 **최상위 KMA 에픽 status가 CLOSE(드랍)** 이면 그 에픽 key 반환, 아니면 nil.
    /// (버전 무관 절대 최상위까지 walk) 상위 과제가 드랍이면 하위 DONE 티켓도 성과 아님 → 제외.
    private func droppedTopEpic(of key: String, known: [String: JiraIssue]) -> String? {
        var cur = key
        var top = key
        var visited = Set<String>()
        while known[cur] != nil, !visited.contains(cur) {
            top = cur
            visited.insert(cur)
            guard let p = known[cur]?.fields.parent?.key, p.hasPrefix("KMA-"), known[p] != nil else { break }
            cur = p
        }
        let dropped = known[top]?.fields.status.name.caseInsensitiveCompare("CLOSE") == .orderedSame
        return dropped ? top : nil
    }

    /// 지정 에픽(overrides) 중 leaf의 조상 체인에서 **가장 상위** 지정 에픽 + 카테고리 반환.
    /// 버전 무시(컨테이너로 묶음). 없으면 nil.
    private func designatedRoot(of key: String, known: [String: JiraIssue], overrides: [String: String]) -> (String, String)? {
        if overrides.isEmpty { return nil }
        var result: (String, String)? = nil
        var cur = key
        var visited = Set<String>()
        while known[cur] != nil, !visited.contains(cur) {
            if let cat = overrides[cur] { result = (cur, cat) } // 위로 갈수록 갱신 → 최상위 지정 에픽이 최종
            visited.insert(cur)
            guard let p = known[cur]?.fields.parent?.key, p.hasPrefix("KMA-") else { break }
            cur = p
        }
        return result
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
