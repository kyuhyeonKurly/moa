import Vapor
import Leaf

public func configure(_ app: Application) async throws {
    // register routes
    app.views.use(.leaf)
    
    // register commands
    app.commands.use(JiraVersionsCommand(), as: "jira-versions")
    app.commands.use(JiraVersionDetailCommand(), as: "jira-version-detail")
    
    try routes(app)
}
