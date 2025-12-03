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
