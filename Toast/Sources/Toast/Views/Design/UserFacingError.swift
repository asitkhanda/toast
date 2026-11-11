import Foundation

/// A plain-language error: what happened, why, and what to do next.
struct UserFacingError: Equatable {
    enum Action: Equatable {
        case replaceToken
        case retry
        case openSettings
    }

    let title: String
    let explanation: String
    let nextStep: String?
    let action: Action?

    var message: String {
        [explanation, nextStep].compactMap { $0 }.joined(separator: " ")
    }

    static func from(_ error: Error) -> UserFacingError {
        if let error = error as? VercelAPIError { return map(error) }
        if let error = error as? CloudflareAPIError { return map(error) }
        if let error = error as? KeychainError { return map(error) }
        if let error = error as? URLError { return network(error, service: nil) }
        if let error = error as? OnboardingError {
            return UserFacingError(
                title: "Pick at least one project",
                explanation: error.localizedDescription,
                nextStep: nil,
                action: nil
            )
        }
        return UserFacingError(
            title: "Something went wrong",
            explanation: error.localizedDescription,
            nextStep: "Try again in a moment.",
            action: .retry
        )
    }

    private static func map(_ error: VercelAPIError) -> UserFacingError {
        common(
            service: "Vercel",
            unauthorized: error.isUnauthorized,
            forbidden: error.isForbidden,
            notFound: error.isNotFound,
            rateLimited: error.isRateLimited,
            serverCode: error.serverCode,
            networkError: error.networkError,
            decoding: error.isDecoding,
            fallback: error.localizedDescription
        )
    }

    private static func map(_ error: CloudflareAPIError) -> UserFacingError {
        switch error {
        case .api(let message) where message.contains("token format"):
            return UserFacingError(
                title: "That doesn't look like a Cloudflare token",
                explanation: "Cloudflare couldn't read what was pasted.",
                nextStep: "Paste only the token itself (about 40 letters, numbers, - and _), without “Bearer”, quotes, or the rest of a command.",
                action: .replaceToken
            )
        case .api(let message):
            return UserFacingError(
                title: "Cloudflare couldn't complete the request",
                explanation: message,
                nextStep: "Check the token permissions, then try again.",
                action: .retry
            )
        case .forbidden:
            return UserFacingError(
                title: "This token is missing a permission",
                explanation: "Cloudflare accepted the token but won't let Toast read your projects.",
                nextStep: "In Cloudflare, add Account Settings → Read plus Cloudflare Pages → Read and/or Workers Scripts → Read.",
                action: .replaceToken
            )
        default:
            return common(
                service: "Cloudflare",
                unauthorized: error.isUnauthorized,
                forbidden: false,
                notFound: error.isNotFound,
                rateLimited: error.isRateLimited,
                serverCode: error.serverCode,
                networkError: error.networkError,
                decoding: error.isDecoding,
                fallback: error.localizedDescription
            )
        }
    }

    private static func map(_ error: KeychainError) -> UserFacingError {
        UserFacingError(
            title: "Toast couldn't use your Keychain",
            explanation: "macOS didn't let Toast save or read the token.",
            nextStep: "Unlock your Keychain, then replace the token in Settings.",
            action: .replaceToken
        )
    }

    private static func common(
        service: String,
        unauthorized: Bool,
        forbidden: Bool,
        notFound: Bool,
        rateLimited: Bool,
        serverCode: Int?,
        networkError: Error?,
        decoding: Bool,
        fallback: String
    ) -> UserFacingError {
        if unauthorized {
            return UserFacingError(
                title: "\(service) didn't accept this token",
                explanation: "The token may be wrong, expired or revoked.",
                nextStep: "Create a new token and replace it in Settings.",
                action: .replaceToken
            )
        }
        if forbidden {
            return UserFacingError(
                title: "This token can't read that",
                explanation: "\(service) refused the request because of the token's permissions or scope.",
                nextStep: "Check that the token covers the team and projects you picked.",
                action: .openSettings
            )
        }
        if notFound {
            return UserFacingError(
                title: "\(service) couldn't find it",
                explanation: "The project or account may have been renamed or deleted.",
                nextStep: "Choose your projects again in Settings.",
                action: .openSettings
            )
        }
        if rateLimited {
            return UserFacingError(
                title: "\(service) asked Toast to slow down",
                explanation: "Too many requests were made in a short time.",
                nextStep: "Toast will try again automatically in a minute.",
                action: nil
            )
        }
        if let serverCode {
            return UserFacingError(
                title: "\(service) is having trouble",
                explanation: "It returned a server error (\(serverCode)). This is on their side.",
                nextStep: "Toast will keep trying. Check \(service)'s status page if it continues.",
                action: .retry
            )
        }
        if let networkError {
            return network(networkError, service: service)
        }
        if decoding {
            return UserFacingError(
                title: "\(service) sent something unexpected",
                explanation: "Toast couldn't understand the response.",
                nextStep: "Update Toast to the latest version, or try again.",
                action: .retry
            )
        }
        return UserFacingError(title: "Something went wrong", explanation: fallback, nextStep: "Try again.", action: .retry)
    }

    private static func network(_ error: Error, service: String?) -> UserFacingError {
        UserFacingError(
            title: service.map { "Can't reach \($0)" } ?? "Can't connect",
            explanation: "Toast couldn't get a response. You may be offline.",
            nextStep: "Check your internet connection. Toast will retry automatically.",
            action: .retry
        )
    }
}

private extension VercelAPIError {
    var isUnauthorized: Bool { if case .unauthorized = self { true } else { false } }
    var isForbidden: Bool { if case .forbidden = self { true } else { false } }
    var isNotFound: Bool { if case .notFound = self { true } else { false } }
    var isRateLimited: Bool { if case .rateLimited = self { true } else { false } }
    var isDecoding: Bool { if case .decodingFailed = self { true } else { false } }
    var serverCode: Int? { if case .serverError(let code) = self { code } else { nil } }
    var networkError: Error? { if case .network(let error) = self { error } else { nil } }
}

private extension CloudflareAPIError {
    var isUnauthorized: Bool { if case .unauthorized = self { true } else { false } }
    var isNotFound: Bool { if case .notFound = self { true } else { false } }
    var isRateLimited: Bool { if case .rateLimited = self { true } else { false } }
    var isDecoding: Bool { if case .decodingFailed = self { true } else { false } }
    var serverCode: Int? { if case .serverError(let code) = self { code } else { nil } }
    var networkError: Error? { if case .network(let error) = self { error } else { nil } }
}
