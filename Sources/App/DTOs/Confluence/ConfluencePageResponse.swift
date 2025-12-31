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
