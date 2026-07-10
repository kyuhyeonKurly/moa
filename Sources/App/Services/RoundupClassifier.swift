import Foundation

/// 상반기 성과 취합의 4버킷 + 검토 버킷.
enum RoundupCategory: String, Codable {
    case planning     // 기획과제
    case technical    // 기술과제
    case ktlo         // KTLO (운영 유지)
    case crash        // 크래시 대응
    case unversioned  // 미배포/버전없음 — 사람 검토
    case excluded     // 제외 (사람이 뺀 항목)
}

/// root(최상위 배포 단위)의 정체로 버킷을 판정하는 순수 로직.
///
/// 분류 신호는 **root의 Jira 라벨**이다 (KMA-8276/8165 거버넌스: 얼라인된 것만 가치창출):
///  - `KTLO`        → KTLO (분기별 운영 에픽)
///  - 크래시 에픽    → 크래시 (KMA-8165 계열)
///  - `기획과제`     → 기획 (자동·확정)
///  - `기술과제`     → 기술 (자동·확정)
///  - 그 외/무라벨   → 미분류 → 제목 휴리스틱 프리필 후 **사람 확정**(→ write-back)
///
/// `개발과제`는 폐기된 라벨이라 자동 매핑하지 않는다(무라벨과 동일 취급, 얼라인 안 되면 KTLO).
enum RoundupClassifier {

    /// 크래시 연간 운영 에픽. 미래 [2027] 크래시 대응 등은 제목 패턴으로도 잡는다.
    static let crashEpicKeys: Set<String> = ["KMA-8165"]

    static let planningLabel = "기획과제"
    static let technicalLabel = "기술과제"

    enum AutoBucket {
        case ktlo
        case crash
        case planning      // 기획과제 라벨 → 자동·확정(locked)
        case technical     // 기술과제 라벨 → 자동·확정(locked)
        case unclassified  // 무라벨 → 사람 확정 대상(프리필)
    }

    private static func hasLabel(_ labels: [String], _ target: String) -> Bool {
        labels.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
    }

    /// root 라벨/키/제목으로 자동 버킷 판정.
    static func autoBucket(rootLabels: [String], rootKey: String?, rootSummary: String?) -> AutoBucket {
        if hasLabel(rootLabels, "KTLO") { return .ktlo }
        if let k = rootKey, crashEpicKeys.contains(k) { return .crash }
        if let s = rootSummary, s.contains("크래시 대응") { return .crash }
        if hasLabel(rootLabels, planningLabel) { return .planning }
        if hasLabel(rootLabels, technicalLabel) { return .technical }
        return .unclassified
    }

    /// 기획 vs 기술 휴리스틱 프리필. 기술 마커가 하나라도 걸리면 기술, 아니면 기획(기본).
    static func guessPlanningOrTechnical(epicSummary: String, leafSummaries: [String] = []) -> RoundupCategory {
        let hay = ([epicSummary] + leafSummaries).joined(separator: " ").lowercased()
        for marker in technicalMarkers where hay.contains(marker) {
            return .technical
        }
        return .planning
    }

    /// 기술과제로 추정하는 결정론 마커 (소문자 비교).
    static let technicalMarkers: [String] = [
        "기술과제", "refactor", "리팩토링", "리팩터", "migration", "마이그레이션",
        "sdk", "ci/cd", "ci /cd", "인프라", "테스트가능", "테스트 인프라",
        "os 최소", "최소버전", "최소 지원", "업그레이드", "아키텍처",
        "빌드", "파이프라인", "워크플로우", "싱글톤", "deprecat",
        "성능 최적화", "자동화 테스트", "tuist", "모듈화", "ssot"
    ]
}
