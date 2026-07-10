import Foundation

/// 반기 성과 취합 Confluence Storage HTML 렌더러 (웹 핸들러 + CLI 커맨드 공용).
/// 4섹션(기획/기술/KTLO/크래시) + 검토. 대량 리스트라 inline 카드 대신 컴팩트 링크.
enum RoundupWikiRenderer {

    static func html(context: RoundupContext, decisions: [String: String], userName: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
        }
        // 라벨된(locked) 건 확정 → decisions 무시. 무라벨만 사람 결정(decisions) 반영, "excluded"는 제외.
        func finalCategory(_ g: RoundupEpicGroup) -> String {
            g.locked ? g.category : (decisions[g.epicKey] ?? g.category)
        }
        let allGroups = context.planning + context.technical
        let planning = allGroups.filter { finalCategory($0) == "planning" }
        let technical = allGroups.filter { finalCategory($0) == "technical" }

        func epicSection(_ title: String, _ groups: [RoundupEpicGroup]) -> String {
            var s = "<h2>\(title) (\(groups.count)건)</h2>"
            if groups.isEmpty { return s + "<p>-</p>" }
            for g in groups {
                let link = g.epicLink ?? "https://kurly0521.atlassian.net/browse/\(g.epicKey)"
                let sub = g.ticketCount > 0 ? " (하위 \(g.ticketCount))" : ""
                s += "<p>📌 <a href=\"\(link)\">\(g.epicKey)</a> <strong>\(esc(g.epicSummary))</strong>\(sub)</p>"
                if !g.tickets.isEmpty {
                    s += "<ul>"
                    for t in g.tickets {
                        s += "<li><a href=\"\(t.link)\">\(t.key)</a> \(esc(t.summary))</li>"
                    }
                    s += "</ul>"
                }
            }
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
        html += "<p><em>※ 귀속 기준: fixVersion 실제 배포일(GitHub Releases). 버전 없는 인프라/백엔드 작업은 완료일 기준. 분류는 최상위 과제의 기획과제/기술과제/KTLO 라벨 기준(자동), 무라벨은 사람이 확정.</em></p>"
        html += epicSection("🎯 기획과제", planning)
        html += epicSection("🛠 기술과제", technical)
        html += flatSection("🔧 KTLO", context.ktlo)
        html += flatSection("💥 크래시 대응", context.crash)
        if !context.unversioned.isEmpty {
            html += flatSection("❓ 검토 필요 (미배포/버전없음)", context.unversioned)
        }
        return html
    }
}
