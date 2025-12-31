import Vapor

struct ConfluencePageCreateRequest: Content {
    let title: String
    let type: String
    let space: Space
    let status: String
    let body: Body
    
    struct Space: Content {
        let key: String
    }
    
    struct Body: Content {
        let storage: Storage
    }
    
    struct Storage: Content {
        let value: String
        let representation: String
    }
}
