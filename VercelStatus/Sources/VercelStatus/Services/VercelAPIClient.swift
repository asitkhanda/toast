import Foundation

enum VercelAPIError: LocalizedError {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int)
    case decodingFailed(Error)
    case network(Error)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Invalid or expired Vercel token. Reconnect in Settings."
        case .forbidden:
            "You don't have permission to access this resource."
        case .notFound:
            "Resource not found."
        case .rateLimited:
            "Vercel rate limit reached. Will retry shortly."
        case .serverError(let code):
            "Vercel server error (\(code))."
        case .decodingFailed:
            "Unexpected response from Vercel."
        case .network(let error):
            error.localizedDescription
        case .invalidURL:
            "Invalid API URL."
        }
    }
}

struct VercelAPIClient: Sendable {
    let token: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
        self.decoder = JSONDecoder()
    }

    func listTeams() async throws -> [Team] {
        let response: TeamsResponse = try await get("/v2/teams")
        return response.teams
    }

    func listProjects(teamId: String) async throws -> [Project] {
        let response: ProjectsResponse = try await get("/v9/projects", query: [
            "teamId": teamId,
            "limit": "100",
        ])
        return response.projects
    }

    func listDeployments(projectId: String, teamId: String, limit: Int = 5) async throws -> [Deployment] {
        let response: DeploymentsResponse = try await get("/v7/deployments", query: [
            "projectId": projectId,
            "teamId": teamId,
            "limit": String(limit),
        ])
        return response.deployments
    }

    func getDeployment(id: String, teamId: String) async throws -> Deployment {
        let response: DeploymentDetailResponse = try await get("/v13/deployments/\(id)", query: [
            "teamId": teamId,
        ])
        return response.asDeployment(fallbackID: id)
    }

    func validateToken() async throws {
        _ = try await listTeams()
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        guard var components = URLComponents(string: "https://api.vercel.com\(path)") else {
            throw VercelAPIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw VercelAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VercelAPIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw VercelAPIError.network(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200 ..< 300:
            break
        case 401:
            throw VercelAPIError.unauthorized
        case 403:
            throw VercelAPIError.forbidden
        case 404:
            throw VercelAPIError.notFound
        case 429:
            throw VercelAPIError.rateLimited
        case 500...:
            throw VercelAPIError.serverError(http.statusCode)
        default:
            throw VercelAPIError.serverError(http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw VercelAPIError.decodingFailed(error)
        }
    }
}
