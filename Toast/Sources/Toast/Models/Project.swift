import Foundation

struct Team: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let slug: String?
    let name: String?

    var displayName: String {
        name ?? slug ?? id
    }
}

struct TeamsResponse: Codable, Sendable {
    let teams: [Team]
}

struct Project: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let accountId: String?
    let updatedAt: TimeInterval?
    let link: ProjectLink?

    var displayName: String {
        switch CloudflareProjectKind(projectID: id) {
        case .pages: "\(name) (Pages)"
        case .worker: "\(name) (Worker)"
        case nil: name
        }
    }
}

struct ProjectLink: Codable, Sendable, Hashable {
    let type: String?
    let repo: String?
    let org: String?
}

struct ProjectsResponse: Codable, Sendable {
    let projects: [Project]
}

struct WatchedProject: Codable, Identifiable, Sendable, Hashable {
    let projectId: String
    let projectName: String
    /// Vercel team ID, or Cloudflare account ID.
    let teamId: String
    let provider: DeploymentProvider

    init(
        projectId: String,
        projectName: String,
        teamId: String,
        provider: DeploymentProvider = .vercel
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.teamId = teamId
        self.provider = provider
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectId = try container.decode(String.self, forKey: .projectId)
        projectName = try container.decode(String.self, forKey: .projectName)
        teamId = try container.decode(String.self, forKey: .teamId)
        // Watched projects saved before multi-provider support are all Vercel.
        provider = try container.decodeIfPresent(DeploymentProvider.self, forKey: .provider) ?? .vercel
    }

    /// Vercel IDs keep their original format so saved state stays valid.
    var id: String {
        switch provider {
        case .vercel: "\(teamId):\(projectId)"
        case .cloudflare: "\(provider.rawValue):\(teamId):\(projectId)"
        }
    }
}
