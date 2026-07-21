import Foundation
import SwiftUI

// Holds the Stremio session + the user's addons for the whole app.
@MainActor
final class AuthStore: ObservableObject {
    @Published var authKey: String?
    @Published var email: String?
    @Published var addons: [Addon] = []
    @Published var continueWatching: [CwItem] = []

    private let keyAuth = "harbor.stremio.authKey"
    private let keyEmail = "harbor.stremio.email"

    init() {
        authKey = UserDefaults.standard.string(forKey: keyAuth)
        email = UserDefaults.standard.string(forKey: keyEmail)
        if authKey != nil { Task { await loadAddons(); await loadContinueWatching() } }
    }

    func loadContinueWatching() async {
        guard let authKey else { return }
        let cw = await StremioService.continueWatching(authKey: authKey)
        continueWatching = cw.map { $0.asCwItem }
    }

    var isSignedIn: Bool { authKey != nil }

    func login(email: String, password: String) async throws {
        let res = try await StremioService.login(email: email, password: password)
        authKey = res.authKey
        self.email = res.user?.email ?? email
        UserDefaults.standard.set(res.authKey, forKey: keyAuth)
        UserDefaults.standard.set(self.email, forKey: keyEmail)
        await loadAddons()
        await loadContinueWatching()
    }

    func logout() {
        authKey = nil
        email = nil
        addons = []
        UserDefaults.standard.removeObject(forKey: keyAuth)
        UserDefaults.standard.removeObject(forKey: keyEmail)
    }

    func loadAddons() async {
        guard let authKey else { return }
        let list = await StremioService.userAddons(authKey: authKey)
        if !list.isEmpty { addons = list }
    }
}
