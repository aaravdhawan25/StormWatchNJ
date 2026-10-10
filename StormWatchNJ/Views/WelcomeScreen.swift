import SwiftUI

/// The first thing anyone sees: the storm scene, what the app does, and the way in.
///
/// Everyone signs in. Votes and removals only mean something when each one is
/// tied to a person, so there is no anonymous mode to fall back to.
struct WelcomeScreen: View {
    @State private var route: AuthRoute?
    @State private var showServer = false
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                StormBackdrop()

                VStack(spacing: 0) {
                    Spacer(minLength: 24)

                    AppLogoMark(size: 104)
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)

                    Text("StormWatch NJ")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 18)
                    Text("Your neighborhood's storm hazard map")
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        feature("camera.fill", "Snap a hazard", "AI fills in the report for you")
                        feature("water.waves", "Watch the rivers", "Live USGS gauges across New Jersey")
                        feature("building.2.fill", "Reach public works", "Reports go straight to your town")
                    }
                    .padding(.top, 30)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

                    Spacer(minLength: 24)

                    VStack(spacing: 12) {
                        Button { route = AuthRoute(kind: .resident, creating: true) } label: {
                            Text("Create an account")
                                .font(.system(.headline, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.white, in: Capsule())
                                .foregroundStyle(Theme.navy)
                        }
                        Button { route = AuthRoute(kind: .resident, creating: false) } label: {
                            Text("Sign in")
                                .font(.system(.headline, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Theme.navy.opacity(0.55), in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 1))
                                .foregroundStyle(.white)
                        }
                        Button { route = AuthRoute(kind: .township, creating: false) } label: {
                            Label("Sign in as a township", systemImage: "building.columns.fill")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(Theme.navy)
                                .padding(.vertical, 8)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                }
                .padding(.vertical, 12)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showServer = true } label: {
                        Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityLabel("Server settings")
                }
            }
            .navigationDestination(item: $route) { route in
                AuthScreen(kind: route.kind, isCreating: route.creating)
            }
            .sheet(isPresented: $showServer) { ServerSettingsSheet() }
            .onAppear {
                withAnimation(.spring(duration: 0.8, bounce: 0.3)) { appeared = true }
            }
            // Light status bar over the night sky.
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
    }
}

struct AuthRoute: Hashable {
    let kind: AccountKind
    let creating: Bool
}

/// Where the app finds its backend. Reachable before sign-in, because without
/// the right address nobody could sign in to change it.
struct ServerSettingsSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://127.0.0.1:8000", text: $settings.backendURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("StormWatch server")
                } footer: {
                    Text("Accounts and the shared hazard map live on this server. On the simulator, the default reaches a backend running on this Mac. On a phone, use the Mac's network address or wherever the backend is hosted.")
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.teal)
        .presentationDetents([.medium])
    }
}
