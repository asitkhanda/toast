import SwiftUI

enum VercelTokenHelp {
    static let tokensURL = URL(string: "https://vercel.com/account/settings/tokens")!
}

struct TokenHelpLink: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Link("How to get your token", destination: VercelTokenHelp.tokensURL)
            Text("Create a token with read access to your teams and projects.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
