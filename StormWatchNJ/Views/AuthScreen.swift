import SwiftUI

/// Sign in, create an account, and confirm the emailed code — for residents and
/// for township staff — on the storm backdrop.
struct AuthScreen: View {
    @EnvironmentObject private var account: AccountStore

    @State var kind: AccountKind
    @State var isCreating: Bool

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var towns: [TownshipDomain] = []
    @State private var showTowns = false
    @FocusState private var focus: Field?

    private enum Field { case email, password, code }

    var body: some View {
        ZStack {
            StormBackdrop(animated: false, waterLevel: 0.14)

            ScrollView {
                VStack(spacing: 18) {
                    AppLogoMark(size: 64).padding(.top, 8)

                    Text(heading)
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                    Text(subheading)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    VStack(spacing: 14) {
                        if let pending = account.pendingEmail {
                            verification(for: pending)
                        } else {
                            credentials
                        }

                        if let message {
                            Label(message, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.amber)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(18)
                    .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                    .environment(\.colorScheme, .dark)

                    if account.pendingEmail == nil, kind == .township, !towns.isEmpty {
                        townList
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { towns = await account.townshipDomains() }
        .onDisappear { account.pendingEmail = nil }
    }

    private var heading: String {
        if account.pendingEmail != nil { return "Check your email" }
        if kind == .township { return isCreating ? "Township account" : "Township sign-in" }
        return isCreating ? "Create your account" : "Welcome back"
    }

    private var subheading: String {
        if let pending = account.pendingEmail {
            return "We sent an email to \(pending). Enter the code from it, or tap the link in it and come back."
        }
        if kind == .township {
            return "For municipal staff. Use your official township email — you'll confirm it with a code sent there, so only someone who receives mail at that address can sign in."
        }
        return isCreating
            ? "One account lets you report hazards, remove your own, and vote when one is gone."
            : "Sign in to see what's happening on your streets."
    }

    // MARK: - Credentials

    @ViewBuilder
    private var credentials: some View {
        Picker("Account type", selection: $kind) {
            ForEach(AccountKind.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: kind) { _, _ in message = nil }

        field(icon: "envelope.fill") {
            TextField("", text: $email,
                      prompt: Text(verbatim: kind == .township ? "you@yourtownship.gov" : "Email").foregroundColor(.white.opacity(0.45)))
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }
        }

        field(icon: "lock.fill") {
            SecureField("", text: $password,
                        prompt: Text(isCreating ? "Password (8+ characters)" : "Password").foregroundColor(.white.opacity(0.45)))
                .textContentType(isCreating ? .newPassword : .password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)
        }

        primaryButton(isCreating ? "Create account" : "Sign in",
                      enabled: !email.isEmpty && password.count >= (isCreating ? 8 : 1),
                      action: submit)

        if GoogleSignIn.isConfigured {
            Button {
                run { try await account.signInWithGoogle(kind: kind) }
            } label: {
                Label("Continue with Google", systemImage: "globe")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(.white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }

        Button(isCreating ? "I already have an account" : "New here? Create an account") {
            isCreating.toggle()
            message = nil
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white.opacity(0.85))
    }

    private func submit() {
        focus = nil
        run {
            if isCreating {
                try await account.signUp(email: email, password: password, kind: kind)
            } else {
                try await account.signIn(email: email, password: password, kind: kind)
            }
        }
    }

    // MARK: - Verification

    @ViewBuilder
    private func verification(for pending: String) -> some View {
        field(icon: "number") {
            TextField("", text: $code, prompt: Text("Code from the email").foregroundColor(.white.opacity(0.45)))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title3.monospacedDigit().weight(.semibold))
                .focused($focus, equals: .code)
        }
        .onAppear { focus = .code }

        primaryButton("Verify", enabled: code.count >= 6) {
            run { try await account.verify(code: code) }
        }

        // Confirming by the emailed link works too; then the password signs in.
        Button("I tapped the link in the email") {
            run { try await account.signIn(email: pending, password: password, kind: kind) }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white.opacity(0.85))
        .disabled(password.isEmpty || isWorking)

        HStack {
            Button("Send a new email") {
                run {
                    try await account.resendCode()
                    message = "A new email is on its way. You can ask once a minute."
                }
            }
            Spacer()
            Button("Use a different email") {
                account.pendingEmail = nil
                code = ""
                message = nil
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white.opacity(0.85))
    }

    // MARK: - Pieces

    private var townList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation { showTowns.toggle() }
            } label: {
                HStack {
                    Label("\(towns.count) recognised townships", systemImage: "building.columns.fill")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Image(systemName: showTowns ? "chevron.up" : "chevron.down").font(.caption.weight(.bold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(14)
            }
            .buttonStyle(.plain)

            if showTowns {
                ForEach(towns) { town in
                    HStack {
                        Text(town.name).font(.caption.weight(.medium)).foregroundStyle(.white)
                        Spacer()
                        Text("@\(town.domain)").font(.caption2).foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .padding(.bottom, 2)
            }
        }
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.brightTeal)
                .frame(width: 20)
            content().foregroundStyle(.white).tint(Theme.brightTeal)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 1))
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                if isWorking { ProgressView().tint(Theme.navy) } else {
                    Text(title).font(.system(.headline, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(.white.opacity(enabled ? 1 : 0.45), in: Capsule())
            .foregroundStyle(Theme.navy)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isWorking)
    }

    /// Runs an account action, showing a failure in the card rather than as an alert.
    private func run(_ action: @escaping () async throws -> Void) {
        message = nil
        isWorking = true
        Task {
            do {
                try await action()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
