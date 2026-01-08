import Vapor

// MARK: - Confluence Search Response

struct ConfluenceSearchResponse: Content {
    let results: [ConfluenceSearchResult]
    let start: Int
    let limit: Int
    let size: Int
    let _links: ConfluenceSearchLinks?
}

struct ConfluenceSearchResult: Content {
    let content: ConfluenceContent?
    let title: String?
    let excerpt: String?
    let url: String?
    let lastModified: String?
}

struct ConfluenceContent: Content {
    let id: String
    let type: String
    let status: String
    let title: String
    let _links: ConfluenceContentLinks?
    let history: ConfluenceHistory?
    let space: ConfluenceSpace?
}

struct ConfluenceContentLinks: Content {
    let webui: String?
    let tinyui: String?
}

struct ConfluenceHistory: Content {
    let createdDate: String?
    let createdBy: ConfluenceUser?
    let lastUpdated: ConfluenceLastUpdated?
}

struct ConfluenceLastUpdated: Content {
    let `when`: String?
    let by: ConfluenceUser?
}

struct ConfluenceUser: Content {
    let accountId: String?
    let email: String?
    let publicName: String?
    let displayName: String?
}

struct ConfluenceSpace: Content {
    let id: Int?
    let key: String
    let name: String?
}

struct ConfluenceSearchLinks: Content {
    let base: String?
    let next: String?
}

// MARK: - Content API Response (for direct content listing)

struct ConfluenceContentListResponse: Content {
    let results: [ConfluenceContent]
    let start: Int
    let limit: Int
    let size: Int
    let _links: ConfluenceSearchLinks?
}

// MARK: - Page with Depth (for tree structure)

/// 페이지와 트리에서의 깊이 정보를 함께 저장하는 구조체
struct ConfluencePageNode {
    let page: ConfluenceContent
    let depth: Int
    
    var title: String { page.title }
    var id: String { page.id }
    var webLink: String? { page._links?.webui }
    var createdDate: String? { page.history?.createdDate }
    var createdBy: String? { page.history?.createdBy?.displayName }
}

// MARK: - Confluence Update Requests

struct ConfluencePageUpdateRequest: Content {
    let id: String?
    let type: String
    let title: String?
    let space: ConfluenceSpaceReference
    let status: String?
    let body: ConfluencePageBody?
    let version: ConfluencePageVersion?
    let ancestors: [ConfluenceAncestor]?
}

struct ConfluenceSpaceReference: Content {
    let key: String
}

struct ConfluencePageBody: Content {
    let storage: ConfluenceStorage
}

struct ConfluenceStorage: Content {
    let value: String
    let representation: String
}

struct ConfluencePageVersion: Content {
    let number: Int
    let minorEdit: Bool
}

struct ConfluenceAncestor: Content {
    let id: String
    let type: String
    let title: String
}

// MARK: - Confluence Update Response

struct ConfluencePageUpdateResponse: Content {
    let id: String
    let type: String
    let status: String
    let title: String
    let space: ConfluenceSpace?
    let history: ConfluenceHistory?
    let version: ConfluencePageVersion?
}

// MARK: - Confluence Organization Rules

struct ConfluenceOrganizationRule: Codable {
    enum ActionType: String, Codable {
        case move = "move"
        case rename = "rename"
        case addLabel = "addLabel"
        case archive = "archive"
    }
    
    let action: ActionType
    let condition: String
    let target: String
    let description: String
}

struct ConfluenceOrganizationResult: Codable {
    let pageId: String
    let title: String
    let action: ConfluenceOrganizationRule.ActionType
    let oldLocation: String?
    let newLocation: String?
    let status: String // "success" | "failed" | "skipped"
    let message: String?
}
