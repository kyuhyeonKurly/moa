import Vapor

struct ConfluencePageResponse: Content {
    let id: String
    let title: String
    let status: String
    let _links: Links
    
    struct Links: Content {
        let webui: String
    }
}

// MARK: - Confluence Current User (for /rest/api/user/current)

struct ConfluenceCurrentUser: Content {
    let accountId: String
    let displayName: String
    let email: String?
}
