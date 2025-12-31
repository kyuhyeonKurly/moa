import Vapor

struct ReportRequest: Content, Validatable {
    let year: Int
    let assignee: String?
    let email: String
    let token: String
    let spaceKey: String?
    let platform: String? // "iOS" or "Android"

    static func validations(_ validations: inout Validations) {
        validations.add("year", as: Int.self, is: .range(2000...2100))
        validations.add("email", as: String.self, is: !.empty)
        validations.add("token", as: String.self, is: !.empty)
    }
    
    func validate() throws {
        guard (2000...2100).contains(year) else {
            throw Abort(.badRequest, reason: "Year must be between 2000 and 2100")
        }
        guard !email.isEmpty else {
            throw Abort(.badRequest, reason: "Email is required")
        }
        guard !token.isEmpty else {
            throw Abort(.badRequest, reason: "Token is required")
        }
    }
}
