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

/// root 에픽의 정체로 버킷을 판정하는 순수 로직.
///
/// 발굴 결과(2026-07 실데이터): 기획/기술을 구분하는 라벨은 **존재하지 않는다**.
/// 일관 라벨은 KTLO 하나뿐이고, 크래시는 연간 운영 에픽(KMA-8165)로 관리된다.
/// 따라서 KTLO·크래시만 자동 분류하고, 나머지는 "미분류"로 두어 사람이 기획/기술을
/// 확정한다. 다만 사람 손을 줄이기 위해 제목 휴리스틱으로 기획/기술을 **프리필**한다
/// (결정론 규칙 — LLM 추론 아님, 사람이 최종 확정).
enum RoundupClassifier {

    /// 크래시 연간 운영 에픽. 미래 [2027] 크래시 대응 등은 제목 패턴으로도 잡는다.
    static let crashEpicKeys: Set<String> = ["KMA-8165"]

    enum AutoBucket {
        case ktlo
        case crash
        case unclassified  // 기획/기술 (라벨 없음 → 사람 확정 대상)
    }

    /// root 에픽 라벨/키/제목으로 자동 버킷 판정.
    static func autoBucket(rootLabels: [String], rootKey: String?, rootSummary: String?) -> AutoBucket {
        if rootLabels.contains(where: { $0.caseInsensitiveCompare("KTLO") == .orderedSame }) {
            return .ktlo
        }
        if let k = rootKey, crashEpicKeys.contains(k) {
            return .crash
        }
        if let s = rootSummary, s.contains("크래시 대응") {
            return .crash
        }
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
