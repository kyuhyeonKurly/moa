# Plan: Quality Review Feature Implementation

Based on `specs/002-quality-review/spec.md`, this plan outlines the steps to implement the Quality Review feature.

## Phase 1: Data Modeling & API Client
- [ ] **Task 1.1**: Update `JiraIssue` model in `Sources/App/Models/JiraModels.swift` to support KQA specific fields (if any special fields are needed, otherwise ensure existing model covers it).
- [ ] **Task 1.2**: Create `QualityStats` and `QualityFeatureStat` structs in `Sources/App/Models/JiraModels.swift` (or a new file `QualityModels.swift`) to hold the aggregated data (Worst 3, Bug counts).

## Phase 2: Service Layer Implementation
- [ ] **Task 2.1**: Implement `fetchQualityIssues(year:client:)` in `Sources/App/Services/JiraService.swift`.
    - JQL: `project = KQA AND assignee = currentUser() AND created >= "{year}-01-01" AND created <= "{year}-12-31"`
- [ ] **Task 2.2**: Implement parent linking logic for KQA tickets.
    - KQA tickets often link to a Story or Epic via "Parent Link" or "Epic Link".
    - Need to reuse or adapt the existing recursive parent lookup to find the "Feature" (Epic) level parent for these bugs.

## Phase 3: Business Logic & Report Generation
- [ ] **Task 3.1**: Update `ReportGenerator.swift` to accept KQA issues.
- [ ] **Task 3.2**: Implement logic to group KQA issues by their Parent Feature (Epic).
- [ ] **Task 3.3**: Calculate "Worst 3 Features" (most bugs).
- [ ] **Task 3.4**: Calculate "Quality Hero" (Features with > X Story Points but 0 bugs - *Note: This might require cross-referencing with the main work tickets fetched in the existing logic*).
- [ ] **Task 3.5**: Generate `QualityStats` view model.

## Phase 4: UI Implementation (Leaf)
- [ ] **Task 4.1**: Update `Resources/Views/report.leaf` to add a new tab navigation item "Quality Review".
- [ ] **Task 4.2**: Create a new partial view `Resources/Views/quality_review.leaf` (or inline) to render the content.
- [ ] **Task 4.3**: Implement "Worst 3 Features" cards.
- [ ] **Task 4.4**: Implement the detailed accordion list of bugs per feature.

## Phase 5: Integration & Testing
- [ ] **Task 5.1**: Update `MoaController.swift` to call the new service methods and pass data to the view.
- [ ] **Task 5.2**: Verify JQL results and parent mapping accuracy.
