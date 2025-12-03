# Moa 프로젝트 지침 (Moa Project Instructions)

## 프로젝트 개요

Moa는 Jira 이슈를 수집하여 에픽(Epic) 및 버전(Version)별로 정리된 연말 회고 리포트를 생성하는 Swift Vapor 애플리케이션입니다.

## 아키텍처

- **프레임워크**: Vapor 4.0 (Swift 6.2.1+)
- **패턴**: 강력한 서비스 계층(Service Layer)을 갖춘 MVC 패턴.
- **주요 컴포넌트**:
  - **Controllers**: `MoaController`는 웹 라우트(`/`, `/moa/*`)를 처리합니다.
  - **Services**: 
    - `JiraService`: 이슈 수집, JQL 실행, 재귀적 버전 조회(Recursive Version Lookup) 핵심 로직 담당.
    - `ConfluenceService`: Confluence 페이지 생성 처리.
    - `ReportGenerator`: 수집된 데이터를 포맷팅.
  - **Commands**: 웹 UI 없이 로직을 테스트하기 위한 커스텀 CLI 명령어(`JiraVersionsCommand`) (`Sources/App/Commands`).
  - **Views**: `Resources/Views`에 위치한 Leaf 템플릿(`.leaf`).

## 주요 패턴 및 컨벤션

### Jira 연동

- **API Client**: `JiraAPIClient`를 사용하여 원시 HTTP 요청을 처리합니다. 헤더와 기본 URL을 관리합니다.
- **재귀적 버전 조회 (Recursive Version Lookup)**: 
  - 하위 작업(Sub-task)은 종종 `fixVersion`이 누락되어 있습니다. `JiraService`의 로직은 상위 작업(Parent Issue) 또는 에픽(Epic)을 재귀적으로 확인하여 올바른 버전을 찾아내야 합니다.
  - **중요**: 이슈 수집 로직을 수정할 때 이 로직을 반드시 유지해야 합니다.
- **JQL 구성**: JQL 쿼리는 `JiraService`에서 동적으로 생성됩니다. `project not in (KQA)` 및 날짜 필터가 유지되도록 주의하세요.

### 데이터 흐름

1. **입력**: 사용자가 `index.leaf`를 통해 자격 증명(이메일, 토큰)과 파라미터(연도, 담당자)를 제공합니다.
2. **처리**: `MoaController`가 `JiraService`에 위임합니다.
3. **출력**: `ReportGenerator`가 구조화된 리포트를 생성하고, 이를 Leaf로 렌더링하거나 Confluence로 전송합니다.

### 설정

- **환경 변수**: `.env` 파일에 저장됩니다 (예: `JIRA_EMAIL`, `JIRA_TOKEN`).
- **쿠키**: 사용자 편의를 위해 자격 증명(`moa_email`, `moa_token`)을 유지하는 데 사용됩니다.

## 개발 워크플로우

### 빌드 및 실행

- **서버 실행**: `swift run` (기본 포트: 8080)
- **명령어 실행**: `swift run App jira-versions` (예시)
- **의존성 관리**: `Package.swift`를 통해 관리됩니다.

### 일반적인 작업

- **새로운 리포트 섹션 추가**:
  1. 새로운 필드가 필요하면 `JiraModels.swift` 업데이트.
  2. 데이터를 가져오도록 `JiraService` 수정.
  3. 출력에 포함되도록 `ReportGenerator` 업데이트.
  4. 이를 표시하도록 `report.leaf` 업데이트.

- **Jira 인증 디버깅**:
  - `JiraService.fetchIssues` -> "0. 내 정보 가져오기" 섹션 확인.
  - `JIRA_TOKEN`이 비밀번호가 아닌 유효한 Atlassian API 토큰인지 확인.

## 기술 스택 상세

- **언어**: Swift 6.2.1
- **웹 프레임워크**: Vapor 4.0
- **템플릿 엔진**: Leaf
- **동시성**: 전체적으로 Swift Concurrency (`async`/`await`) 사용.
