import AppKit
import SwiftUI

enum MenuBarIcon {
    static func image(for status: AggregateStatus) -> NSImage {
        let symbolName = status.menuBarSymbol
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Toast")
        let image = base?.withSymbolConfiguration(config) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }

    static func tintedImage(for status: AggregateStatus) -> NSImage {
        let image = image(for: status)
        switch status {
        case .ready:
            return colored(image, .systemGreen)
        case .building:
            return colored(image, .systemBlue)
        case .error:
            return colored(image, .systemRed)
        case .disconnected:
            return colored(image, .systemOrange)
        case .idle:
            return image
        }
    }

    private static func colored(_ template: NSImage, _ color: NSColor) -> NSImage {
        let size = template.size
        let rendered = NSImage(size: size, flipped: false) { rect in
            template.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        rendered.isTemplate = false
        return rendered
    }
}

struct MenuBarLabel: View {
    @Environment(DeploymentStore.self) private var store
    @Environment(SparkleUpdater.self) private var updater

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.tintedImage(for: store.aggregateStatus))
            if store.showStatusText, let label = store.aggregateStatus.shortLabel {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
        }
        .task {
            updater.startIfNeeded()
            store.bootstrap()
        }
    }
}
