import Foundation

/// Plain-language summary of all watched projects, shared by the popover header and VoiceOver.
struct StatusSummary: Equatable {
    let headline: String
    let spoken: String

    static func make(states: [DeploymentState], isDisconnected: Bool) -> StatusSummary {
        if isDisconnected {
            return StatusSummary(
                headline: "Not connected",
                spoken: "Toast: not connected. Open Toast to reconnect."
            )
        }
        guard !states.isEmpty else {
            return StatusSummary(headline: "No projects yet", spoken: "Toast: no projects are being watched.")
        }

        let failed = states.filter { $0 == .error || $0 == .blocked }.count
        let canceled = states.filter { $0 == .canceled }.count
        let inProgress = states.filter(\.isInProgress).count
        let ready = states.filter { $0 == .ready }.count
        let total = states.count

        if failed == 0, canceled == 0, inProgress == 0, ready == total {
            let headline = total == 1 ? "Your project is live" : "All \(total) projects are live"
            return StatusSummary(headline: headline, spoken: "Toast: \(headline.lowercased()).")
        }

        var parts: [String] = []
        if failed > 0 { parts.append("\(failed) failed") }
        if canceled > 0 { parts.append("\(canceled) canceled") }
        if inProgress > 0 { parts.append("\(inProgress) building") }
        if ready > 0 { parts.append("\(ready) live") }
        let headline = parts.joined(separator: ", ")
        return StatusSummary(headline: headline.prefix(1).uppercased() + headline.dropFirst(), spoken: "Toast: \(headline).")
    }
}
