import SwiftUI

@main
struct ColorNovaApp: App {
    @StateObject private var leaderboard = LeaderboardStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(leaderboard) // ✅ required
        }
    }
}
