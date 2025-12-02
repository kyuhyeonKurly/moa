import Vapor

struct JiraTestCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "projectKey", help: "The Project Key to test (e.g. KMA)")
        var projectKey: String
    }

    var help: String {
        "Tests Jira API integration: Fetch Versions -> Get Version Details -> Search Issues"
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
        
        context.console.print("🚀 Starting Jira API Test for Project: \(projectKey)")
        
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
        context.console.print("\n1️⃣  Step 1: Fetching Project Versions...")
        let versionsUri = URI(string: "\(apiBaseURL)/rest/api/3/project/\(projectKey)/versions")
        
        let versionsResponse = try await app.client.get(versionsUri, headers: headers)
        
        guard versionsResponse.status == .ok else {
            context.console.print("❌ Failed to fetch versions: \(versionsResponse.status)")
            if let body = versionsResponse.body {
                context.console.print(String(buffer: body))
            }
            
            // Debug: List all visible projects
            context.console.print("\n🔍 Debug: Listing all visible projects...")
            let projectsUri = URI(string: "\(apiBaseURL)/rest/api/3/project")
            let projectsResponse = try await app.client.get(projectsUri, headers: headers)
            
            if projectsResponse.status == .ok, projectsResponse.body != nil {
                struct Project: Decodable {
                    let key: String
                    let name: String
                }
                let projects = try? projectsResponse.content.decode([Project].self)
                let keys = projects?.map { "\($0.key) (\($0.name))" }.joined(separator: ", ") ?? "None"
                context.console.print("📋 Visible Projects: \(keys)")
            } else {
                context.console.print("❌ Failed to list projects: \(projectsResponse.status)")
            }
            
            return
        }
        
        // Decode to find a suitable version (released in 2025 or latest released)
        struct MinimalVersion: Decodable {
            let id: String
            let name: String
            let released: Bool
            let releaseDate: String?
        }
        
        let versions = try versionsResponse.content.decode([MinimalVersion].self)
        
        // Print pretty JSON for inspection
        if let body = versionsResponse.body,
           let data = body.getData(at: 0, length: body.readableBytes),
           let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            context.console.print("✅ Versions JSON Structure (First 3 items):")
            // Too long to print all, just print a snippet or the whole thing if user wants schema
            // User asked for schema, but 299 versions is huge. Let's print the first item only to show schema.
            if let array = jsonObject as? [[String: Any]], let first = array.first,
               let firstData = try? JSONSerialization.data(withJSONObject: first, options: [.prettyPrinted]),
               let firstString = String(data: firstData, encoding: .utf8) {
                context.console.print(firstString)
                context.console.print("... (and \(array.count - 1) more)")
            } else {
                context.console.print(prettyString)
            }
        }
        
        context.console.print("✅ Found \(versions.count) versions.")
        
        // Find a target version to test (Preferably released, and recent)
        guard let targetVersion = versions.filter({ $0.released && $0.releaseDate != nil }).sorted(by: { $0.releaseDate! > $1.releaseDate! }).first else {
            context.console.print("⚠️ No released versions found with a release date.")
            return
        }
        
        context.console.print("🎯 Target Version: \(targetVersion.name) (ID: \(targetVersion.id), Date: \(targetVersion.releaseDate ?? "N/A"))")
        
        // 2. Fetch Version Details
        context.console.print("\n2️⃣  Step 2: Fetching Version Details...")
        let versionDetailUri = URI(string: "\(apiBaseURL)/rest/api/3/version/\(targetVersion.id)")
        let versionDetailResponse = try await app.client.get(versionDetailUri, headers: headers)
        
        if versionDetailResponse.status == .ok {
            context.console.print("✅ Version Details Fetched:")
            if let body = versionDetailResponse.body {
                context.console.print(String(buffer: body)) // Print raw JSON to verify format
            }
        } else {
            context.console.print("❌ Failed to fetch version details.")
        }
        
        // 3. Search Issues in this Version
        context.console.print("\n3️⃣  Step 3: Searching Issues in Version...")
        let searchUri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        // JQL needs to be properly escaped or passed in body
        let jql = "project = \"\(projectKey)\" AND fixVersion = \(targetVersion.id)"
        
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
