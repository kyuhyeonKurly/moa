# Plan: Refactor to Vapor Guidelines

Based on `specs/001-refactor-guidelines/spec.md`.

## Phase 0: Directory Structure (Priority)
- [ ] **Task 0.1**: Create `Sources/App/DTOs` directory.
- [ ] **Task 0.2**: Move `Sources/App/Models/JiraModels.swift` to `Sources/App/DTOs/JiraDTOs.swift`.
- [ ] **Task 0.3**: Move `Sources/App/Models/JiraVersionModel.swift` to `Sources/App/DTOs/JiraVersionDTOs.swift`.
- [ ] **Task 0.4**: Move `Sources/App/Models/Confluence/` to `Sources/App/DTOs/Confluence/`.
- [ ] **Task 0.5**: Create missing standard directories even if empty (to enforce structure):
    - `Sources/App/Migrations`
    - `Sources/App/Middleware`
    - `Sources/App/Jobs`
    - `Sources/App/Services` (Already exists)
    - `Sources/App/Commands` (Already exists)
- [ ] **Task 0.6**: Verify and fix any import errors.

## Phase 1: Logging Refactor
- [x] **Task 1.1**: Modify `JiraService` in `Sources/App/Services/JiraService.swift`.
    - Add `let logger: Logger` property.
    - Update `init` to accept `Logger`.
    - Replace all `print("[Debug] ...")` with `logger.debug("...")` or `logger.info("...")`.
    - Replace `print("❌ ...")` with `logger.error("...")`.

## Phase 2: Controller Refactor
- [x] **Task 2.1**: Update `MoaController` in `Sources/App/Controllers/MoaController.swift`.
    - In `generateReport`, initialize `JiraService` with `req.logger`.
    - Remove `.get()` calls from `req.view.render(...).get()` and use `try await req.view.render(...)`.
    - Remove `.get()` from `view.encodeResponse(for: req).get()` and use `try await view.encodeResponse(for: req)`.

## Phase 4: Validation (Guideline #4)
- [ ] **Task 4.1**: Update `ReportRequest` in `MoaController.swift` (or move to DTOs).
    - Move `ReportRequest` struct to `Sources/App/DTOs/ReportDTOs.swift`.
    - Conform to `Validatable`.
    - Add validations: `year` (>= 2000), `email` (!empty), `token` (!empty).
- [ ] **Task 4.2**: Update `MoaController.generateReport` to call `req.content.validate(ReportRequest.self)`.

## Phase 5: Leaf Context (Guideline #6)
- [ ] **Task 5.1**: Create `ReportContext` struct in `Sources/App/DTOs/ViewContexts.swift`.
    - Define all fields used in `report.leaf` (e.g., `year`, `issues`, `stats`, etc.).
- [ ] **Task 5.2**: Update `ReportGenerator.generateContext` to return `ReportContext` instead of `[String: Any]`.
- [ ] **Task 5.3**: Update `MoaController` to use the new typed context.
