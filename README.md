# Project Moa

**Project Moa**는 Jira 이슈를 수집하여 에픽(Epic) 및 버전(Version)별로 정리된 연말 회고 리포트를 생성하는 서버 애플리케이션입니다. 
Swift Vapor 프레임워크를 기반으로 구축되었으며, Leaf 템플릿 엔진을 사용하여 시각화된 HTML 리포트를 제공합니다.

## 📋 주요 기능

- **Jira 이슈 자동 수집**: 지정된 연도(`year`) 이후 생성된 모든 Jira 이슈를 JQL을 통해 수집합니다.
- **스마트 버전 추적 (Recursive Version Lookup)**: 
  - `fixVersion`이 명시되지 않은 하위 작업(Sub-task)의 경우, 상위 작업(Story/Task) 또는 에픽(Epic)을 재귀적으로 탐색하여 버전을 추론합니다.
- **계층적 리포트 생성**:
  - **📚 에픽별 보기**: 프로젝트 및 에픽 단위로 작업을 그룹화하여 보여줍니다.
  - **🚀 버전별 보기**: 릴리즈 버전별로 작업을 그룹화하고, `Epic -> Story -> Sub-task`의 계층 구조(Tree)를 시각화합니다.
- **통계 시각화**: 월별 작업 처리량 등 연말 회고에 필요한 기초 통계를 제공합니다.
- **반응형 UI**: Leaf 템플릿을 활용하여 깔끔하고 가독성 높은 HTML 리포트를 생성합니다.

## 🛠 기술 스택

- **Language**: Swift 5.9+
- **Framework**: Vapor 4.0
- **Template Engine**: Leaf 4.0
- **External API**: Jira Cloud REST API v3 (Cursor-based Pagination 적용)

## ⚙️ 설치 및 설정

### 1. 사전 요구사항
- Swift 5.9 이상 설치
- Jira 계정 및 API Token 발급 ([Atlassian API Token 생성](https://id.atlassian.com/manage-profile/security/api-tokens))

### 2. 프로젝트 클론
```bash
git clone https://github.com/kyuhyeonKurly/moa.git
cd moa
```

### 3. 환경 변수 설정 (.env)
프로젝트 루트 경로에 `.env` 파일을 생성하고 아래 정보를 입력하세요.

```env
JIRA_EMAIL=your_email@example.com
JIRA_TOKEN=your_jira_api_token
# JIRA_DOMAIN=https://your-domain.atlassian.net (코드 내 하드코딩 된 경우 확인 필요)
```

## 🚀 실행 방법

### 개발 모드로 실행
```bash
swift run
```
서버가 시작되면 `http://127.0.0.1:8080`에서 접속 가능합니다.

### 리포트 생성
브라우저에서 아래 URL로 접속하여 리포트를 생성합니다.
```
http://127.0.0.1:8080/moa/collect\?year\=2024
```
- `year`: 회고할 연도 (기본값: 현재 연도)
- `assignee`: (선택) 특정 담당자의 이슈만 조회하고 싶은 경우 이메일 또는 ID 지정 (기본값: API 토큰 소유자)

## 📂 프로젝트 구조

```
Moa/
├── Sources/
│   ├── App/
│   │   ├── Commands/       # CLI 명령어 (jira-*, confluence-*)
│   │   ├── Controllers/    # 요청 처리 (MoaController)
│   │   ├── DTOs/           # 데이터 전송 객체
│   │   ├── Services/       # 비즈니스 로직
│   │   │   ├── JiraAPIClient.swift     # Jira API 클라이언트
│   │   │   ├── JiraService.swift       # Jira 데이터 가공
│   │   │   ├── ConfluenceService.swift # Confluence API 클라이언트
│   │   │   └── ReportGenerator.swift   # 리포트 데이터 구조화
│   │   └── ...
├── Resources/
│   └── Views/
│       └── report.leaf     # HTML 리포트 템플릿
└── ...
```

## 🖥️ CLI 명령어

모든 명령어는 `swift run App <command>` 형식으로 실행합니다.

### Jira 명령어

#### 버전 관련

| 명령어 | 설명 | 예시 |
|--------|------|------|
| `jira-versions` | 프로젝트 버전 목록 조회 | `swift run App jira-versions KMA -y 2024` |
| `jira-version-detail` | 특정 버전의 이슈 조회 | `swift run App jira-version-detail KMA -v 10234 -m` |

```bash
# 2024년 릴리스 버전만 조회
swift run App jira-versions KMA --year 2024

# 특정 버전의 내 이슈만 조회
swift run App jira-version-detail KMA --version 10234 --me
```

#### 티켓 조회

| 명령어 | 설명 | 예시 |
|--------|------|------|
| `jira-tickets` | 연도별 티켓 목록 (웹과 동일) | `swift run App jira-tickets -y 2024 -g` |
| `jira-detail` | 단일 이슈 상세 조회 | `swift run App jira-detail -i KMA-4564` |
| `jira-issue-type` | 여러 이슈 타입 일괄 조회 | `swift run App jira-issue-type KMA-4771,KMA-4768` |
| `jira-ticket-detail` | 여러 티켓 상세 조회 + 도메인 분류 | `swift run App jira-ticket-detail "KMA-4817,KMA-4764"` |

```bash
# 2024년 티켓을 버전별로 그룹화
swift run App jira-tickets --year 2024 --group

# 타입 태그와 함께 출력
swift run App jira-tickets -y 2024 -t

# 특정 이슈 상세 조회
swift run App jira-detail --issue KMA-4564
```

#### 트리/계층 구조

| 명령어 | 설명 | 예시 |
|--------|------|------|
| `jira-tree` | 이슈 하위 구조를 트리로 출력 | `swift run App jira-tree -i KMA-5788 -d 3` |

```bash
# Epic의 하위 구조를 3레벨까지 트리로 출력
swift run App jira-tree --issue KMA-5788 --depth 3

# 상세 정보 포함 + 마크다운 내보내기
swift run App jira-tree -i KMA-5788 -v --export ./output.md
```

#### 연간 회고/분석

| 명령어 | 설명 | 예시 |
|--------|------|------|
| `jira-export` | 연도별 티켓을 마크다운으로 내보내기 | `swift run App jira-export -y 2024` |
| `jira-retrospective` | AI 에이전트용 회고 컨텍스트 생성 | `swift run App jira-retrospective -s 2021 -e 2025` |
| `jira-domain-guideline` | 도메인별 세분화 가이드라인 | `swift run App jira-domain-guideline -s 2021 -e 2025` |
| `jira-domain-detail` | 특정 도메인 상세 추출 | `swift run App jira-domain-detail -d search` |

```bash
# 2024년 티켓을 마크다운으로 내보내기
swift run App jira-export --year 2024 --output ./exports/2024.md

# 2021-2025 전체 회고 데이터 생성
swift run App jira-retrospective --start 2021 --end 2025

# 검색 도메인만 상세 추출
swift run App jira-domain-detail --domain search --start 2021 --end 2025
```

### Confluence 명령어

| 명령어 | 설명 | 예시 |
|--------|------|------|
| `confluence-wiki` | 스페이스별 연도별 위키 목록 | `swift run App confluence-wiki -s appr --start-year 2024` |
| `confluence-children` | 페이지 하위 트리 조회 | `swift run App confluence-children 123456 -x` |

```bash
# 2024년 appr 스페이스 위키 페이지 조회
swift run App confluence-wiki --space appr --start-year 2024 --end-year 2024 --export

# 특정 페이지의 하위 구조 조회
swift run App confluence-children 123456,789012 --export
```

### 공통 옵션

| 옵션 | 설명 |
|------|------|
| `-y, --year` | 연도 필터 |
| `-s, --start` | 시작 연도 |
| `-e, --end` | 종료 연도 |
| `-o, --output` | 출력 파일 경로 |
| `-d, --domain` | 도메인 필터 (search, cart, home, category, mykurly, experiment, platform, design, product, filter, mmp, ai) |
| `-x, --export` | 마크다운 파일로 내보내기 |

