import Vapor
import Leaf

public func configure(_ app: Application) async throws {
    // register routes
    app.views.use(.leaf)
    
    // register commands
    app.commands.use(JiraTestCommand(), as: "jira-test")
    
    try routes(app)
}
