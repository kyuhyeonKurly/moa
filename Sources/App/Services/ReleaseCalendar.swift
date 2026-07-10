import Vapor

/// GitHub 릴리즈 기반 "버전 → 실제 배포일" 달력.
///
/// KMA-8276 / KMA-8165 거버넌스 규칙: 쿼터·반기 귀속은 작업/머지 시점이 아니라
/// **수정버전(fixVersion)의 실제 배포일** 기준이다. 그리고 그 배포일의 진실 소스는
/// 개발자가 릴리즈 시 갱신하는 GitHub Releases다 (Jira version.releaseDate는 계획일/
/// 일괄기입으로 어긋날 수 있어 fallback으로만 쓴다).
///
/// 데이터는 `Resources/release-calendar.json` (github-releases-sync 커맨드로 갱신).
struct ReleaseCalendar {
    struct Entry: Content {
        let platform: String     // "iOS" | "Android"
        let version: String      // semver, no leading v ("3.77.3")
        let tag: String
        let name: String?
        let releasedAt: String   // ISO8601
    }
    struct File: Content {
        let source: String
        let releases: [Entry]
    }

    /// key: "\(platform.lowercased())#\(semver)" -> 실제 배포일(instant)
    private let index: [String: Date]

    init(entries: [Entry]) {
        let iso = ISO8601DateFormatter()
        var map: [String: Date] = [:]
        for e in entries {
            guard let d = iso.date(from: e.releasedAt) else { continue }
            let key = Self.key(platform: e.platform, version: e.version)
            // 같은 버전이 중복되면 가장 이른 배포일을 채택
            if let existing = map[key] {
                if d < existing { map[key] = d }
            } else {
                map[key] = d
            }
        }
        self.index = map
    }

    /// `Resources/release-calendar.json` 로드
    static func load(on app: Application) throws -> ReleaseCalendar {
        let path = app.directory.resourcesDirectory + "release-calendar.json"
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let file = try JSONDecoder().decode(File.self, from: data)
        return ReleaseCalendar(entries: file.releases)
    }

    private static func key(platform: String, version: String) -> String {
        "\(platform.lowercased())#\(version)"
    }

    /// Jira fixVersion 이름 파싱 → (플랫폼, semver)
    /// 관용 처리: "v3.77.3 - iOS", "3.77.3 - Android", "[iOS] v3.10.0", "iOS 3.38.0",
    ///           "안드로이드 3.71.0" 등. 플랫폼/버전 어느 하나라도 못 뽑으면 nil.
    static func parse(versionName: String) -> (platform: String, version: String)? {
        let lower = versionName.lowercased()

        let platform: String
        if lower.contains("android") || versionName.contains("안드로이드") || lower.contains("aos") {
            platform = "Android"
        } else if lower.contains("ios") {
            platform = "iOS"
        } else {
            return nil // 플랫폼 식별 불가 (예: "버전 할당 대기")
        }

        // 첫 번째 semver 토큰 추출 (major.minor[.patch])
        guard let version = firstSemver(in: versionName) else { return nil }
        return (platform, version)
    }

    private static func firstSemver(in text: String) -> String? {
        // 정규식 없이 스캔: 숫자.숫자[.숫자] 패턴을 찾는다.
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i].isNumber {
                var j = i
                var dots = 0
                while j < chars.count, chars[j].isNumber || chars[j] == "." {
                    if chars[j] == "." { dots += 1 }
                    j += 1
                }
                let token = String(chars[i..<j])
                // 최소 major.minor 형태
                if dots >= 1, token.first != ".", token.last != "." {
                    return token
                }
                i = j
            } else {
                i += 1
            }
        }
        return nil
    }

    /// Jira fixVersion 이름으로 실제 배포일 조회 (GitHub 달력 우선)
    func shipDate(forVersionName name: String) -> Date? {
        guard let parsed = Self.parse(versionName: name) else { return nil }
        return shipDate(platform: parsed.platform, version: parsed.version)
    }

    func shipDate(platform: String, version: String) -> Date? {
        index[Self.key(platform: platform, version: version)]
    }

    var count: Int { index.count }
}
