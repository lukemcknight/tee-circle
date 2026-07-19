import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: TeeCircleStore

    var body: some View {
        Group {
            if store.isRestoringSession {
                ZStack {
                    TeeCircleBrand.forest.ignoresSafeArea()
                    ProgressView("Opening clubhouse…")
                        .tint(TeeCircleBrand.signal)
                        .foregroundStyle(.white)
                }
            } else if store.isAuthenticated, store.needsProfileSetup == true {
                ProfileSetupView()
            } else if store.isAuthenticated {
                TabView(selection: $store.selectedTab) {
                    NavigationStack(path: $store.path) {
                        HomeView()
                            .navigationDestination(for: AppRoute.self, destination: destination)
                    }
                    .teeTabBar()
                    .tabItem { Label(AppTab.rounds.title, systemImage: AppTab.rounds.systemImage) }
                    .tag(AppTab.rounds)

                    NavigationStack(path: $store.golfersPath) {
                        GolfersView()
                            .navigationDestination(for: GolferSummary.self) { golfer in
                                GolferDetailView(golfer: golfer)
                            }
                    }
                    .teeTabBar()
                    .tabItem { Label(AppTab.golfers.title, systemImage: AppTab.golfers.systemImage) }
                    .tag(AppTab.golfers)

                    NavigationStack {
                        ProfileView()
                    }
                    .teeTabBar()
                    .tabItem { Label(AppTab.account.title, systemImage: AppTab.account.systemImage) }
                    .tag(AppTab.account)
                }
                .tint(TeeCircleBrand.signal)
            } else {
                AuthenticationView()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: store.isAuthenticated)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: store.needsProfileSetup)
        .alert("TeeCircle", isPresented: errorPresented) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Something went wrong.")
        }
        .sheet(item: $store.pendingInvite) { invite in
            InviteClaimView(invite: invite)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .createRound:
            CreateRoundView()
        case .createTrip:
            CreateTripView()
        case let .trip(id):
            TripHubView(tripID: id)
        case let .leaderboard(id):
            LeaderboardView(tripID: id)
        case let .score(tripID, roundID, playerID):
            ScorecardView(tripID: tripID, roundID: roundID, initialPlayerID: playerID)
        case let .paywall(id):
            TripPaywallView(tripID: id)
        case .legacyRounds:
            LegacyRoundsView()
        case .profile:
            ProfileView()
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }
}
