import Foundation

/// Cloudflare projects are Pages sites or Workers. The kind is stored in the project ID
/// (`pages:<name>` / `worker:<name>`) so both kinds can share one watched-project list.
enum CloudflareProjectKind: String, Sendable {
    case pages
    case worker

    init?(projectID: String) {
        guard let prefix = projectID.split(separator: ":", maxSplits: 1).first,
              let kind = CloudflareProjectKind(rawValue: String(prefix)),
              projectID.contains(":")
        else { return nil }
        self = kind
    }

    static func id(_ kind: CloudflareProjectKind, name: String) -> String {
        "\(kind.rawValue):\(name)"
    }

    static func name(fromProjectID projectID: String) -> String {
        guard let index = projectID.firstIndex(of: ":"), CloudflareProjectKind(projectID: projectID) != nil else {
            return projectID
        }
        return String(projectID[projectID.index(after: index)...])
    }
}
