import SwiftUI

/// Shared sizes and status styling. Colours are system semantic colours so they adapt to
/// light, dark and Increase Contrast. Text stays `.primary`; colour only tints icons and backgrounds.
enum Theme {
    static let spacing: CGFloat = 12
    static let cardRadius: CGFloat = 14
    static let popoverWidth: CGFloat = 400
    static let minimumControlHeight: CGFloat = 28
}

extension View {
    /// Liquid Glass buttons on macOS 26 and later, standard bordered buttons before that.
    @ViewBuilder
    func toastButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// A glass surface on macOS 26 and later, a regular material before that.
    @ViewBuilder
    func toastSurface(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension DeploymentState {
    var symbolName: String {
        switch self {
        case .ready: "checkmark.circle.fill"
        case .queued: "clock.fill"
        case .initializing, .building: "arrow.triangle.2.circlepath"
        case .error: "xmark.octagon.fill"
        case .canceled: "slash.circle.fill"
        case .blocked: "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready: .green
        case .queued, .initializing, .building: .blue
        case .error, .blocked: .red
        case .canceled: .gray
        }
    }

    /// Plain-language description used for VoiceOver and the summary line.
    var spokenName: String {
        switch self {
        case .ready: "live"
        case .queued: "waiting to build"
        case .initializing: "starting"
        case .building: "building"
        case .error: "failed"
        case .canceled: "canceled"
        case .blocked: "blocked"
        }
    }
}

/// A status badge that never relies on colour alone: icon shape plus a word.
struct StatusPill: View {
    let state: DeploymentState

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
                .imageScale(.small)
            Text(state.displayName)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(state.tint.opacity(contrast == .increased ? 0.3 : 0.16), in: Capsule())
        .overlay {
            if contrast == .increased {
                Capsule().strokeBorder(state.tint, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(state.displayName)")
    }
}

/// An inline message with an optional action button. Used for info, warnings and errors.
struct InlineNotice: View {
    enum Kind {
        case info, warning, error, success

        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            case .success: "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .info: .blue
            case .warning: .orange
            case .error: .red
            case .success: .green
            }
        }

        var spokenPrefix: String {
            switch self {
            case .info: "Note"
            case .warning: "Warning"
            case .error: "Problem"
            case .success: "Success"
            }
        }
    }

    @Environment(\.colorSchemeContrast) private var contrast

    let kind: Kind
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
                .font(.body)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.tint.opacity(contrast == .increased ? 0.2 : 0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(kind.tint, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(kind.spokenPrefix): \(title)")
    }
}

/// "Step 2 of 5" with a progress bar, announced as one element.
struct StepIndicator: View {
    let current: Int
    let total: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Step \(current) of \(total)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            ProgressView(value: Double(current), total: Double(total))
                .progressViewStyle(.linear)
                .tint(.accentColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of \(total): \(title)")
    }
}
