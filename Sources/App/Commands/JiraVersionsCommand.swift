import Vapor

struct JiraVersionsCommand: Command {
    struct Signature: CommandSignature {
        @Argument(name: "projectKey", help: "The Project Key to test (e.g. KMA)")
        var projectKey: String
        
        @Option(name: "year", short: "y", help: "Filter versions by release year (e.g. 2025)")
        var year: Int?
    }

    var help: String {
        "Fetches and lists project versions from Jira, optionally filtered by year."
    }

    func run(using context: CommandContext, signature: Signature) throws {
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
        let targetYear = signature.year
        
        context.console.print("🚀 Fetching Versions for Project: \(projectKey)")
        if let year = targetYear {
            context.console.print("📅 Filtering by Year: \(year)")
        }
        
        // Load Credentials
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
        
        // Fetch Project Versions
        let versionsUri = URI(string: "\(apiBaseURL)/rest/api/3/project/\(projectKey)/versions")
        let versionsResponse = try await app.client.get(versionsUri, headers: headers)
        
        guard versionsResponse.status == .ok else {
            context.console.print("❌ Failed to fetch versions: \(versionsResponse.status)")
            if let body = versionsResponse.body {
                context.console.print(String(buffer: body))
            }
            return
        }
        
        struct MinimalVersion: Decodable {
            let id: String
            let name: String
            let released: Bool
            let releaseDate: String?
        }
        
        let versions = try versionsResponse.content.decode([MinimalVersion].self)
        
        // Filter logic
        let filteredVersions: [MinimalVersion]
        if let year = targetYear {
            filteredVersions = versions.filter { version in
                guard version.released, let date = version.releaseDate else { return false }
                return date.hasPrefix("\(year)")
            }
        } else {
            filteredVersions = versions
        }
        
        context.console.print("✅ Found \(filteredVersions.count) versions.")
        
        // Sort by date descending
        let sortedVersions = filteredVersions.sorted {
            ($0.releaseDate ?? "") > ($1.releaseDate ?? "")
        }
        
        for version in sortedVersions {
            let dateStr = version.releaseDate ?? "No Date"
            let status = version.released ? "Released" : "Unreleased"
            context.console.print("   - [\(version.id)] \(version.name) (\(dateStr)) - \(status)")
        }
    }
}
