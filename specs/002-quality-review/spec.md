# Spec 002: Quality Review (품질 회고)

## 1. Intent (의도)
단순히 "얼마나 많이 일했는가(Output)"를 보여주는 것을 넘어, **"얼마나 완성도 있게 일했는가(Outcome)"**를 회고할 수 있는 도구로 진화시킨다.
QA 기간 동안 발생한 버그 티켓(KQA)을 분석하여, 개발자가 자신의 작업 품질을 객관적으로 파악하고 구조적 개선점을 찾도록 돕는다.

## 2. Context (맥락)
- **Current State**: 현재 리포트는 완료된 티켓(Done)만 보여주며, QA 프로젝트(KQA)는 제외되어 있음.
- **Problem**: 기능 개발 후 QA 과정에서 얼마나 많은 리소스가 투입되었는지, 어떤 기능이 취약했는지 알 수 없음.
- **Goal**: 리포트에 'Quality Review' 섹션을 추가하여 버그 데이터를 시각화함.

## 3. Functional Requirements (기능 요구사항)

### 3.1 Data Acquisition (데이터 수집)
- **Source**: Jira Cloud API
- **Filter Logic**:
  - Project: `KQA` (QA 프로젝트)
  - Assignee: `currentUser()` (내가 해결한 버그)
  - Date: 해당 연도 (`created` or `resolved`)
- **Mapping**:
  - KQA 티켓의 `Parent Link` 필드를 추적하여 원인 제공 기능(Feature/Epic)을 식별해야 함.
  - 부모가 없는 단순 버그는 'Uncategorized' 또는 'Misc'로 분류.

### 3.2 Data Processing (데이터 가공)
- **Grouping**: `[Feature Name]`을 기준으로 KQA 티켓을 그룹핑.
- **Metrics**:
  - **Bug Count per Feature**: 기능별 버그 발생 수.
  - **Bug Type Distribution**: 버그 유형(기능, 기획, 디자인 등) 비율 (라벨 기반).

### 3.3 User Interface (UI)
- **Tab**: `report.leaf`에 'Quality Review' 탭 추가.
- **Components**:
  - **Worst 3 Features**: 버그가 가장 많이 발생한 상위 3개 기능을 카드 형태로 강조 (경각심 부여).
  - **Quality Hero**: 일정 규모(Story Point 등) 이상인데 버그가 0건인 기능이 있다면 칭찬 뱃지 부여.
  - **Detailed List**: 기능별 버그 목록 (아코디언 UI).

## 4. Technical Constraints (기술적 제약사항)
- **Stack**: Swift 6.2, Vapor 4.0, Leaf.
- **Performance**: KQA 티켓 조회 및 부모 추적 시 N+1 문제가 발생하지 않도록, 가능한 한 번의 JQL이나 병렬 요청으로 처리해야 함.
- **Privacy**: 개인 회고용이므로, 다른 사람의 버그 데이터는 노출하지 않음.

## 5. Implementation Plan (구현 계획)
1. `JiraService`: `fetchQualityIssues()` 메서드 구현.
2. `JiraService`: `mapIssuesToParents()` 로직 구현 (재귀적 부모 찾기).
3. `ReportGenerator`: `QualityStats` 뷰 모델 생성.
4. `report.leaf`: UI 렌더링 구현.
