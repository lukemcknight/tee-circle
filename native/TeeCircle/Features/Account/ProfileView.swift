import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: TeeCircleStore
    @Environment(\.openURL) private var openURL
    @State private var notificationsEnabled = true
    @State private var showDeleteConfirmation = false
    @State private var isEditingIdentity = false

    var body: some View {
        ZStack {
            BroadcastBackground()
            Form {
                Section {
                    HStack(spacing: 15) {
                        Text(store.currentDisplayName.prefix(1).uppercased())
                            .font(.title2.weight(.black))
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(TeeCircleBrand.raisedCard, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.currentDisplayName).font(.headline)
                            Text(Username.display(store.currentUsername) ?? "TeeCircle player")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        isEditingIdentity = true
                    } label: {
                        Label("Edit name and username", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("account.editIdentity")
                }

                Section("Notifications") {
                    Toggle("Trip and scoring updates", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { enabled in
                            if enabled { Task { await store.requestNotificationPermission() } }
                        }
                    NavigationLink {
                        Text("Follow a trip from its hub to start one live leaderboard on this iPhone.")
                            .padding()
                            .navigationTitle("Live Activities")
                    } label: {
                        Label("Live Activity settings", systemImage: "iphone.radiowaves.left.and.right")
                    }
                }

                Section("Help & legal") {
                    Button { openURL(store.configuration.webBaseURL.appending(path: "privacy")) } label: {
                        Label("Privacy policy", systemImage: "hand.raised.fill")
                    }
                    Button { openURL(store.configuration.webBaseURL.appending(path: "terms")) } label: {
                        Label("Terms", systemImage: "doc.text.fill")
                    }
                    Button { openURL(URL(string: "mailto:support@teecircle.app")!) } label: {
                        Label("Contact support", systemImage: "envelope.fill")
                    }
                }

                Section {
                    Button("Sign out") { store.signOut() }
                        .accessibilityIdentifier("account.signOut")
                    Button("Delete account", role: .destructive) { showDeleteConfirmation = true }
                        .accessibilityIdentifier("account.delete")
                } footer: {
                    Text("A captain must transfer or archive an active shared trip before account deletion. Completed results remain readable by the roster.")
                }

                Section {
                    HStack {
                        Text("Native release")
                        Spacer()
                        Text("2.0.0 (10)").foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Account")
        .sheet(isPresented: $isEditingIdentity) {
            NavigationStack {
                EditIdentityView()
                    .environmentObject(store)
            }
        }
        .confirmationDialog(
            "Delete your TeeCircle account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Request deletion", role: .destructive) {
                if store.configuration.useMockData {
                    store.errorMessage = "Fixture mode cannot delete an account. Production first checks ownership transfer and archival constraints."
                } else {
                    Task {
                        guard let blockers = await store.accountDeletionBlockers() else { return }
                        if blockers.canDelete {
                            store.errorMessage = "Your account is eligible for deletion. Confirming deletion requires the server-side destructive command."
                        } else {
                            let names = blockers.ownedTrips.map(\.name).joined(separator: ", ")
                            store.errorMessage = "Transfer or archive these trips first: \(names)."
                        }
                    }
                }
            }
            .accessibilityIdentifier("account.confirmDelete")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("TeeCircle will check shared-trip ownership before removing private account data.")
        }
    }
}
