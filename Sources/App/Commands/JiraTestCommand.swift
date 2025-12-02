import Vapor

struct JiraTestCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "projectKey", help: "The Project Key to test (e.g. KMA)")
        var projectKey: String
        
        @Option(name: "year", short: "y", help: "Filter versions by release year (e.g. 2025)")
        var year: Int?
        
        @Option(name: "version", short: "v", help: "Specific Version ID to search issues for (e.g. 14051)")
        var versionId: String?
    }

    var help: String {
        "Tests Jira API integration: Fetch Versions (Filter by Year) -> Search Issues in Latest Version"
    }

    func run(using context: CommandContext, signature: Signature) throws {
        // Create a task to run the async code and wait for it to complete
        let group = DispatchGroup()
        group.enter()
        
        Task {
            do {
                try await runAsync(using: context, signature: signature)
            } catch {
                context.console.print("❌ Error: \(error)")
            }
            group.leave()
        }
        
        group.wait()
    }

    func runAsync(using context: CommandContext, signature: Signature) async throws {
        let app = context.application
        let projectKey = signature.projectKey
        let targetYear = signature.year ?? 2025
        
        context.console.print("🚀 Starting Jira API Test for Project: \(projectKey), Year: \(targetYear)")
        
        // 0. Load Credentials
        let email = Environment.get("JIRA_EMAIL") ?? ""
        let token = Environment.get("JIRA_TOKEN") ?? ""
        
        if email.isEmpty || token.isEmpty {
            context.console.print("❌ Missing JIRA_EMAIL or JIRA_TOKEN in environment variables.")
            return
        }
        
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json"
        ]
        let apiBaseURL = "https://kurly0521.atlassian.net"
        
        // 1. Fetch Project Versions
        context.console.print("\n1️⃣  Test 1: Fetching All Versions & Filtering by Year \(targetYear)...")
        let versionsUri = URI(string: "\(apiBaseURL)/rest/api/3/project/\(projectKey)/versions")
        
        let versionsResponse = try await app.client.get(versionsUri, headers: headers)
        
        guard versionsResponse.status == .ok else {
            context.console.print("❌ Failed to fetch versions: \(versionsResponse.status)")
            if let body = versionsResponse.body {
                context.console.print(String(buffer: body))
            }
            return
        }
        
        // Decode to find a suitable version
        struct MinimalVersion: Decodable {
            let id: String
            let name: String
            let released: Bool
            let releaseDate: String?
        }
        
        let versions = try versionsResponse.content.decode([MinimalVersion].self)
        
        // Filter by Year
        let filteredVersions = versions.filter { version in
            guard version.released, let date = version.releaseDate else { return false }
            return date.hasPrefix("\(targetYear)")
        }
        
        context.console.print("✅ Found \(filteredVersions.count) versions released in \(targetYear).")
        for version in filteredVersions {
            context.console.print("   - \(version.name) (ID: \(version.id), Date: \(version.releaseDate ?? ""))")
        }
        
        if filteredVersions.isEmpty {
            context.console.print("⚠️ No versions found for \(targetYear).")
            // Don't return here, proceed to check if versionId is provided
        }
        
        // 2. Search Issues (Old Step 3)
        let targetVersionId: String
        let targetVersionName: String
        
        if let specificVersionId = signature.versionId {
            context.console.print("\n2️⃣  Test 2: Fetching Issues for specific version ID: \(specificVersionId)...")
            // Try to find name from fetched versions
            if let found = versions.first(where: { $0.id == specificVersionId }) {
                targetVersionId = found.id
                targetVersionName = found.name
            } else {
                targetVersionId = specificVersionId
                targetVersionName = "Unknown (ID: \(specificVersionId))"
            }
        } else {
            context.console.print("\n2️⃣  Test 2: Fetching Issues for the latest version in \(targetYear)...")
            
            if filteredVersions.isEmpty {
                context.console.print("⚠️ No versions found for \(targetYear). Stopping.")
                return
            }
            
            guard let latest = filteredVersions.sorted(by: { $0.releaseDate! > $1.releaseDate! }).first else { return }
            targetVersionId = latest.id
            targetVersionName = latest.name
        }
        
        context.console.print("🎯 Target Version: \(targetVersionName) (ID: \(targetVersionId))")
        
        let searchUri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        let jql = "project = \"\(projectKey)\" AND fixVersion = \(targetVersionId)"
        
        struct SearchRequest: Content {
            let jql: String
            let fields: [String]
            let maxResults: Int
            let nextPageToken: String?
        }
        
        let searchRequest = SearchRequest(
            jql: jql,
            fields: ["summary", "status", "fixVersions"],
            maxResults: 5,
            nextPageToken: nil
        )
        
        let searchResponse = try await app.client.post(searchUri, headers: headers) { req in
            try req.content.encode(searchRequest)
        }
        
        if searchResponse.status == .ok {
            context.console.print("✅ Issues Found:")
            if let body = searchResponse.body {
                context.console.print(String(buffer: body)) // Print raw JSON
            }
        } else {
            context.console.print("❌ Failed to search issues.")
            if let body = searchResponse.body {
                context.console.print(String(buffer: body))
            }
        }
        
        context.console.print("\n✨ Test Completed!")
    }
}
