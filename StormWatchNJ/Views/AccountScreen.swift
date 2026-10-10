import SwiftUI

/// Sign in, create an account, or manage the one you have.
struct AccountScreen: View {
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var store: HazardStore

    @State private var kind: AccountKind = .resident
    @State private var isCreating = false
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var towns: [TownshipDomain] = []

    var body: some View {
        Form {
            if let current = account.account {
                signedIn(current)
            } else if let pending = account.pendingEmail {
                verification(for: pending)
            } else {
                credentials
            }

        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { towns = await account.townshipDomains() }
        .onChange(of: kind) { _, _ in message = nil }
    }

    private var title: String {
        if account.isSignedIn { return "Account" }
        if account.pendingEmail != nil { return "Verify email" }
        if kind == .township { return isCreating ? "Township account" : "Township sign-in" }
        return isCreating ? "Create account" : "Sign in"
    }

    /// Shown directly under whichever form produced it — the township screen has a
    /// long list beneath the form, and a message below that would be off-screen.
    @ViewBuilder
    private var messageRow: some View {
        if let message {
            Section {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Signed out

    @ViewBuilder
    private var credentials: some View {
        Section {
            Picker("Account type", selection: $kind) {
                ForEach(AccountKind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text(kind == .township
                 ? "For municipal staff. Use your official township email — you'll confirm it with a code sent to that address, so only someone who receives mail there can sign in."
                 : "An account lets you remove your own reports and vote when a hazard is gone.")
        }

        Section {
            TextField(kind == .township ? "you@yourtownship.gov" : "Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(isCreating ? "Password (8 or more characters)" : "Password", text: $password)
                .textContentType(isCreating ? .newPassword : .password)

            Button {
                run { isCreating
                    ? try await account.signUp(email: email, password: password, kind: kind)
                    : try await account.signIn(email: email, password: password)
                }
            } label: {
                HStack {
                    Spacer()
                    if isWorking { ProgressView() } else {
                        Text(isCreating ? "Create account" : "Sign in").fontWeight(.semibold)
                    }
                    Spacer()
                }
            }
            .disabled(isWorking || email.isEmpty || password.count < (isCreating ? 8 : 1))

            Button(isCreating ? "I already have an account" : "Create an account instead") {
                isCreating.toggle()
                message = nil
            }
            .font(.footnote)
        }

        messageRow

        if GoogleSignIn.isConfigured {
            Section {
                Button {
                    run { try await account.signInWithGoogle(kind: kind) }
                } label: {
                    Label("Continue with Google", systemImage: "globe")
                }
                .disabled(isWorking)
            } footer: {
                Text(kind == .township
                     ? "Works if your township's email is run by Google and is on the list below."
                     : "Google confirms your email, so there is no code to enter.")
            }
        }

        if kind == .township, !towns.isEmpty {
            Section("Recognised township domains") {
                ForEach(towns) { town in
                    LabeledContent(town.name) {
                        Text("@\(town.domain)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Verification

    @ViewBuilder
    private func verification(for pending: String) -> some View {
        Section {
            TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title3.monospacedDigit())

            Button {
                run { try await account.verify(code: code) }
            } label: {
                HStack {
                    Spacer()
                    if isWorking { ProgressView() } else { Text("Verify").fontWeight(.semibold) }
                    Spacer()
                }
            }
            .disabled(isWorking || code.count < 6)
        } header: {
            Text("Check your email")
        } footer: {
            Text("We sent a code to \(pending). It expires in 15 minutes.")
        }

        messageRow

        Section {
            Button("Send a new code") {
                run {
                    try await account.resendCode()
                    message = "If a code was due, a new one is on its way. You can request one a minute."
                }
            }
            Button("Use a different email") {
                account.pendingEmail = nil
                code = ""
                message = nil
            }
        }
        .font(.footnote)
    }

    // MARK: - Signed in

    @ViewBuilder
    private func signedIn(_ current: Account) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: current.isTownship ? "building.columns.fill" : "person.crop.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.email).font(.subheadline.weight(.semibold))
                    Text(current.isTownship ? (current.township ?? "Township") + " · verified staff" : "Resident")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text(current.isTownship
                 ? "Township accounts can set crew status on any hazard and remove hazards once they are cleared."
                 : "You can remove hazards you reported, and vote when someone else's is no longer there. Three votes from different people remove it.")
        }

        Section {
            Button("Sign out", role: .destructive) {
                run {
                    await account.signOut()
                    await HazardSync.pull(into: store, account: account)
                    password = ""
                }
            }
        }
    }

    /// Runs an account action, showing its failure in place rather than as an alert.
    private func run(_ action: @escaping () async throws -> Void) {
        message = nil
        isWorking = true
        Task {
            do {
                try await action()
                if account.isSignedIn {
                    password = ""
                    code = ""
                    await HazardSync.pull(into: store, account: account)
                }
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
