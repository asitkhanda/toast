import Foundation

enum RelativeDateFormat {
    static func label(for date: Date, prefix: String) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "\(prefix) just now"
        }
        if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(prefix) \(minutes)m ago"
        }
        if interval < 86400 {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return "\(prefix) \(formatter.string(from: date))"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(prefix) \(formatter.string(from: date))"
    }
}
