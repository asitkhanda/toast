import Foundation

public final class RuntimeState: @unchecked Sendable {
    public static let shared = RuntimeState()

    private let fileURL: URL

    private enum Keys {
        static let userInitiatedQuit = "userInitiatedQuit"
        static let relaunchOnCrashEnabled = "relaunchOnCrashEnabled"
        static let pendingCrashReport = "pendingCrashReport"
        static let crashPromptSuppressed = "crashPromptSuppressed"
    }

    public init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("com.toast.app", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("runtime.plist")
    }

    public var userInitiatedQuit: Bool {
        get { bool(forKey: Keys.userInitiatedQuit) ?? false }
        set { setBool(newValue, forKey: Keys.userInitiatedQuit) }
    }

    public var relaunchOnCrashEnabled: Bool {
        get { bool(forKey: Keys.relaunchOnCrashEnabled) ?? true }
        set { setBool(newValue, forKey: Keys.relaunchOnCrashEnabled) }
    }

    public var pendingCrashReport: Bool {
        get { bool(forKey: Keys.pendingCrashReport) ?? false }
        set { setBool(newValue, forKey: Keys.pendingCrashReport) }
    }

    public var crashPromptSuppressed: Bool {
        get { bool(forKey: Keys.crashPromptSuppressed) ?? false }
        set { setBool(newValue, forKey: Keys.crashPromptSuppressed) }
    }

    public func markAppRunning() {
        userInitiatedQuit = false
    }

    public func markUserQuit() {
        userInitiatedQuit = true
    }

    private func bool(forKey key: String) -> Bool? {
        dictionary[key] as? Bool
    }

    private func setBool(_ value: Bool, forKey key: String) {
        var dict = dictionary
        dict[key] = value
        write(dict)
    }

    private var dictionary: [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    private func write(_ dictionary: [String: Any]) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
