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
│   │   ├── Controllers/    # 요청 처리 (MoaController)
│   │   ├── Models/         # 데이터 모델 (JiraIssue, ProcessedIssue 등)
│   │   ├── Services/       # 비즈니스 로직
│   │   │   ├── JiraService.swift       # Jira API 통신 및 데이터 가공
│   │   │   └── ReportGenerator.swift   # 리포트 데이터 구조화 및 트리 빌딩
│   │   └── ...
├── Resources/
│   └── Views/
│       └── report.leaf     # HTML 리포트 템플릿
└── ...
```

## 📝 라이선스
This project is for internal use.
