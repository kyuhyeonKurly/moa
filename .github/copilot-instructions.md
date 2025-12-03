# Moa 프로젝트 지침 (Moa Project Instructions)

## 프로젝트 개요

Moa는 Jira 이슈를 수집하여 에픽(Epic) 및 버전(Version)별로 정리된 연말 회고 리포트를 생성하는 Swift Vapor 애플리케이션입니다.

## 아키텍처

- **프레임워크**: Vapor 4.0 (Swift 6.2.1+)
- **패턴**: 강력한 서비스 계층(Service Layer)을 갖춘 MVC 패턴.
- **주요 컴포넌트**:
  - **Controllers**: `MoaController`는 웹 라우트(`/`, `/moa/*`)를 처리합니다.
  - **Services**: 
    - `JiraService`: 이슈 수집, JQL 실행, 재귀적 버전 조회 핵심 로직 담당.
    - `ConfluenceService`: Confluence 페이지 생성 처리.
    - `ReportGenerator`: 수집된 데이터를 포맷팅.
  - **Commands**: 웹 UI 없이 로직을 테스트하기 위한 커스텀 CLI 명령어(`JiraVersionsCommand`) (`Sources/App/Commands`).
  - **Views**: `Resources/Views`에 위치한 Leaf 템플릿(`.leaf`).

## 핵심 비즈니스 로직 (Jira 데이터 처리)

AI 에이전트는 코드를 수정할 때 반드시 아래의 **데이터 처리 순서**를 준수해야 합니다.

1. **이슈 우선 수집 (Fetch Issues First)**:
   - JQL을 사용하여 해당 연도의 **모든 내 이슈(Sub-task 포함)**를 먼저 수집합니다.
   
2. **재귀적 버전 매핑 (Recursive Version Lookup)**:
   - 수집된 **모든 이슈**에 대해 올바른 버전을 찾아 매핑합니다.
   - **Sub-task 처리**: Sub-task는 `fixVersion`이 비어있는 경우가 많으므로, 반드시 **부모(Parent) 이슈**를 조회하여 부모의 버전을 상속받아야 합니다.
   
3. **뷰 모델 구성 (View Generation)**:
   - **총 티켓 수**: 1번 단계에서 수집된 **모든 이슈(Sub-task 포함)**의 개수입니다 (가장 정확한 업무량).
   - **월별 보기 (Monthly View)**: 2번 단계에서 매핑된 버전의 **배포일(Release Date)**을 기준으로 그룹핑합니다. 이때 리포트의 가독성을 위해 주요 배포 단위로 묶어서 보여줍니다.

## 주요 패턴 및 컨벤션

### Jira 연동

- **API Client**: `JiraAPIClient`를 사용하여 원시 HTTP 요청을 처리합니다.
- **JQL 구성**: `project not in (KQA)` 및 날짜 필터가 유지되도록 주의하세요.

### 데이터 흐름

1. **입력**: 사용자가 `index.leaf`를 통해 자격 증명과 파라미터를 제공.
2. **처리**: `MoaController` -> `JiraService` (위의 비즈니스 로직 수행).
3. **출력**: `ReportGenerator`가 구조화된 리포트 생성 -> Leaf 렌더링.

### 설정

- **환경 변수**: `.env` 파일 사용 (`JIRA_EMAIL`, `JIRA_TOKEN`).
- **쿠키**: 자격 증명(`moa_email`, `moa_token`) 유지.

## 개발 워크플로우

### 빌드 및 실행

- **서버 실행**: `swift run` (기본 포트: 8080)
- **명령어 실행**: `swift run App jira-versions`
- **의존성 관리**: `Package.swift`

### 일반적인 작업

- **새로운 리포트 섹션 추가**:
  1. `JiraModels.swift` 필드 추가.
  2. `JiraService` 데이터 매핑 로직 수정.
  3. `ReportGenerator` 및 `report.leaf` 업데이트.

## 기술 스택 상세

- **언어**: Swift 6.2.1
- **웹 프레임워크**: Vapor 4.0
- **템// filepath: .github/copilot-instructions.md
# Moa 프로젝트 지침 (Moa Project Instructions)

## 프로젝트 개요

Moa는 Jira 이슈를 수집하여 에픽(Epic) 및 버전(Version)별로 정리된 연말 회고 리포트를 생성하는 Swift Vapor 애플리케이션입니다.

## 아키텍처

- **프레임워크**: Vapor 4.0 (Swift 6.2.1+)
- **패턴**: 강력한 서비스 계층(Service Layer)을 갖춘 MVC 패턴.
- **주요 컴포넌트**:
  - **Controllers**: `MoaController`는 웹 라우트(`/`, `/moa/*`)를 처리합니다.
  - **Services**: 
    - `JiraService`: 이슈 수집, JQL 실행, 재귀적 버전 조회 핵심 로직 담당.
    - `ConfluenceService`: Confluence 페이지 생성 처리.
    - `ReportGenerator`: 수집된 데이터를 포맷팅.
  - **Commands**: 웹 UI 없이 로직을 테스트하기 위한 커스텀 CLI 명령어(`JiraVersionsCommand`) (`Sources/App/Commands`).
  - **Views**: `Resources/Views`에 위치한 Leaf 템플릿(`.leaf`).

## 핵심 비즈니스 로직 (Jira 데이터 처리)

AI 에이전트는 코드를 수정할 때 반드시 아래의 **데이터 처리 순서**를 준수해야 합니다.

1. **이슈 우선 수집 (Fetch Issues First)**:
   - JQL을 사용하여 해당 연도의 **모든 내 이슈(Sub-task 포함)**를 먼저 수집합니다.
   
2. **재귀적 버전 매핑 (Recursive Version Lookup)**:
   - 수집된 **모든 이슈**에 대해 올바른 버전을 찾아 매핑합니다.
   - **Sub-task 처리**: Sub-task는 `fixVersion`이 비어있는 경우가 많으므로, 반드시 **부모(Parent) 이슈**를 조회하여 부모의 버전을 상속받아야 합니다.
   
3. **뷰 모델 구성 (View Generation)**:
   - **총 티켓 수**: 1번 단계에서 수집된 **모든 이슈(Sub-task 포함)**의 개수입니다 (가장 정확한 업무량).
   - **월별 보기 (Monthly View)**: 2번 단계에서 매핑된 버전의 **배포일(Release Date)**을 기준으로 그룹핑합니다. 이때 리포트의 가독성을 위해 주요 배포 단위로 묶어서 보여줍니다.

## 주요 패턴 및 컨벤션

### Jira 연동

- **API Client**: `JiraAPIClient`를 사용하여 원시 HTTP 요청을 처리합니다.
- **JQL 구성**: `project not in (KQA)` 및 날짜 필터가 유지되도록 주의하세요.

### 데이터 흐름

1. **입력**: 사용자가 `index.leaf`를 통해 자격 증명과 파라미터를 제공.
2. **처리**: `MoaController` -> `JiraService` (위의 비즈니스 로직 수행).
3. **출력**: `ReportGenerator`가 구조화된 리포트 생성 -> Leaf 렌더링.

### 설정

- **환경 변수**: `.env` 파일 사용 (`JIRA_EMAIL`, `JIRA_TOKEN`).
- **쿠키**: 자격 증명(`moa_email`, `moa_token`) 유지.

## 개발 워크플로우

### 빌드 및 실행

- **서버 실행**: `swift run` (기본 포트: 8080)
- **명령어 실행**: `swift run App jira-versions`
- **의존성 관리**: `Package.swift`

### 일반적인 작업

- **새로운 리포트 섹션 추가**:
  1. `JiraModels.swift` 필드 추가.
  2. `JiraService` 데이터 매핑 로직 수정.
  3. `ReportGenerator` 및 `report.leaf` 업데이트.

## 기술 스택 상세

- **언어**: Swift 6.2.1
- **웹 프레임워크**: Vapor 4.0
- **템플릿 엔진**: Leaf
- **동시성**: Swift Concurrency (async/await) 필수 사용.
- **외부 API**: Jira Cloud REST API v3