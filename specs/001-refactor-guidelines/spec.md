# Spec 001: Refactor Codebase to Vapor 4 Master Guidelines

## 1. Intent
Refactor the existing codebase to strictly adhere to the "Vapor 4 Framework & Ecosystem Master Guidelines" defined in `.github/copilot-instructions.md`. This ensures maintainability, security, and performance before adding new features.

## 2. Context
- **Current State**: The codebase contains legacy patterns such as `print()` statements for debugging and potentially mixed concurrency patterns (`.get()` on futures).
- **Goal**: Clean up `JiraService` and `MoaController` to match the guidelines.

## 3. Requirements

### 3.1 Logging
- **Guideline**: "Use `req.logger` instead of `print()`."
- **Target**: `Sources/App/Services/JiraService.swift` uses `print()` extensively.
- **Action**:
    - Inject `Logger` into `JiraService`.
    - Replace all `print()` calls with `logger.info()`, `logger.debug()`, or `logger.error()`.

### 3.2 Concurrency
- **Guideline**: "ALWAYS use Swift's native Concurrency (`async`/`await`). DO NOT use `EventLoopFuture`."
- **Target**: `Sources/App/Controllers/MoaController.swift` uses `.get()` on futures inside async functions.
- **Action**:
    - Remove `.get()` calls and use direct `await` on `EventLoopFuture`s (Vapor 4 supports this).

### 3.3 Code Style
- Ensure strict separation of concerns.
- Verify DTO usage (already mostly good, but double check).

### 3.4 Directory Structure (Critical)
- **Guideline**: "Maintain this strict folder hierarchy. Do not place files randomly."
- **Current State**: 
    - `Sources/App/Models` contains API response structs (DTOs), not Fluent Models.
    - `Sources/App/DTOs` does not exist.
    - `Sources/App/Extensions` exists but is not in the master guideline (should be reviewed).
- **Action**:
    - Create `Sources/App/DTOs`.
    - Move `JiraModels.swift`, `JiraVersionModel.swift`, and `Confluence/` from `Models` to `DTOs`.
    - Ensure `Models` is reserved for Fluent DB models (or empty if no DB).

### 3.5 Validation & DTOs (Guideline #4)
- **Guideline**: "Implement `Validatable` on input DTOs and call `req.content.validate(InputDTO.self)` before decoding."
- **Current State**: `MoaController` decodes `ReportRequest` but does not validate it.
- **Action**:
    - Conform `ReportRequest` to `Validatable`.
    - Add validation rules (e.g., year > 2000, email not empty).
    - Call `req.content.validate(ReportRequest.self)` in `generateReport`.

### 3.6 Leaf Context (Guideline #6)
- **Guideline**: "Pass data via `ViewContext` structs, not raw Models."
- **Current State**: `ReportGenerator` returns `[String: Any]`, which is untyped and risky.
- **Action**:
    - Create explicit `ReportContext` struct in `Sources/App/DTOs/ViewContexts.swift`.
    - Update `ReportGenerator` to return `ReportContext`.
    - Update `MoaController` to pass `ReportContext` to Leaf.

## 4. Implementation Plan
1.  **Directory Restructuring**: Create `DTOs` folder, move files, update references.
2.  **Refactor JiraService**: Update initializer to take `Logger`, replace prints.
3.  **Update MoaController**: Pass `req.logger` to `JiraService`, clean up async calls.
4.  **Validation**: Implement `Validatable` for `ReportRequest`.
5.  **View Context**: Replace `[String: Any]` with `ReportContext` struct.
