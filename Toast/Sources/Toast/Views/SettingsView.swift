import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(DeploymentStore.self) private var store
    @Environment(SparkleUpdater.self) private var updater

    @State private var token = ""
    @State private var showToken = false
    @State private var selectedProjectIDs: Set<String> = []
    @State private var statusMessage: String?
    @State private var isSavingToken = false
    @State private var isLoadingSession = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Account") {
                HStack {
                    if showToken {
                        TextField("Personal Access Token", text: $token, prompt: Text("vercel_..."))
                    } else {
                        SecureField("Personal Access Token", text: $token, prompt: Text("vercel_..."))
                    }
                    Button(showToken ? "Hide" : "Show") { showToken.toggle() }
                }

                TokenHelpLink()

                HStack {
                    Button("Save token") {
                        Task { await saveToken() }
                    }
                    .disabled(isSavingToken)

                    Button("Disconnect", role: .destructive) {
                        store.disconnect()
                        token = ""
                        selectedProjectIDs = []
                        statusMessage = "Disconnected."
                    }
                }

                if isSavingToken || isLoadingSession {
                    ProgressView(isLoadingSession ? "Loading account…" : "Validating token…")
                        .controlSize(.small)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Team") {
                if store.teams.isEmpty {
                    Text("Connect a token to load teams.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Team", selection: $store.selectedTeamId) {
                        Text("Select a team").tag(Optional<String>.none)
                        ForEach(store.teams) { team in
                            Text(team.displayName).tag(Optional(team.id))
                        }
                    }
                }

                Button("Reload projects") {
                    Task { await store.reloadProjects() }
                }
                .disabled(store.selectedTeamId == nil || isLoadingSession)
            }

            Section("Watched projects") {
                if store.projects.isEmpty {
                    Text("No projects loaded. Save a token and pick a team first.")
                        .foregroundStyle(.secondary)
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
                    .frame(minHeight: 140)
                }

                Button("Save watched projects") {
                    saveWatchedProjects()
                }
                .disabled(selectedProjectIDs.isEmpty || store.selectedTeamId == nil)
            }

            Section("Menu bar") {
                Toggle("Show status text", isOn: $store.showStatusText)
                Toggle("Notify on completion", isOn: $store.notificationsEnabled)
            }

            Section("Updates") {
                LabeledContent("Version") {
                    Text("\(updater.currentVersion) (\(updater.currentBuild))")
                        .foregroundStyle(.secondary)
                }
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
            }

            Section {
                Text("The menu bar icon polls Vercel every 5 seconds while a deployment is building, otherwise every 60 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 580)
        .task {
            await loadSettingsSession()
        }
        .onChange(of: store.selectedTeamId) { _, _ in
            selectedProjectIDs = Set(store.watchedProjects.map(\.projectId))
            Task { await store.reloadProjects() }
        }
        .onDisappear {
            AppActivation.restoreMenuBarOnlyPolicy()
        }
    }

    private func loadSettingsSession() async {
        token = KeychainStore.loadToken() ?? ""
        selectedProjectIDs = Set(store.watchedProjects.map(\.projectId))

        isLoadingSession = true
        defer { isLoadingSession = false }

        await store.restoreSessionIfNeeded()
        selectedProjectIDs = Set(store.watchedProjects.map(\.projectId))
    }

    private func saveToken() async {
        isSavingToken = true
        statusMessage = nil
        defer { isSavingToken = false }

        do {
            try await store.connect(token: token)
            selectedProjectIDs = Set(store.watchedProjects.map(\.projectId))
            statusMessage = "Token saved. Connected to \(store.connectedTeamName ?? "Vercel")."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveWatchedProjects() {
        guard let teamId = store.selectedTeamId else {
            statusMessage = "Select a team first."
            return
        }
        let selected = store.projects
            .filter { selectedProjectIDs.contains($0.id) }
            .map { WatchedProject(projectId: $0.id, projectName: $0.name, teamId: teamId) }
        store.updateWatchedProjects(selected)
        statusMessage = "Watching \(selected.count) project\(selected.count == 1 ? "" : "s")."
    }
}
