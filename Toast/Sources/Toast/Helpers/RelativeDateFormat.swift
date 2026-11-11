import Foundation

enum RelativeDateFormat {
    /// "Deployed 3 hours ago" — spelled out so it reads well on screen and in VoiceOver.
    static func label(for date: Date, prefix: String, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "\(prefix) just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "\(prefix) \(formatter.localizedString(for: date, relativeTo: now))"
    }
}
