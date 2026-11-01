import Foundation
import EffiLensKit

/// Dependency container. Built once at launch; passed to feature view models
/// explicitly (no singletons, no global state).
struct AppEnvironment: Sendable {
    let configuration: AppConfiguration
    let session: SessionManager
    let api: APIClient
    let agent: AgentClient?

    var profile: ProfileService { ProfileService(api: api) }
    var consent: ConsentService { ConsentService(api: api) }
    var agentAPI: AgentAPIService { AgentAPIService(api: api) }
    var work: WorkService { WorkService(api: api) }
    var insights: InsightsService { InsightsService(api: api) }
    var leave: LeaveService { LeaveService(api: api) }
    var notifications: NotificationService { NotificationService(api: api) }

    static func live() throws -> AppEnvironment {
        let configuration = try AppConfiguration.load()
        let secrets = KeychainStore(service: configuration.bundleIdentifier)
        let session = SessionManager(configuration: configuration, secrets: secrets)
        let api = APIClient(configuration: configuration, credentials: session)
        let agent = (try? AgentClient.Options.standard()).map(AgentClient.init(options:))
        return AppEnvironment(configuration: configuration, session: session, api: api, agent: agent)
    }
}
