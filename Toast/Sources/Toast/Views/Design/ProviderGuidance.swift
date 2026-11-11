import Foundation

/// Step-by-step help for creating a token, shown during setup and in Settings.
extension DeploymentProvider {
    struct Permission: Identifiable {
        let label: String
        let reason: String
        let isOptional: Bool
        var id: String { label }
    }

    var tokenSteps: [String] {
        switch self {
        case .vercel:
            [
                "Open your Vercel tokens page.",
                "Choose Create Token and name it “Toast”.",
                "Under Scope, pick only the team you want Toast to watch.",
                "Set an expiry you're comfortable with, then create the token.",
                "Copy the token and paste it below.",
            ]
        case .cloudflare:
            [
                "Open your Cloudflare API tokens page.",
                "Choose Create Token, then Create Custom Token.",
                "Add the permissions listed below (set each to Read).",
                "Under Account Resources, choose your account.",
                "Create the token, copy it, and paste it below.",
            ]
        }
    }

    var requiredPermissions: [Permission] {
        switch self {
        case .vercel:
            []
        case .cloudflare:
            [
                Permission(label: "Account → Account Settings → Read", reason: "Lets Toast find your account.", isOptional: false),
                Permission(label: "Account → Cloudflare Pages → Read", reason: "Needed to watch Pages projects.", isOptional: false),
                Permission(label: "Account → Workers Scripts → Read", reason: "Needed to watch Workers.", isOptional: false),
                Permission(label: "Account → Workers Builds Configuration → Read", reason: "Optional. Shows real build progress for Workers.", isOptional: true),
            ]
        }
    }

    var tokenPageButtonTitle: String {
        "Open \(displayName) token page"
    }

    var privacyReassurance: String {
        "Your token is saved in this Mac's Keychain and only ever sent to \(displayName)."
    }

    var summaryLine: String {
        switch self {
        case .vercel: "Deployments from Vercel projects."
        case .cloudflare: "Cloudflare Pages sites and Workers."
        }
    }
}
