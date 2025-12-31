# Copilot Constitution & Vapor 4 Master Guidelines

> **CRITICAL INSTRUCTION**: This project follows **Spec-Driven Development**.
> Before writing any code, you MUST check the `specs/` directory for the relevant specification file.
> - `specs/000_system_overview.md`: Core system logic and legacy context.
> - `specs/001_*.md`: Feature-specific specifications.
>
> If a spec does not exist for the requested feature, ask the user to create one or create it yourself before proceeding.

---

# Vapor 4 Framework & Ecosystem Master Guidelines

You are an expert Server-side Swift developer specializing in Vapor 4. You must strictly adhere to the following architectural patterns, coding standards, and security best practices defined below.

## 1. Project Directory Structure
Maintain this strict folder hierarchy. Do not place files randomly.

```
.
├── Package.swift               # Dependencies manifest
├── Public                      # Static assets (Served directly to browser via FileMiddleware)
│   ├── images                  # Image files (Logo, Icons, Banners - png/jpg/svg)
│   ├── styles                  # CSS stylesheets (Design, Layout, Fonts)
│   └── scripts                 # Client-side JavaScript (ONLY for light interactions or Alpine.js)
├── Resources
│   └── Views                   # Leaf templates (Server-side rendered HTML)
└── Sources
    └── App
        ├── Controllers         # RouteCollections (Request logic & Response handling)
        ├── DTOs                # Data Transfer Objects (Strictly typed JSON structs)
        ├── Models              # Fluent Models (Database Tables & Schemas)
        ├── Migrations          # Database Schema Version Control
        ├── Services            # Business Logic, External API Clients
        ├── Middleware          # Custom Request/Response Interceptors
        ├── Commands            # Custom CLI Tools (e.g., Admin tasks)
        ├── Jobs                # Queue Workers (Background tasks like Emails)
        ├── configure.swift     # Application Setup (DB, Middleware, Services)
        ├── entrypoint.swift    # Application Entry Point (@main)
        └── routes.swift        # Route Definitions (End-points)
```

## 2. Core Principles & Basics
- **Concurrency**: ALWAYS use Swift's native Concurrency (`async`/`await`). DO NOT use `EventLoopFuture` unless dealing with legacy dependencies.
- **Error Handling**: Throw `Abort(.status, reason: String)` for HTTP errors.
- **Logging**: Use `req.logger` (e.g., `req.logger.info("...")`) instead of `print()`.
- **Environment**: Never hardcode secrets. Use `Environment.get("KEY")` or `.env` files.

## 3. Controllers & Routing
- **Protocol**: Controllers must conform to `RouteCollection`.
- **Boot**: Implement `func boot(routes: RoutesBuilder) throws`.
- **Registration**: ALWAYS suggest registering new controllers in `routes.swift` or `configure.swift` (e.g., `try app.register(collection: MyController())`).

## 4. Content, Validation & DTOs
- **Strict Separation**: NEVER expose Fluent `Model` classes directly in API responses or Views.
- **DTOs**: Create structs in `Sources/App/DTOs` conforming to `Content`.
- **Validation**: Implement `Validatable` on input DTOs and call `req.content.validate(InputDTO.self)` before decoding.

## 5. Database (Fluent)
- **Models**: Conform to `Model`. Use `UUID` for IDs. Use `@Parent`, `@Children`, `@Siblings` for relationships.
- **Migrations**: Every Model MUST have a corresponding `AsyncMigration`.
    - Define constraints strictly (`.required`, `.unique`).
    - Use `.references()` for Foreign Keys to ensure integrity.
- **Performance**: Use Eager Loading (`.with(\.$relation)`) to prevent N+1 query issues.
- **Transactions**: Use `req.db.transaction { ... }` for atomic operations.

## 6. Leaf Templating
- **Files**: All templates reside in `Resources/Views`. Extension must be `.leaf`.
- **Syntax**:
    - Extend layouts: `#extend("base"): ... #endextend`
    - Variables: `#(variableName)`
    - Loops/Conditions: `#for(item in items):`, `#if(condition):`
- **Context**: Pass data via `ViewContext` structs, not raw Models.

## 7. Frontend Architecture (HTMX & Alpine.js)
Prefer **HTMX** for server-driven interactions and **Alpine.js** for client-side logic to minimize custom JavaScript.

- **HTMX Usage**:
    - Use `hx-get`, `hx-post`, `hx-delete` to trigger server actions without full page reloads.
    - Use `hx-target` and `hx-swap` to update specific DOM elements.
    - **Response**: Return HTML fragments (partials), NOT JSON. Create small Leaf files (e.g., `_user_row.leaf`) for these fragments.
- **Alpine.js Usage**:
    - Use for purely client-side interactivity (toggling modals, dropdowns) where server roundtrip is unnecessary.
    - Example: `<div x-data="{ open: false }">`

## 8. Redis & Caching (In-Memory DB)
- **Sessions**: Prefer Redis for session storage in production: `app.sessions.use(.redis)`.
- **Caching**: Use `req.cache` backed by Redis for high-performance data retrieval.
- **TTL**: ALWAYS set an expiration time (`expiresIn:`) when caching to manage memory usage.

## 9. Advanced Features
- **Middleware**: Create custom `AsyncMiddleware` for request interception. Register order matters in `configure.swift`.
- **Queues**: Use `app.queues` for background tasks (email sending, image processing). Define `Job` structs.
- **Commands**: Conform to `Command` for custom CLI tools.
- **WebSockets**: Use `routes.webSocket("path") { req, ws in ... }`.

## 10. Security & Authentication
- **Passwords**: NEVER store plain text passwords. Use `Bcrypt` for hashing (`req.password.hash(password)`).
- **Authentication**:
    - Conform User models to `ModelAuthenticatable`.
    - Use built-in middleware: `User.authenticator()`, `User.guardMiddleware()`.
- **JWT**: For stateless auth, use `JWTPayload` and `app.jwt.signers`.

## 11. Swift Language & Style Guidelines
Adhere to the [Apple API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and the following best practices:

### Naming & Clarity
- **Clarity over Brevity**: Names should be precise. `fetchUser(by: id)` is preferred over `getUser(id)`.
- **CamelCase**: Use `UpperCamelCase` for types/protocols and `lowerCamelCase` for everything else.
- **Boolean Properties**: Prefix with `is`, `has`, `should` (e.g., `isVisible`, `hasAccess`).
- **Context**: Avoid repeating type information in properties (e.g., `user.name` instead of `user.userName`).

### Safety & Optionals
- **No Force Unwrapping**: NEVER use `!` unless absolutely certain (e.g., URL initialization from static string). Use `guard let` or `if let`.
- **Implicitly Unwrapped Optionals**: Avoid `Type!` unless required by the framework (e.g., `@IBOutlet`).
- **Coalescing**: Use `??` to provide default values.

### Code Structure & Formatting
- **Extensions**: Use `extension` to separate protocol conformance and logical grouping.
- **MARK Comments**: Use `// MARK: - Section Name` to organize code within files.
- **Trailing Closures**: Use trailing closure syntax for the last closure argument.
- **Guard Statements**: Use `guard` for early exits to reduce nesting (the "happy path" should be left-aligned).

### Modern Swift Features
- **Result Type**: Use `Result<Success, Error>` for complex completion handlers (though `async/await` is preferred).
- **Computed Properties**: Prefer computed properties over methods for simple getters (O(1) complexity).
- **Final**: Mark classes as `final` by default unless inheritance is specifically intended.


⚠️ Agent Instruction: IGNORE THE TRANSLATION BELOW. Proceed only with the English Master Guidelines.
Copilot 헌법 및 Vapor 4 마스터 지침 (한글 번역)
핵심 지침 (CRITICAL INSTRUCTION): 이 프로젝트는 **사양 주도 개발(Spec-Driven Development)**을 따릅니다. 코드를 작성하기 전에 반드시 specs/ 디렉토리에서 관련 사양 파일을 확인해야 합니다.

specs/000_system_overview.md: 핵심 시스템 로직 및 레거시 컨텍스트.

specs/001_*.md: 기능별 사양.

요청된 기능에 대한 사양 파일이 존재하지 않는 경우, 사용자에게 생성을 요청하거나 개발자가 직접 생성한 후 진행해야 합니다.

Vapor 4 프레임워크 및 생태계 마스터 지침
당신은 Vapor 4를 전문으로 하는 서버 측 Swift 개발 전문가입니다. 아래에 정의된 아키텍처 패턴, 코딩 표준 및 보안 모범 사례를 엄격하게 준수해야 합니다.

1. 프로젝트 디렉토리 구조
이 엄격한 폴더 계층 구조를 유지해야 합니다. 파일을 무작위로 배치하지 마십시오.

.
├── Package.swift               # 종속성(Dependencies) 매니페스트
├── Public                      # 정적 자산 (FileMiddleware를 통해 브라우저에 직접 제공됨)
│   ├── images                  # 이미지 파일 (로고, 아이콘, 배너 - png/jpg/svg)
│   ├── styles                  # CSS 스타일시트 (디자인, 레이아웃, 글꼴)
│   └── scripts                 # 클라이언트 측 JavaScript (가벼운 상호 작용 또는 Alpine.js에만 사용)
├── Resources
│   └── Views                   # Leaf 템플릿 (서버 측 렌더링된 HTML)
└── Sources
    └── App
        ├── Controllers         # RouteCollection (요청 로직 및 응답 처리)
        ├── DTOs                # 데이터 전송 객체 (엄격하게 타입 지정된 JSON 구조체)
        ├── Models              # Fluent 모델 (데이터베이스 테이블 및 스키마)
        ├── Migrations          # 데이터베이스 스키마 버전 관리
        ├── Services            # 비즈니스 로직, 외부 API 클라이언트
        ├── Middleware          # 사용자 지정 요청/응답 인터셉터
        ├── Commands            # 사용자 지정 CLI 도구 (예: 관리자 작업)
        ├── Jobs                # 큐 워커 (이메일과 같은 백그라운드 작업)
        ├── configure.swift     # 애플리케이션 설정 (DB, 미들웨어, 서비스)
        ├── entrypoint.swift    # 애플리케이션 시작점 (@main)
        └── routes.swift        # 라우트 정의 (엔드포인트)
2. 핵심 원칙 및 기본 사항
동시성 (Concurrency): 항상 Swift의 네이티브 동시성 (async/await)을 사용해야 합니다. 레거시 종속성을 처리하는 경우가 아니면 EventLoopFuture를 사용하지 마십시오.

오류 처리: HTTP 오류의 경우 Abort(.status, reason: String)를 throw 합니다.

로깅: print() 대신 req.logger를 사용합니다 (예: req.logger.info("...")).

환경 변수: 보안 정보를 하드 코딩하지 마십시오. Environment.get("KEY") 또는 .env 파일을 사용하십시오.

3. 컨트롤러 및 라우팅
프로토콜: 컨트롤러는 RouteCollection을 준수해야 합니다.

부트: func boot(routes: RoutesBuilder) throws를 구현해야 합니다.

등록: routes.swift 또는 configure.swift에 새 컨트롤러를 등록하도록 항상 제안해야 합니다 (예: try app.register(collection: MyController())).

4. 콘텐츠, 유효성 검사 및 DTO
엄격한 분리: API 응답이나 View에서 Fluent Model 클래스를 직접 절대 노출하지 마십시오.

DTO: Sources/App/DTOs에 Content를 준수하는 구조체를 생성합니다.

유효성 검사: 입력 DTO에 Validatable을 구현하고 디코딩하기 전에 req.content.validate(InputDTO.self)를 호출합니다.

5. 데이터베이스 (Fluent)
모델: Model을 준수합니다. ID에는 UUID를 사용합니다. 관계에는 @Parent, @Children, @Siblings를 사용합니다.

마이그레이션: 모든 모델은 해당 AsyncMigration을 반드시 가져야 합니다.

제약 조건(required, .unique)을 엄격하게 정의합니다.

무결성을 보장하기 위해 외래 키에 .references()를 사용합니다.

성능: N+1 쿼리 문제를 방지하기 위해 Eager Loading (.with(\.$relation))을 사용합니다.

트랜잭션: 원자적 작업에는 req.db.transaction { ... }를 사용합니다.

6. Leaf 템플릿
파일: 모든 템플릿은 Resources/Views에 있습니다. 확장자는 .leaf여야 합니다.

구문:

레이아웃 확장: #extend("base"): ... #endextend

변수: #(variableName)

루프/조건: #for(item in items):, #if(condition):

컨텍스트: 원시 모델(raw Models)이 아닌 ViewContext 구조체를 통해 데이터를 전달합니다.

7. 프론트엔드 아키텍처 (HTMX & Alpine.js)
서버 주도 상호 작용에는 HTMX를, 클라이언트 측 로직에는 Alpine.js를 선호하여 사용자 지정 JavaScript를 최소화합니다.

HTMX 사용:

hx-get, hx-post, hx-delete를 사용하여 전체 페이지를 다시 로드하지 않고 서버 작업을 트리거합니다.

hx-target 및 hx-swap을 사용하여 특정 DOM 요소를 업데이트합니다.

응답: JSON이 아닌 HTML 조각(부분)을 반환합니다. 이러한 조각을 위해 작은 Leaf 파일(예: _user_row.leaf)을 생성합니다.

Alpine.js 사용:

서버 왕복이 불필요한 순수한 클라이언트 측 상호 작용(모달 토글, 드롭다운)에 사용합니다.

예시: <div x-data="{ open: false }">

8. Redis 및 캐싱 (인메모리 DB)
세션: 프로덕션 환경에서는 Redis를 세션 저장소로 선호합니다: app.sessions.use(.redis).

캐싱: 고성능 데이터 검색을 위해 Redis를 백엔드로 사용하는 req.cache를 사용합니다.

TTL: 메모리 관리를 위해 캐싱할 때 항상 만료 시간(expiresIn:)을 설정해야 합니다.

9. 고급 기능
미들웨어: 요청 가로채기를 위해 사용자 지정 AsyncMiddleware를 생성합니다. configure.swift에서 등록 순서가 중요합니다.

큐: 백그라운드 작업(이메일 전송, 이미지 처리)에는 app.queues를 사용합니다. Job 구조체를 정의합니다.

명령: 사용자 지정 CLI 도구에는 Command를 준수합니다.

웹소켓: routes.webSocket("path") { req, ws in ... }를 사용합니다.

10. 보안 및 인증
암호: 일반 텍스트 암호를 절대 저장하지 마십시오. 해싱에는 Bcrypt를 사용합니다 (req.password.hash(password)).

인증:

사용자 모델이 ModelAuthenticatable을 준수하도록 합니다.

내장 미들웨어 사용: User.authenticator(), User.guardMiddleware().

JWT: 상태 비저장 인증에는 JWTPayload 및 app.jwt.signers를 사용합니다.

11. Swift 언어 및 스타일 가이드
[Apple API 설계 가이드라인](https://www.swift.org/documentation/api-design-guidelines/) 및 다음 모범 사례를 준수하십시오.

명명 및 명확성
- **명확성 우선**: 이름은 정확해야 합니다. `getUser(id)`보다 `fetchUser(by: id)`를 선호합니다.
- **CamelCase**: 타입/프로토콜에는 `UpperCamelCase`를, 그 외에는 `lowerCamelCase`를 사용합니다.
- **Boolean 속성**: `is`, `has`, `should` 접두사를 사용합니다 (예: `isVisible`, `hasAccess`).
- **컨텍스트**: 속성 이름에 타입 정보를 반복하지 마십시오 (예: `user.userName` 대신 `user.name`).

안전성 및 옵셔널
- **강제 언래핑 금지**: 절대적으로 확실한 경우(예: 정적 문자열에서 URL 초기화)가 아니면 `!`를 절대 사용하지 마십시오. `guard let` 또는 `if let`을 사용하십시오.
- **암시적 언래핑 옵셔널**: 프레임워크에서 요구하는 경우(예: `@IBOutlet`)가 아니면 `Type!`을 피하십시오.
- **Coalescing**: 기본값을 제공하려면 `??`를 사용하십시오.

코드 구조 및 서식
- **Extensions**: 프로토콜 준수 및 논리적 그룹화를 분리하기 위해 `extension`을 사용하십시오.
- **MARK 주석**: 파일 내 코드를 정리하기 위해 `// MARK: - Section Name`을 사용하십시오.
- **후행 클로저**: 마지막 클로저 인수에 대해 후행 클로저 구문을 사용하십시오.
- **Guard 문**: 중첩을 줄이기 위해 조기 종료에 `guard`를 사용하십시오 ("행복한 경로"는 왼쪽 정렬되어야 함).

최신 Swift 기능
- **Result 타입**: 복잡한 완료 핸들러에는 `Result<Success, Error>`를 사용하십시오 (단, `async/await`가 선호됨).
- **계산 속성**: 단순 getter(O(1) 복잡도)의 경우 메서드보다 계산 속성을 선호하십시오.
- **Final**: 상속이 구체적으로 의도되지 않은 경우 클래스를 기본적으로 `final`로 표시하십시오.