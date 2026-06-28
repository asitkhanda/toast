import SwiftUI

enum VercelTokenHelp {
    static let tokensURL = URL(string: "https://vercel.com/account/settings/tokens")!
}

struct TokenHelpLink: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link("How to get your token?", destination: VercelTokenHelp.tokensURL)
                .font(.caption)
            Text("Create a token with read-only access, scoped only to the teams and projects Toast should monitor.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Avoid full-account tokens. Toast only needs to read teams, projects, and deployments.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
