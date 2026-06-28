import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case connect = 1
    case selectProjects = 2

    var title: String {
        switch self {
        case .connect: "Connect"
        case .selectProjects: "Choose projects"
        }
    }
}

struct OnboardingView: View {
    @Environment(DeploymentStore.self) private var store

    @State private var step: OnboardingStep = .connect
    @State private var token = ""
    @State private var showToken = false
    @State private var isConnecting = false
    @State private var isStarting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var selectedProjectIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            stepContent
                .padding(24)
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 420)
        .onAppear {
            if let existing = KeychainStore.loadToken() {
                token = existing
            }
            if store.isConnected {
                step = .selectProjects
            }
        }
        .onChange(of: store.isConnected) { _, connected in
            if connected {
                withAnimation(.easeInOut(duration: 0.2)) {
                    step = .selectProjects
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up Toast")
                .font(.title3.weight(.semibold))

            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { onboardingStep in
                    stepBadge(onboardingStep)
                    if onboardingStep != OnboardingStep.allCases.last {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Text(stepDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }

    private var stepDescription: String {
        switch step {
        case .connect:
            "Link your Vercel account so the app can read deployment status."
        case .selectProjects:
            "Pick which projects to monitor. The menu bar icon updates automatically — every 5 seconds while building, otherwise every minute."
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .connect:
            connectStep
        case .selectProjects:
            selectProjectsStep
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Personal Access Token")
                    .font(.headline)

                HStack {
                    Group {
                        if showToken {
                            TextField("vercel_...", text: $token)
                        } else {
                            SecureField("vercel_...", text: $token)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button(showToken ? "Hide" : "Show") {
                        showToken.toggle()
                    }
                }

                TokenHelpLink()
            }

            feedbackBanner
        }
    }

    private var selectProjectsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let teamName = store.connectedTeamName {
                Label("Connected to \(teamName)", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Team")
                    .font(.headline)

                Picker("Team", selection: Binding(
                    get: { store.selectedTeamId ?? "" },
                    set: { newValue in
                        store.selectedTeamId = newValue.isEmpty ? nil : newValue
                        selectedProjectIDs = []
                        Task { await store.reloadProjects() }
                    }
                )) {
                    ForEach(store.teams) { team in
                        Text(team.displayName).tag(team.id)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Projects")
                        .font(.headline)
                    Spacer()
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }

                if store.projects.isEmpty {
                    ContentUnavailableView {
                        Label("No projects", systemImage: "folder")
                    } description: {
                        Text("No projects found for this team.")
                    }
                    .frame(height: 140)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(store.projects) { project in
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
                        }
                    }
                    .frame(height: 140)
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }

                Text(selectedProjectIDs.isEmpty
                    ? "Select at least one project."
                    : "\(selectedProjectIDs.count) project\(selectedProjectIDs.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(selectedProjectIDs.isEmpty ? .orange : .secondary)
            }

            feedbackBanner
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else if let successMessage {
            Label(successMessage, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var footer: some View {
        HStack {
            if step == .selectProjects {
                Button("Back") {
                    withAnimation { step = .connect }
                    errorMessage = nil
                    successMessage = nil
                }
            }

            Spacer()

            switch step {
            case .connect:
                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                            .frame(width: 60)
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)

            case .selectProjects:
                Button {
                    Task { await finishOnboarding() }
                } label: {
                    if isStarting || store.isFinishingOnboarding {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Starting…")
                        }
                    } else {
                        Text("Start watching")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedProjectIDs.isEmpty || isStarting || store.isFinishingOnboarding)
            }
        }
    }

    private func stepBadge(_ onboardingStep: OnboardingStep) -> some View {
        let isActive = step == onboardingStep
        let isComplete = onboardingStep.rawValue < step.rawValue
            || (onboardingStep == .connect && store.isConnected)

        return HStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : (isComplete ? Color.green : Color.secondary.opacity(0.2)))
                    .frame(width: 20, height: 20)
                if isComplete && !isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(onboardingStep.rawValue)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            Text(onboardingStep.title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        successMessage = nil
        defer { isConnecting = false }

        do {
            try await store.connect(token: token)
            await NotificationManager.shared.requestAuthorization()
            successMessage = "Connected successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishOnboarding() async {
        guard let teamId = store.selectedTeamId else {
            errorMessage = "Select a team first."
            return
        }

        let selected = store.projects
            .filter { selectedProjectIDs.contains($0.id) }
            .map { WatchedProject(projectId: $0.id, projectName: $0.name, teamId: teamId) }

        guard !selected.isEmpty else {
            errorMessage = OnboardingError.noProjectsSelected.localizedDescription
            return
        }

        isStarting = true
        errorMessage = nil
        successMessage = nil
        defer { isStarting = false }

        await store.completeOnboarding(watching: selected)
    }
}