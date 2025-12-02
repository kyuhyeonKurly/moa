import Vapor

extension Application {
    var jiraClient: JiraAPIClient {
        guard let email = Environment.get("JIRA_EMAIL"),
              let token = Environment.get("JIRA_TOKEN") else {
            fatalError("JIRA_EMAIL or JIRA_TOKEN is missing in environment.")
        }
        return JiraAPIClient(client: self.client, email: email, token: token)
    }
}
