import Vapor

/// 모드 2 "상반기 성과 취합" 리포트 요청.
struct RoundupRequest: Content {
    let year: Int
    let half: Int            // 1 = 상반기(1~6월), 2 = 하반기(7~12월)
    let platform: String?    // "" | "iOS" | "Android"
    let assignee: String?
    let email: String
    let token: String
    let spaceKey: String?

    func validate() throws {
        guard (2000...2100).contains(year) else {
            throw Abort(.badRequest, reason: "Year must be between 2000 and 2100")
        }
        guard half == 1 || half == 2 else {
            throw Abort(.badRequest, reason: "half must be 1 or 2")
        }
        guard !email.isEmpty else { throw Abort(.badRequest, reason: "Email is required") }
        guard !token.isEmpty else { throw Abort(.badRequest, reason: "Token is required") }
    }
}

/// 위키 생성 응답 — 생성된 Confluence draft 편집 URL.
struct RoundupDraftResponse: Content {
    let editUrl: String
}

/// 위키 생성 요청 — 사람이 확정한 분류 결정을 함께 받는다.
struct RoundupWikiRequest: Content {
    let year: Int
    let half: Int
    let platform: String?
    let spaceKey: String
    /// rootKey → "planning" | "technical" | "excluded"
    let decisions: [String: String]?
}

/// 라벨 write-back 요청 — 무라벨 root에 기획과제/기술과제 라벨을 Jira에 부착.
struct RoundupLabelRequest: Content {
    let year: Int
    let half: Int
    let platform: String?
    /// rootKey → "planning" | "technical" | "excluded"
    let decisions: [String: String]?
}

struct RoundupLabelResponse: Content {
    let applied: Int
    let skipped: Int
    let details: [String]   // "KMA-7674 → 기획과제" 등
}

// MARK: - View Context

/// leaf 티켓 1건 표시용.
struct RoundupTicket: Content {
    let key: String
    let summary: String
    let link: String
    let versionLabel: String    // "v3.77.0 - iOS" 등 대표 버전
    let shipDateText: String     // "06/23"
}

/// 기획/기술 과제 그룹 (root = 최상위 배포 단위).
struct RoundupEpicGroup: Content {
    let epicKey: String          // 최상위(root) 티켓 key
    let epicSummary: String
    let epicLink: String?
    let category: String         // "planning" | "technical" (라벨 or 프리필)
    let locked: Bool             // 라벨이 이미 있어 확정됨(수정 불가 · write-back 제외)
    let lockedLabel: String?     // "기획과제" | "기술과제" (locked일 때 표시)
    let tickets: [RoundupTicket] // 하위 작업 (root 자신 제외)
    let ticketCount: Int         // 하위 작업 수
}

struct RoundupContext: Content {
    let year: Int
    let half: Int
    let halfLabel: String        // "2026년 상반기 (1~6월)"
    let platform: String?
    let spaceKey: String?

    let totalCount: Int          // 반기 귀속된 내 leaf 총계
    let planning: [RoundupEpicGroup]   // 기획 과제
    let technical: [RoundupEpicGroup]  // 기술 과제
    let ktlo: [RoundupTicket]
    let crash: [RoundupTicket]
    let unversioned: [RoundupTicket]   // 미배포/버전없음 — 검토

    // 섹션별 카운트 (뷰 헤더용) — 기획/기술은 "과제(그룹) 수"
    let planningCount: Int
    let technicalCount: Int
    let ktloCount: Int
    let crashCount: Int
    let unversionedCount: Int
}
