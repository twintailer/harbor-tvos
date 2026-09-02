import SwiftUI

struct AddonsView: View {
    var onRootBack: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @State private var refreshing = false
    @State private var addonURL = ""
    @State private var working = false
    @State private var error: String?
    @State private var pendingRemovalURL: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        HarborPageHeader(title: "Add-ons", eyebrow: "Your sources",
                                         subtitle: "Catalogs, metadata and streams connected to Harbor",
                                         count: auth.addons.count)
                        Spacer()
                        if auth.isSignedIn {
                            Button {
                                refreshing = true
                                Task { await auth.loadAddons(); refreshing = false }
                            } label: {
                                Label(refreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(HarborActionButtonStyle(tone: .secondary))
                            .disabled(refreshing)
                        }
                    }

                    if auth.isSignedIn {
                        HStack(spacing: 18) {
                            TextField("Add-on manifest URL", text: $addonURL)
                                .textContentType(.URL)
                            Button {
                                installAddon()
                            } label: {
                                Label("Install", systemImage: "plus")
                            }
                            .buttonStyle(HarborActionButtonStyle(tone: .primary))
                            .disabled(working || addonURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let error {
                            Text(error).font(.system(size: 20)).foregroundStyle(.red)
                        }
                    }

                    if !auth.isSignedIn {
                        HarborEmptyState(icon: "person.crop.circle",
                                         title: "Sign in to load add-ons",
                                         message: "Use Settings › Account to sign in to Stremio.")
                    } else if auth.addons.isEmpty {
                        HarborEmptyState(icon: "puzzlepiece.extension",
                                         title: "No add-ons found",
                                         message: "Install add-ons in Stremio, then choose Refresh.")
                    } else {
                        ForEach(Array(auth.addons.enumerated()), id: \.offset) { _, addon in
                            addonRow(addon)
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            .background(HarborStageBackground())
            .onExitCommand(perform: onRootBack)
        }
        .confirmationDialog("Remove this add-on from your Stremio account?",
                            isPresented: Binding(get: { pendingRemovalURL != nil },
                                                 set: { if !$0 { pendingRemovalURL = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Add-on", role: .destructive) { removePendingAddon() }
            Button("Cancel", role: .cancel) { pendingRemovalURL = nil }
        }
    }

    private func addonRow(_ addon: Addon) -> some View {
        let resources = (addon.manifest?.resources ?? []).map(\.name)
        let catalogs = addon.manifest?.catalogs ?? []
        return HStack(alignment: .top, spacing: 24) {
            Image(systemName: addon.hasStream ? "play.rectangle.on.rectangle.fill" : "puzzlepiece.extension.fill")
                .font(.system(size: 38))
                .foregroundStyle(addon.hasStream ? Color.green : Color.gray)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 8) {
                Text(addon.manifest?.name ?? addon.manifest?.id ?? "Add-on")
                    .font(.system(size: 27, weight: .semibold))
                if !resources.isEmpty {
                    Text(resources.map { $0.capitalized }.joined(separator: " · "))
                        .font(.system(size: 20)).foregroundStyle(.secondary)
                }
                if !catalogs.isEmpty {
                    Text("\(catalogs.count) catalog\(catalogs.count == 1 ? "" : "s")")
                        .font(.system(size: 18)).foregroundStyle(.tertiary)
                }
                Text(addon.base)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            if addon.hasStream {
                Text("STREAMS")
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.green.opacity(0.18)))
                    .foregroundStyle(.green)
            }
            if addon.flags?.official != true && addon.flags?.protected != true {
                Button(role: .destructive) {
                    pendingRemovalURL = addon.transportUrl
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(working)
            }
        }
        .padding(26)
        .background(HarborTVDesign.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func installAddon() {
        guard let key = auth.authKey else { return }
        let input = addonURL
        working = true; error = nil
        Task {
            if await StremioService.installAddon(authKey: key, from: input) {
                addonURL = ""
                await auth.loadAddons()
            } else {
                error = "The manifest was invalid, protected, or Stremio rejected the update."
            }
            working = false
        }
    }

    private func removePendingAddon() {
        guard let key = auth.authKey, let url = pendingRemovalURL else { return }
        pendingRemovalURL = nil
        working = true; error = nil
        Task {
            if await StremioService.removeAddon(authKey: key, transportURL: url) {
                await auth.loadAddons()
            } else {
                error = "Stremio rejected the add-on update."
            }
            working = false
        }
    }
}
