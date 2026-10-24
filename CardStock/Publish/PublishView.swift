import SwiftUI

/// Everything about getting the site online: current status, the main
/// Publish (or Build) button, how it works, and GitHub setup.
struct PublishView: View {
    @Environment(AppModel.self) private var model
    let site: Site
    @State private var message = ""
    @State private var showSchedule = false

    private var link: ProjectSettings.GitHubLink? { model.project.github }

    var body: some View {
        Form {
            if link != nil, let sync = model.syncStatus, sync.behind > 0, sync.checkedAt != nil, !model.isWorking {
                Section {
                    IncomingUpdatesBanner(sync: sync)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section {
                hero
            } footer: {
                // How publishing works and the other ways to put the site online.
                Button {
                    model.showHelp("ways-to-publish")
                } label: {
                    Label("Ways to publish your website", systemImage: "questionmark.circle")
                }
                .buttonStyle(.link)
                .font(.callout)
            }

            if link != nil {
                syncDetails
            } else {
                buildDetails
            }

            GitHubSetupSection(site: site)

            if link != nil {
                hosting
            }
        }
        .formStyle(.grouped)
        .task(id: link?.repo) { model.refreshStatus(fetch: true) }
        .sheet(isPresented: $showSchedule) {
            SchedulePublishSheet(existing: model.scheduledPublish)
        }
    }

    // MARK: - Status card

    private struct Status {
        var icon: String
        var color: Color
        var title: String
        var detail: String
    }

    private var status: Status {
        if model.isWorking {
            return Status(icon: "arrow.triangle.2.circlepath", color: .accentColor,
                          title: model.workMessage ?? "Working…", detail: "This can take a moment.")
        }
        guard let link else {
            let build = model.buildState
            if build?.lastBuild == nil {
                return Status(icon: "hammer.circle.fill", color: .orange, title: "Flat HTML not generated yet",
                              detail: "Generate the flat HTML to create the finished website in the public folder.")
            }
            if build?.changedSinceBuild == true {
                return Status(icon: "exclamationmark.circle.fill", color: .orange, title: "You have changes since the flat HTML was generated",
                              detail: "Generate the flat HTML again so the website files include your latest edits.")
            }
            return Status(icon: "checkmark.circle.fill", color: .green, title: "Website files are up to date",
                          detail: "The public folder has your latest edits. This site isn't linked to GitHub, so it lives only on this Mac.")
        }
        if !model.isSignedIn {
            return Status(icon: "person.crop.circle.badge.exclamationmark", color: .orange,
                          title: "Sign in to publish from this Mac",
                          detail: "This site is linked to \(link.repo), but this Mac isn't signed in to GitHub yet. Sign in below.")
        }
        guard let sync = model.syncStatus else {
            return Status(icon: "arrow.triangle.2.circlepath", color: .secondary, title: "Checking GitHub…",
                          detail: "Comparing this Mac with \(link.repo).")
        }
        let local = sync.hasLocalChanges
        let localText = sync.changedFiles.isEmpty
            ? "\(sync.ahead) saved \(sync.ahead == 1 ? "update" : "updates")"
            : "\(sync.changedFiles.count) changed \(sync.changedFiles.count == 1 ? "file" : "files")"
        if sync.checkedAt == nil {
            return Status(icon: "wifi.exclamationmark", color: .orange, title: "Couldn't reach GitHub",
                          detail: local
                            ? "You have \(localText) on this Mac. Check your connection, then publish."
                            : "Check your internet connection and try again.")
        }
        switch (local, sync.behind > 0) {
        case (true, true):
            return Status(icon: "arrow.up.arrow.down.circle.fill", color: .incomingUpdates, title: "Changes here and on GitHub",
                          detail: "You have \(localText) on this Mac, and GitHub has \(sync.behind) newer \(sync.behind == 1 ? "update" : "updates") from another computer. Publishing combines them.")
        case (true, false):
            return Status(icon: "arrow.up.circle.fill", color: .orange, title: "Ready to publish",
                          detail: "You have \(localText) on this Mac that \(sync.pendingCount == 1 ? "isn't" : "aren't") on GitHub or your live site yet.")
        case (false, true):
            return Status(icon: "arrow.down.circle.fill", color: .incomingUpdates, title: "GitHub has newer changes",
                          detail: "\(sync.behind) \(sync.behind == 1 ? "update was" : "updates were") published from another computer. Get them to bring this Mac up to date.")
        case (false, false):
            return Status(icon: "checkmark.circle.fill", color: .green, title: "Everything is published",
                          detail: "This Mac and GitHub match. Your live site has your latest changes.")
        }
    }

    private var hero: some View {
        let s = status
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if model.isWorking || (link != nil && model.isSignedIn && model.syncStatus == nil) {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: s.icon)
                            .font(.system(size: 40))
                            .foregroundStyle(s.color)
                    }
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.title)
                        .font(.title2.bold())
                    Text(s.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if link != nil {
                publishControls
            } else {
                buildControls
            }
        }
        .padding(.vertical, 8)
    }

    private var publishControls: some View {
        let sync = model.syncStatus
        let nothingToDo = sync?.isUpToDate == true
        let onlyBehind = sync.map { !$0.hasLocalChanges && $0.behind > 0 } ?? false
        return VStack(alignment: .leading, spacing: 10) {
            if !onlyBehind && !nothingToDo {
                TextField("Describe your changes (optional)", text: $message, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
            }
            Button {
                let text = message
                Task {
                    await model.publish(message: text)
                    message = ""
                }
            } label: {
                Label(onlyBehind ? "Get Latest from GitHub" : "Flatten and Push to GitHub",
                      systemImage: onlyBehind ? "icloud.and.arrow.down" : "icloud.and.arrow.up")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(onlyBehind ? Color.incomingUpdates : nil)
            .controlSize(.extraLarge)
            .disabled(model.isWorking || !model.isSignedIn || nothingToDo)
            .keyboardShortcut(.defaultAction)

            if let schedule = model.scheduledPublish {
                ScheduledPublishCard(schedule: schedule, onChange: { showSchedule = true })
            } else {
                Button { showSchedule = true } label: {
                    Label("Schedule Publish…", systemImage: "clock")
                }
                .disabled(!model.isSignedIn)
                .help("Publish automatically at a date and time you choose")
            }
            Text("Note: Your Mac has to be on and CardStock has to be open for scheduled publishing to work.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var buildControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.build()
            } label: {
                Label("Generate Flat HTML", systemImage: "hammer")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(model.isWorking)

            if model.buildState?.lastBuild != nil {
                Button("Show Website Files in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([site.root.appending(path: "public")])
                }
            }
        }
    }

    // MARK: - Details

    private var syncDetails: some View {
        Section("Sync Status") {
            if let sync = model.syncStatus {
                LabeledContent("This Mac") {
                    if !sync.changedFiles.isEmpty {
                        Text("\(sync.changedFiles.count) unpublished \(sync.changedFiles.count == 1 ? "change" : "changes")")
                            .foregroundStyle(.orange)
                    } else if sync.ahead > 0 {
                        Text("\(sync.ahead) saved \(sync.ahead == 1 ? "update" : "updates") not on GitHub")
                            .foregroundStyle(.orange)
                    } else {
                        Text("No unpublished changes")
                    }
                }
                if !sync.changedFiles.isEmpty {
                    DisclosureGroup("Changed files") {
                        ForEach(sync.changedFiles.prefix(30), id: \.self) { file in
                            Text(file)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if sync.changedFiles.count > 30 {
                            Text("and \(sync.changedFiles.count - 30) more")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("GitHub") {
                    if sync.behind > 0 {
                        Text("\(sync.behind) newer \(sync.behind == 1 ? "update" : "updates") not on this Mac")
                            .foregroundStyle(.blue)
                    } else if sync.remoteDate == nil {
                        Text("Nothing published yet")
                    } else {
                        Text("Matches this Mac")
                    }
                }
                if let message = sync.remoteMessage, let date = sync.remoteDate {
                    LabeledContent("Latest on GitHub") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(message).lineLimit(1)
                            Text(date, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            LabeledContent("Last published from this Mac") {
                if let date = model.lastPublished {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Not yet").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Last checked GitHub") {
                HStack {
                    if model.isCheckingSync {
                        ProgressView().controlSize(.small)
                    } else if let checked = model.syncStatus?.checkedAt {
                        Text(checked, format: .relative(presentation: .named))
                    } else if let error = model.syncStatus?.fetchError {
                        Text(error).foregroundStyle(.orange)
                    }
                    Button("Check Now") { model.refreshStatus(fetch: true) }
                        .disabled(model.isCheckingSync || !model.isSignedIn)
                }
            }
        }
    }

    private var buildDetails: some View {
        Section("Flat HTML") {
            LabeledContent("Last generated") {
                if let date = model.buildState?.lastBuild {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Edits since then") {
                Text(model.buildState?.changedSinceBuild == false ? "None" : "Yes")
            }
            LabeledContent("Website files") {
                Text("public/").font(.body.monospaced())
            }
        }
    }

    private var hosting: some View {
        Section {
            Step(number: 1, title: "Connect the repository", detail: "In Cloudflare, go to Workers & Pages → Create → Pages → Connect to Git, and choose \(link?.repo ?? "this repository").")
            Step(number: 2, title: "Use these build settings", detail: "Build command: leave empty. Build output directory: public")
            Step(number: 3, title: "Add your web address", detail: "Paste the address Cloudflare gives you (like my-site.pages.dev) below, so CardStock can link to your live site and build your RSS feed.")
            TextField("Web address", text: webAddress, prompt: Text("https://my-site.pages.dev"))
        } header: {
            Text("Hosting with Cloudflare Pages")
        } footer: {
            Text("You only need to do this once per site. Any host that deploys from GitHub works the same way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var webAddress: Binding<String> {
        Binding(
            get: { model.site?.config.url ?? "" },
            set: { newValue in
                guard var config = model.site?.config else { return }
                config.url = newValue.trimmingCharacters(in: .whitespaces)
                model.updateConfig(config)
            })
    }
}

/// A numbered step in an explanation.
private struct Step: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
