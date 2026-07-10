import Vapor
import Leaf

public func configure(_ app: Application) async throws {
    // register routes
    app.views.use(.leaf)
    
    // register commands - Jira
    app.commands.use(JiraVersionsCommand(), as: "jira-versions")
    app.commands.use(JiraVersionDetailCommand(), as: "jira-version-detail")
    app.commands.use(JiraTicketsCommand(), as: "jira-tickets")
    app.commands.use(JiraIssueDetailCommand(), as: "jira-detail")
    app.commands.use(JiraExportCommand(), as: "jira-export")
    app.commands.use(JiraTreeCommand(), as: "jira-tree")
    app.commands.use(JiraRetrospectiveCommand(), as: "jira-retrospective")
    app.commands.use(JiraDomainGuidelineCommand(), as: "jira-domain-guideline")
    app.commands.use(JiraDomainDetailCommand(), as: "jira-domain-detail")
    app.commands.use(JiraIssueTypeCommand(), as: "jira-issue-type")
    app.commands.use(JiraTicketDetailCommand(), as: "jira-ticket-detail")

    // 반기 성과 취합
    app.commands.use(RoundupWikiCommand(), as: "roundup-wiki")
    
    // register commands - Confluence
    app.commands.use(ConfluenceWikiCommand(), as: "confluence-wiki")
    app.commands.use(ConfluenceChildrenCommand(), as: "confluence-children")
    app.commands.use(ConfluenceOrganizeCommand(), as: "confluence-organize")
    app.commands.use(ConfluenceOrganizeCommand(), as: "confluence-organize")
    app.commands.use(ConfluenceOrganizeCommand(), as: "confluence-organize")
    
    try routes(app)
}
