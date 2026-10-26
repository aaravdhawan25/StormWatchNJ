import SwiftUI

// the signed-in account
struct AccountScreen: View {
    @EnvironmentObject private var account: AccountStore
    @State private var confirmSignOut = false

    var body: some View {
        List {
            if let current = account.account {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: current.isTownship ? "building.columns.fill" : "person.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 72, height: 72)
                            .background(LinearGradient(colors: [Theme.deep, Theme.teal],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: Circle())
                            .shadow(color: Theme.teal.opacity(0.4), radius: 10, y: 4)
                        Text(current.email)
                            .font(.system(.headline, design: .rounded))
                        Chip(text: current.isTownship ? "\(current.township ?? "Township") · verified staff" : "Resident",
                             symbol: current.isTownship ? "checkmark.seal.fill" : "house.fill",
                             tint: Theme.teal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } footer: {
                    Text(current.isTownship
                         ? "Township accounts can set crew status on any hazard and remove hazards once they are cleared."
                         : "You can remove hazards you reported, and vote when someone else's is no longer there. Three votes from different people remove it.")
                }

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of StormWatch NJ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await account.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to use the app.")
        }
    }
}
