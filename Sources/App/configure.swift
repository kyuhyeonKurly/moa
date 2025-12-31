import Vapor
import Leaf

public func configure(_ app: Application) async throws {
    // register routes
    app.views.use(.leaf)
    
    // register commands
    app.commands.use(JiraVersionsCommand(), as: "jira-versions")
    app.commands.use(JiraVersionDetailCommand(), as: "jira-version-detail")
    app.commands.use(JiraTicketsCommand(), as: "jira-tickets")
    app.commands.use(JiraIssueDetailCommand(), as: "jira-detail")
    app.commands.use(JiraExportCommand(), as: "jira-export")
    app.commands.use(JiraTreeCommand(), as: "jira-tree")
    app.commands.use(JiraRetrospectiveCommand(), as: "jira-retrospective")
    app.commands.use(JiraDomainGuidelineCommand(), as: "jira-domain-guideline")
    
    try routes(app)
}
