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

    var displayName: String { name }
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
    let teamId: String

    var id: String { "\(teamId):\(projectId)" }
}
