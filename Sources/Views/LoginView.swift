import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        if auth.isSignedIn {
            VStack(spacing: 30) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 100))
                Text(auth.email ?? "Signed in").font(.system(size: 34, weight: .semibold))
                Text("\(auth.addons.count) addons").foregroundStyle(.secondary)
                Button("Sign out", role: .destructive) { auth.logout() }
                    .buttonStyle(.bordered)
            }
            .padding(80)
        } else {
            LoginView()
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Harbor").font(.system(size: 60, weight: .bold))
            Text("Sign in to Stremio")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .frame(width: 700)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .frame(width: 700)

            if let error {
                Text(error).foregroundStyle(.red).font(.system(size: 22))
            }

            Button {
                Task { await signIn() }
            } label: {
                Text(busy ? "Signing in…" : "Sign in")
                    .frame(width: 300)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || email.isEmpty || password.isEmpty)

            Text("Your credentials go straight to Stremio's API and are not stored — only the session token is kept.")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 800)
                .padding(.top, 12)
        }
        .padding(80)
    }

    private func signIn() async {
        busy = true; error = nil
        do {
            try await auth.login(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
