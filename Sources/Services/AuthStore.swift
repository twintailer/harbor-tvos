import Foundation
import SwiftUI

// Holds the Stremio session + the user's addons for the whole app.
@MainActor
final class AuthStore: ObservableObject {
    @Published var authKey: String?
    @Published var email: String?
    @Published var addons: [Addon] = []
    @Published var continueWatching: [CwItem] = []
    @Published var libraryItems: [StremioService.LibraryItem] = []

    private let keyAuth = "harbor.stremio.authKey"
    private let keyEmail = "harbor.stremio.email"
    private var playbackSaveTask: Task<Void, Never>?

    func savePlaybackProgress(meta: MetaItem, videoId: String, season: Int?, episode: Int?,
                              position: Double, duration: Double, existing: StremioService.LibraryItem?) {
        guard let key = authKey else { return }
        let previous = playbackSaveTask
        playbackSaveTask = Task {
            await previous?.value
            guard authKey == key else { return }
            await StremioService.saveProgress(authKey: key, meta: meta, videoId: videoId,
                season: season, episode: episode, position: position, duration: duration, existing: existing)
        }
    }

    func refreshAfterPlayback() async {
        await playbackSaveTask?.value
        await loadLibrary()
        await loadContinueWatching()
    }

    init() {
        let secureToken = SecureStore.read(keyAuth)
        authKey = secureToken ?? UserDefaults.standard.string(forKey: keyAuth)
        if secureToken == nil, let token = authKey {
            if SecureStore.write(token, account: keyAuth) {
                UserDefaults.standard.removeObject(forKey: keyAuth)
            }
        }
        email = UserDefaults.standard.string(forKey: keyEmail)
        if authKey != nil { Task { await refreshAccountData() } }
    }

    func loadContinueWatching() async {
        guard let authKey else { return }
        let cw = await StremioService.continueWatching(authKey: authKey)
        guard self.authKey == authKey else { return }
        continueWatching = cw.map { $0.asCwItem }
    }

    func loadLibrary() async {
        guard let authKey else { libraryItems = []; return }
        let items = await StremioService.library(authKey: authKey)
        guard self.authKey == authKey else { return }
        libraryItems = items
    }

    func clearContinueWatching(_ id: String) async {
        continueWatching.removeAll { $0.id == id }
        guard let authKey else { return }
        await StremioService.clearContinueWatching(authKey: authKey, id: id)
        await loadContinueWatching()
        await loadLibrary()
    }

    func removeFromHistory(_ id: String) async {
        libraryItems.removeAll { $0._id == id }
        continueWatching.removeAll { $0.id == id }
        guard let authKey else { return }
        await StremioService.removeFromHistory(authKey: authKey, id: id)
        await loadLibrary()
        await loadContinueWatching()
    }

    func refreshAccountData() async {
        await loadAddons()
        await loadLibrary()
        await loadContinueWatching()
    }

    var isSignedIn: Bool { authKey != nil }

    func login(email: String, password: String) async throws {
        let res = try await StremioService.login(email: email, password: password)
        authKey = res.authKey
        self.email = res.user?.email ?? email
        if SecureStore.write(res.authKey, account: keyAuth) {
            UserDefaults.standard.removeObject(forKey: keyAuth)
        }
        UserDefaults.standard.set(self.email, forKey: keyEmail)
        await refreshAccountData()
    }

    func logout() {
        authKey = nil
        email = nil
        addons = []
        libraryItems = []
        continueWatching = []
        SecureStore.delete(keyAuth)
        UserDefaults.standard.removeObject(forKey: keyAuth)
        UserDefaults.standard.removeObject(forKey: keyEmail)
    }

    func loadAddons() async {
        guard let authKey else { return }
        let list = await StremioService.userAddons(authKey: authKey)
        addons = list
    }
}
