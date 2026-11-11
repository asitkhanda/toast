import AppKit
import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 1
    case service = 2
    case connect = 3
    case projects = 4
    case preferences = 5

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .service: "Choose a service"
        case .connect: "Connect"
        case .projects: "Choose projects"
        case .preferences: "Preferences"
        }
    }
}

struct OnboardingView: View {
    @Environment(DeploymentStore.self) private var store

    @State private var step: OnboardingStep
    @State private var provider: DeploymentProvider
    @State private var token = ""
    @State private var showToken = false
    @State private var isConnecting = false
    @State private var isStarting = false
    @State private var failure: UserFacingError?
    @State private var scopeWarning: String?
    @State private var selectedProjectIDs: Set<String> = []
    @State private var search = ""
    @State private var launchAtLogin = true
    @State private var runInBackground = true
    @State private var relaunchOnCrash = true
    @State private var notifyOnCompletion = true

    init(initialStep: Int = 1, initialProvider: DeploymentProvider = .vercel) {
        _step = State(initialValue: OnboardingStep(rawValue: initialStep) ?? .welcome)
        _provider = State(initialValue: initialProvider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                stepContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 460)
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 440)
        .onAppear {
            guard step == .welcome else { return }
            if let connected = DeploymentProvider.allCases.first(where: {
                KeychainStore.hasToken(for: $0) && store.isConnected(to: $0)
            }) {
                provider = connected
                step = .projects
            }
        }
        .onChange(of: store.isConnected) { _, connected in
            if connected, provider == .vercel, step == .connect { advance(to: .projects) }
        }
        .onChange(of: store.isCloudflareConnected) { _, connected in
            if connected, provider == .cloudflare, step == .connect { advance(to: .projects) }
        }
        .onChange(of: provider) { _, _ in
            token = ""
            failure = nil
            scopeWarning = nil
            selectedProjectIDs = []
        }
        .onDisappear {
            token = ""
            showToken = false
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set up Toast")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            StepIndicator(current: step.rawValue, total: OnboardingStep.allCases.count, title: step.title)
            Text(stepDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var stepDescription: String {
        switch step {
        case .welcome:
            "Toast sits in your menu bar and shows whether your latest deployments are building, live or failed."
        case .service:
            "Pick where your projects are deployed. You can add the other service later in Settings."
        case .connect:
            "Toast needs a token to read your \(provider.displayName) deployments. It only reads status. It can't change or delete anything."
        case .projects:
            "Choose the projects to watch. You can change this any time in Settings."
        case .preferences:
            "These keep Toast useful without getting in your way. You can change them later."
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .service: serviceStep
        case .connect: connectStep
        case .projects: projectsStep
        case .preferences: preferencesStep
        }
    }

    // MARK: Step 1: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureRow(
                symbol: "menubar.arrow.up.rectangle",
                title: "Status at a glance",
                detail: "The menu bar icon changes shape and color when something builds, fails or goes live."
            )
            featureRow(
                symbol: "bell.badge",
                title: "Know when a deploy finishes",
                detail: "Get a notification the moment a build succeeds or fails."
            )
            featureRow(
                symbol: "lock.shield",
                title: "Private by design",
                detail: "Your token stays in this Mac's Keychain. Toast never sends it, or your project names, to us."
            )
        }
    }

    private func featureRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Step 2: Service

    private var serviceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(DeploymentProvider.allCases) { option in
                Button {
                    provider = option
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.symbolName)
                            .font(.title2)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName).font(.headline)
                            Text(option.summaryLine)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: provider == option ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(provider == option ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .fill(provider == option ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .strokeBorder(Color.accentColor, lineWidth: provider == option ? 2 : 0)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(provider == option ? [.isSelected] : [])
                .accessibilityLabel("\(option.displayName). \(option.summaryLine)")
            }
        }
    }

    // MARK: Step 3: Connect

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How to get your \(provider.displayName) token")
                    .font(.headline)
                ForEach(Array(provider.tokenSteps.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .frame(width: 20, alignment: .trailing)
                        Text(text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button {
                    NSWorkspace.shared.open(provider.tokensURL)
                } label: {
                    Label(provider.tokenPageButtonTitle, systemImage: "arrow.up.forward.square")
                }
                .controlSize(.regular)
                .padding(.top, 2)
            }

            if !provider.requiredPermissions.isEmpty {
                permissionsList
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste your token")
                    .font(.headline)
                HStack {
                    Group {
                        if showToken {
                            TextField("Token", text: $token, prompt: Text(provider.tokenPlaceholder))
                        } else {
                            SecureField("Token", text: $token, prompt: Text(provider.tokenPlaceholder))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await connect() } }
                    .accessibilityLabel("\(provider.displayName) token")

                    Button(showToken ? "Hide" : "Show") { showToken.toggle() }
                        .accessibilityLabel(showToken ? "Hide token" : "Show token")
                }
                if let hint = tokenHint {
                    Label(hint, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Label(provider.privacyReassurance, systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            feedback
        }
    }

    private var permissionsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions to add")
                .font(.headline)
            ForEach(provider.requiredPermissions) { permission in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(permission.label)
                                .font(.callout.weight(.semibold))
                            if permission.isOptional {
                                Text("Optional")
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        Text(permission.reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(permission.label, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy “\(permission.label)”")
                    .accessibilityLabel("Copy permission name: \(permission.label)")
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var tokenHint: String? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if provider == .cloudflare {
            if CloudflareAPIClient.sanitizedToken(token) != cleaned {
                return "Toast will ignore the extra “Bearer” or quotes around your token."
            }
            if cleaned.count < 30 {
                return "Cloudflare tokens are about 40 characters. This one looks short. Did the whole token get copied?"
            }
        }
        return nil
    }

    // MARK: Step 4: Projects

    private var filteredProjects: [Project] {
        let all = store.projects(for: provider)
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var projectsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let name = store.connectedAccountName(for: provider) {
                InlineNotice(kind: .success, title: "Connected to \(name)")
            }
            if let warning = store.scopeWarning(for: provider) {
                InlineNotice(kind: .warning, title: "This token can do more than Toast needs", message: warning)
            }

            if store.accounts(for: provider).count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(provider.accountNoun).font(.headline)
                    Picker(provider.accountNoun, selection: Binding(
                        get: { store.selectedAccountId(for: provider) ?? "" },
                        set: { newValue in
                            store.selectAccount(newValue.isEmpty ? nil : newValue, for: provider)
                            selectedProjectIDs = []
                            Task { await store.reloadProjects(for: provider) }
                        }
                    )) {
                        ForEach(store.accounts(for: provider)) { team in
                            Text(team.displayName).tag(team.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Projects").font(.headline)
                    Spacer()
                    if store.isLoading { ProgressView().controlSize(.small) }
                }

                if store.projects(for: provider).isEmpty {
                    InlineNotice(
                        kind: .info,
                        title: "No projects found",
                        message: store.projectNotice(for: provider)
                            ?? "This \(provider.accountNoun.lowercased()) has no projects Toast can read. Check the token's permissions, or pick a different \(provider.accountNoun.lowercased())."
                    )
                } else {
                    HStack {
                        TextField("Search projects", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search projects")
                        Button("Select all") {
                            selectedProjectIDs.formUnion(filteredProjects.map(\.id))
                        }
                        Button("None") {
                            selectedProjectIDs.subtract(filteredProjects.map(\.id))
                        }
                    }
                    .controlSize(.small)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredProjects) { project in
                                ProjectToggleRow(
                                    project: project,
                                    isSelected: selectedProjectIDs.contains(project.id)
                                ) { isSelected in
                                    if isSelected {
                                        selectedProjectIDs.insert(project.id)
                                    } else {
                                        selectedProjectIDs.remove(project.id)
                                    }
                                }
                            }
                            if filteredProjects.isEmpty {
                                Text("No projects match “\(search)”.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .padding(8)
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 170)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                    Text(selectedProjectIDs.isEmpty
                        ? "Select at least one project to continue."
                        : "\(selectedProjectIDs.count) selected")
                        .font(.footnote)
                        .foregroundStyle(selectedProjectIDs.isEmpty ? Color.primary : Color.secondary)
                        .fontWeight(selectedProjectIDs.isEmpty ? .semibold : .regular)
                }
            }

            feedback
        }
    }

    // MARK: Step 5: Preferences

    private var preferencesStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            preferenceToggle(
                "Notify me when a deploy finishes",
                detail: "A notification appears when a build succeeds or fails.",
                isOn: $notifyOnCompletion
            )
            preferenceToggle(
                "Open Toast when I log in",
                detail: "Starts Toast automatically so it's always in your menu bar.",
                isOn: $launchAtLogin
            )
            preferenceToggle(
                "Keep Toast out of the Dock",
                detail: "Toast lives only in the menu bar.",
                isOn: $runInBackground
            )
            preferenceToggle(
                "Restart Toast if it quits unexpectedly",
                detail: "A small helper brings it back so you don't miss a failed deploy.",
                isOn: $relaunchOnCrash
            )

            if launchAtLogin && BackgroundBehavior.launchAtLoginRequiresApproval {
                InlineNotice(
                    kind: .info,
                    title: "macOS may ask for approval",
                    message: "If asked, allow Toast in System Settings → General → Login Items."
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Help improve Toast").font(.headline)
                Text("Toast sends anonymous usage data and crash reports. It never includes your tokens, project names or personal information. Turn this off any time in Settings → Privacy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Read the privacy policy", destination: URL(string: "https://toast.asit.space/privacy")!)
                    .font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.cardRadius))

            feedback
        }
    }

    private func preferenceToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: Feedback

    @ViewBuilder
    private var feedback: some View {
        if let failure {
            InlineNotice(kind: .error, title: failure.title, message: failure.message)
        } else if let scopeWarning, step == .connect {
            InlineNotice(kind: .warning, title: "Heads up", message: scopeWarning)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { goBack() }
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            switch step {
            case .welcome:
                Button("Get started") { advance(to: .service) }
                    .keyboardShortcut(.defaultAction)
                    .toastButtonStyle(prominent: true)
                    .controlSize(.large)
            case .service:
                Button("Continue") { advance(to: .connect) }
                    .keyboardShortcut(.defaultAction)
                    .toastButtonStyle(prominent: true)
                    .controlSize(.large)
            case .connect:
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        }
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .toastButtonStyle(prominent: true)
                .controlSize(.large)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
            case .projects:
                Button("Continue") { advance(to: .preferences) }
                    .keyboardShortcut(.defaultAction)
                    .toastButtonStyle(prominent: true)
                    .controlSize(.large)
                    .disabled(selectedProjectIDs.isEmpty)
            case .preferences:
                Button {
                    Task { await finishOnboarding() }
                } label: {
                    if isStarting || store.isFinishingOnboarding {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Starting…")
                        }
                    } else {
                        Text("Finish setup")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .toastButtonStyle(prominent: true)
                .controlSize(.large)
                .disabled(isStarting || store.isFinishingOnboarding)
            }
        }
    }

    // MARK: Actions

    private func advance(to next: OnboardingStep) {
        failure = nil
        withAnimation(.easeInOut(duration: 0.2)) { step = next }
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        advance(to: previous)
    }

    private func connect() async {
        isConnecting = true
        failure = nil
        scopeWarning = nil
        defer { isConnecting = false }

        do {
            try await store.connect(token: token, provider: provider)
            token = ""
            showToken = false
            await NotificationManager.shared.requestAuthorization()
            scopeWarning = store.scopeWarning(for: provider)
        } catch {
            AnalyticsService.shared.captureTokenFailed(error)
            failure = UserFacingError.from(error)
        }
    }

    private func finishOnboarding() async {
        guard let accountId = store.selectedAccountId(for: provider) else {
            failure = UserFacingError(
                title: "Choose a \(provider.accountNoun.lowercased())",
                explanation: "Go back and select a \(provider.accountNoun.lowercased()) first.",
                nextStep: nil,
                action: nil
            )
            return
        }

        let selected = store.projects(for: provider)
            .filter { selectedProjectIDs.contains($0.id) }
            .map { WatchedProject(projectId: $0.id, projectName: $0.name, teamId: accountId, provider: provider) }

        guard !selected.isEmpty else {
            failure = UserFacingError.from(OnboardingError.noProjectsSelected)
            return
        }

        isStarting = true
        failure = nil
        defer { isStarting = false }

        store.notificationsEnabled = notifyOnCompletion
        await store.completeOnboarding(
            watching: selected,
            background: BackgroundPreferences(
                launchAtLogin: launchAtLogin,
                runInBackground: runInBackground,
                relaunchOnCrash: relaunchOnCrash
            )
        )
    }
}

/// Shown once after setup so people know where Toast lives and what happens next.
struct SetupCompleteView: View {
    @Environment(DeploymentStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("You're all set")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                tip("menubar.arrow.up.rectangle", "Toast lives in your menu bar, at the top right of your screen.")
                tip("hand.tap", "Click the icon any time to see your deployments.")
                tip("bell", "You'll get a notification when a deploy finishes or fails.")
                tip("gearshape", "Add projects or another service in Settings.")
            }
            Button("Show my deployments") {
                store.showSetupComplete = false
            }
            .keyboardShortcut(.defaultAction)
            .toastButtonStyle(prominent: true)
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 400)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
