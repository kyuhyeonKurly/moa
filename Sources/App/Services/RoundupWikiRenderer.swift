import Foundation

/// 반기 성과 취합 Confluence Storage HTML 렌더러 (웹 핸들러 + CLI 커맨드 공용).
///
/// 섹션 구성:
///   요약 → 기획과제 → 기술과제 → KTLO(자동) → 크래시 대응(자동)
///        → 🛠 수동 대응(에픽 이관 필요: KTLO/크래시) → 검토 필요 → 🚫 제외(사유)
/// 대량 리스트라 inline 카드 대신 컴팩트 링크.
enum RoundupWikiRenderer {

    static func html(context: RoundupContext, decisions: [String: String], userName: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        func browse(_ key: String) -> String { "https://kurly0521.atlassian.net/browse/\(key)" }

        // 라벨된(locked) 건 확정 → decisions 무시. 무라벨만 사람 결정(decisions) 반영.
        // decision: planning | technical | ktlo | crash | excluded
        func finalCategory(_ g: RoundupEpicGroup) -> String {
            g.locked ? g.category : (decisions[g.epicKey] ?? g.category)
        }
        let allGroups = context.planning + context.technical
        let planning = allGroups.filter { finalCategory($0) == "planning" }
        let technical = allGroups.filter { finalCategory($0) == "technical" }
        // KTLO/크래시로 "사람이 지정"했지만 아직 그 에픽 하위로 이관 안 된 것 → 수동 대응(이관 필요)
        let ktloMigrate = allGroups.filter { finalCategory($0) == "ktlo" && !$0.locked }
        let crashMigrate = allGroups.filter { finalCategory($0) == "crash" && !$0.locked }
        let excludedGroups = allGroups.filter { finalCategory($0) == "excluded" }

        // 에픽 그룹 렌더 (헤더 + 하위 티켓). marker가 있으면 헤더 뒤에 붙임(⚠️ 이관 필요 등).
        func groupBlock(_ g: RoundupEpicGroup, marker: String = "") -> String {
            let link = g.epicLink ?? browse(g.epicKey)
            let sub = g.ticketCount > 0 ? " (하위 \(g.ticketCount))" : ""
            var s = "<p>📌 <a href=\"\(link)\">\(g.epicKey)</a> <strong>\(esc(g.epicSummary))</strong>\(sub)\(marker)</p>"
            if !g.tickets.isEmpty {
                s += "<ul>"
                for t in g.tickets { s += "<li><a href=\"\(t.link)\">\(t.key)</a> \(esc(t.summary))</li>" }
                s += "</ul>"
            }
            return s
        }
        func epicSection(_ title: String, _ groups: [RoundupEpicGroup]) -> String {
            var s = "<h2>\(title) (\(groups.count)건)</h2>"
            if groups.isEmpty { return s + "<p>-</p>" }
            for g in groups { s += groupBlock(g) }
            return s
        }
        func flatSection(_ title: String, _ tickets: [RoundupTicket]) -> String {
            var s = "<h2>\(title)</h2>"
            if tickets.isEmpty { return s + "<p>-</p>" }
            s += "<ul>"
            for t in tickets { s += "<li><a href=\"\(t.link)\">\(t.key)</a> \(esc(t.summary))</li>" }
            return s + "</ul>"
        }

        var html = "<p><strong>\(context.halfLabel)</strong> 완료 티켓 취합 · \(esc(userName))"
        if let p = context.platform { html += " · \(esc(p))" }
        html += " · 총 \(context.totalCount)건</p>"

        // 맨 위 요약 (기획/기술=과제 수, KTLO/크래시=건수)
        let ktloTotal = context.ktlo.count + ktloMigrate.reduce(0) { $0 + $1.ticketCount }
        let crashTotal = context.crash.count + crashMigrate.reduce(0) { $0 + $1.ticketCount }
        let excludedTotal = context.excluded.count + excludedGroups.reduce(0) { $0 + $1.ticketCount }
        html += "<h2>📌 요약</h2><ul>"
        html += "<li>🎯 <strong>기획과제</strong> \(planning.count)건</li>"
        html += "<li>🛠 <strong>기술과제</strong> \(technical.count)건</li>"
        html += "<li>🔧 <strong>KTLO</strong> \(ktloTotal)건</li>"
        html += "<li>💥 <strong>크래시 대응</strong> \(crashTotal)건</li>"
        if !context.unversioned.isEmpty {
            html += "<li>❓ <strong>검토 필요</strong> \(context.unversioned.count)건</li>"
        }
        if excludedTotal > 0 {
            html += "<li>🚫 <strong>제외</strong> \(excludedTotal)건</li>"
        }
        html += "</ul>"

        html += "<p><em>※ 귀속 기준: fixVersion 실제 배포일(GitHub Releases). 버전 없는 인프라/백엔드 작업은 완료일 기준. 분류는 최상위 과제의 기획과제/기술과제/KTLO 라벨 기준(자동), 무라벨은 사람이 확정.</em></p>"

        html += epicSection("🎯 기획과제", planning)
        html += epicSection("🛠 기술과제", technical)

        // KTLO / 크래시 — 자동(해당 에픽 하위로 이미 정상 이관된 것)만
        html += flatSection("🔧 KTLO", context.ktlo)
        html += flatSection("💥 크래시 대응", context.crash)

        // 🛠 수동 대응 (에픽 이관 필요) — KTLO/크래시 성격이나 아직 에픽 하위로 이관 안 됨
        if !ktloMigrate.isEmpty || !crashMigrate.isEmpty {
            html += "<h2>🛠 수동 대응 (에픽 이관 필요)</h2>"
            html += "<p><em>KTLO/크래시 성격이지만 해당 분기 KTLO 에픽 · 크래시 에픽(KMA-8165) 하위로 아직 이관되지 않은 과제. Jira에서 상위 에픽 하위로 이관하세요.</em></p>"
            let marker = " — <span style=\"color:#c00;\">⚠️ 에픽 이관 필요</span>"
            if !ktloMigrate.isEmpty {
                html += "<h3>🔧 KTLO 이관 필요 (\(ktloMigrate.count)건)</h3>"
                for g in ktloMigrate { html += groupBlock(g, marker: marker) }
            }
            if !crashMigrate.isEmpty {
                html += "<h3>💥 크래시 이관 필요 (\(crashMigrate.count)건)</h3>"
                for g in crashMigrate { html += groupBlock(g, marker: marker) }
            }
        }

        if !context.unversioned.isEmpty {
            html += flatSection("❓ 검토 필요 (미배포/버전없음)", context.unversioned)
        }

        // 🚫 제외 — 왜 빠졌는지 확인용 (사용자 제외 선택 + 상위 드랍 등 자동 제외)
        if !excludedGroups.isEmpty || !context.excluded.isEmpty {
            html += "<h2>🚫 제외 (사유 확인용)</h2>"
            html += "<p><em>성과 집계에서 제외된 티켓. 사유를 확인하고 오분류면 리뷰 화면에서 조정하세요.</em></p>"
            for g in excludedGroups {
                html += groupBlock(g, marker: " — <em>사용자 제외 선택</em>")
            }
            if !context.excluded.isEmpty {
                html += "<ul>"
                for e in context.excluded {
                    html += "<li><a href=\"\(e.link)\">\(e.key)</a> \(esc(e.summary)) — <em>\(esc(e.reason))</em></li>"
                }
                html += "</ul>"
            }
        }
        return html
    }
}
