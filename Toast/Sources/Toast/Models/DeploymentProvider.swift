import Foundation

enum DeploymentProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case vercel
    case cloudflare

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vercel: "Vercel"
        case .cloudflare: "Cloudflare"
        }
    }

    var accountNoun: String {
        switch self {
        case .vercel: "Team"
        case .cloudflare: "Account"
        }
    }

    var tokenPlaceholder: String {
        switch self {
        case .vercel: "vercel_..."
        case .cloudflare: "Cloudflare API token"
        }
    }

    var keychainAccount: String {
        switch self {
        case .vercel: "vercel-pat"
        case .cloudflare: "cloudflare-api-token"
        }
    }

    var hardenedStorageKey: String {
        switch self {
        case .vercel: "keychainTokenHardenedV2"
        case .cloudflare: "keychainCloudflareTokenHardenedV1"
        }
    }

    var tokensURL: URL {
        switch self {
        case .vercel: URL(string: "https://vercel.com/account/settings/tokens")!
        case .cloudflare: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!
        }
    }

    var tokenAdvice: String {
        switch self {
        case .vercel:
            "Create a token with read-only access, scoped only to the teams and projects Toast should monitor."
        case .cloudflare:
            "Create a custom API token with only Account → Cloudflare Pages → Read, Account → Workers Scripts → Read, and Account → Account Settings → Read. Add Account → Workers Builds Configuration → Read to see real Workers build progress. Limit it to the accounts Toast should monitor."
        }
    }

    var symbolName: String {
        switch self {
        case .vercel: "triangle.fill"
        case .cloudflare: "cloud.fill"
        }
    }
}
