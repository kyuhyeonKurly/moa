import Vapor

struct ConfluenceService {
    let client: Client
    let apiBaseURL = "https://kurly0521.atlassian.net/wiki"

    func createPage(spaceKey: String, title: String, htmlContent: String, email: String, token: String) async throws -> String {
        let authString = "\(email):\(token)".data(using: .utf8)?.base64EncodedString() ?? ""
        
        let headers: HTTPHeaders = [
            "Authorization": "Basic \(authString)",
            "Content-Type": "application/json"
        ]
        
        let uri = URI(string: "\(apiBaseURL)/rest/api/content")
        
        let requestBody = ConfluencePageCreateRequest(
            title: title,
            type: "page",
            space: .init(key: spaceKey),
            status: "draft",
            body: .init(storage: .init(value: htmlContent, representation: "storage"))
        )
        
        let response = try await client.post(uri, headers: headers) { req in
            try req.content.encode(requestBody)
        }
        
        guard response.status == .ok || response.status == .created else {
            let body = response.body.map { String(buffer: $0) } ?? "No body"
            throw Abort(.internalServerError, reason: "Confluence API Error (\(response.status)): \(body)")
        }
        
        let result = try response.content.decode(ConfluencePageResponse.self)
        return result.id
    }
}

