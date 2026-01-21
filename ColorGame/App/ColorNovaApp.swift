import SwiftUI

@main
struct ColorNovaApp: App {
    @StateObject private var leaderboard = LeaderboardStore()
    @StateObject private var achievements = AchievementsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(leaderboard)
                .environmentObject(achievements)
        }
    }
}
