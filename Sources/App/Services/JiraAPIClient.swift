import Vapor

final class JiraAPIClient {
    let client: Client
    let apiBaseURL = "https://kurly0521.atlassian.net"
    let headers: HTTPHeaders

    init(client: Client, email: String, token: String) {
        self.client = client
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        self.headers = [
            "Authorization": "Basic \(authString)",
            "Accept": "application/json",
            "Content-Type": "application/json"
        ]
    }

    func fetchProjectVersions(projectKey: String) async throws -> [JiraProjectVersion] {
        let uri = URI(string: "\(apiBaseURL)/rest/api/3/project/\(projectKey)/versions")
        let response = try await client.get(uri, headers: headers)
        
        guard response.status == .ok else {
            return []
        }
        
        return try response.content.decode([JiraProjectVersion].self)
    }

    func searchIssues(jql: String, fields: [String], maxResults: Int, nextPageToken: String?) async throws -> JiraSearchResponse {
        let uri = URI(string: "\(apiBaseURL)/rest/api/3/search/jql")
        let searchRequest = JiraSearchRequest(
            jql: jql,
            fields: fields,
            maxResults: maxResults,
            nextPageToken: nextPageToken
        )
        
        let response = try await client.post(uri, headers: headers) { req in
            try req.content.encode(searchRequest)
        }
        
        guard response.status == .ok else {
            let body = response.body.map { String(buffer: $0) } ?? "No body"
            throw Abort(.internalServerError, reason: "Jira API Error: \(body)")
        }
        
        return try response.content.decode(JiraSearchResponse.self)
    }
}
