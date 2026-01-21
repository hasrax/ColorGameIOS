import SwiftUI
import Combine
import UIKit

// MARK: - Models

enum GameMode: String, CaseIterable, Identifiable, Codable {
    case easy, moderate, hard
    var id: String { rawValue }

    var gridSize: Int {
        switch self {
        case .easy: return 3
        case .moderate: return 5
        case .hard: return 7
        }
    }

    // per-round time
    var roundTime: Int {
        switch self {
        case .easy: return 15
        case .moderate: return 25
        case .hard: return 35
        }
    }

    // total session length
    var sessionSeconds: Int {
        switch self {
        case .easy: return 45
        case .moderate: return 60
        case .hard: return 75
        }
    }

    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .easy: return "3 × 3 Grid"
        case .moderate: return "5 × 5 Grid"
        case .hard: return "7 × 7 Grid"
        }
    }

    var accent: Color {
        switch self {
        case .easy: return Color(hue: 0.52, saturation: 0.75, brightness: 0.95)
        case .moderate: return Color(hue: 0.80, saturation: 0.75, brightness: 0.95)
        case .hard: return Color(hue: 0.05, saturation: 0.85, brightness: 0.95)
        }
    }

    var tip: String {
        switch self {
        case .easy: return "Tip: Scan corners first — the match pops out."
        case .moderate: return "Tip: Use peripheral vision — don’t stare too long."
        case .hard: return "Tip: Scan rows/columns — it’s faster than random."
        }
    }
}

enum TileShape: String, CaseIterable, Codable, Hashable {
    case circle, diamond, triangle, star

    @ViewBuilder
    func view(color: Color) -> some View {
        switch self {
        case .circle:
            Circle().fill(color)
        case .diamond:
            DiamondShape().fill(color)
        case .triangle:
            TriangleShape().fill(color)
        case .star:
            StarShape(points: 5, innerRatio: 0.45).fill(color)
        }
    }
}

struct ScoreEntry: Codable, Identifiable {
    let id: UUID
    let name: String
    let score: Int
    let mode: GameMode
    let date: Date

    init(id: UUID = UUID(), name: String, score: Int, mode: GameMode, date: Date = Date()) {
        self.id = id
        self.name = name
        self.score = score
        self.mode = mode
        self.date = date
    }
}

final class LeaderboardStore: ObservableObject {
    @AppStorage("leaderboard_json") private var leaderboardJSON: String = "[]"
    @Published private(set) var entries: [ScoreEntry] = []

    init() { load() }

    func load() {
        guard let data = leaderboardJSON.data(using: .utf8) else { entries = []; return }
        do { entries = try JSONDecoder().decode([ScoreEntry].self, from: data) }
        catch { entries = [] }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            leaderboardJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch { }
    }

    func upsertBestScore(name: String, score: Int, mode: GameMode) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = clean.isEmpty ? "Player" : clean

        if let idx = entries.firstIndex(where: {
            $0.name.lowercased() == finalName.lowercased() && $0.mode == mode
        }) {
            if score > entries[idx].score {
                entries[idx] = ScoreEntry(id: entries[idx].id, name: finalName, score: score, mode: mode, date: Date())
            }
        } else {
            entries.append(ScoreEntry(name: finalName, score: score, mode: mode))
        }

        entries.sort { $0.score > $1.score }
        if entries.count > 100 { entries = Array(entries.prefix(100)) }
        persist()
    }

    func top(for mode: GameMode? = nil) -> [ScoreEntry] {
        let filtered = (mode == nil) ? entries : entries.filter { $0.mode == mode! }
        return Array(filtered.sorted { $0.score > $1.score }.prefix(10))
    }
}

// MARK: - Routing

enum Route: Hashable {
    case game(mode: GameMode, shapeMode: Bool, name: String)
    case leaderboard
    case howto
}

// MARK: - ContentView (Menu + Navigation)

struct ContentView: View {
    @EnvironmentObject private var leaderboard: LeaderboardStore
    @State private var path: [Route] = []

    @State private var shapeModeEnabled = false
    @State private var showNameSheet = false
    @State private var pendingMode: GameMode? = nil
    @State private var playerName: String = ""

    @State private var pulse = false
    @State private var tipIndex = 0

    private let tips: [String] = [
        "⚡️ Tap fast for Speed Bonus!",
        "🔥 Keep a streak alive — it boosts points.",
        "🧠 Hard mode: scan row-by-row, not randomly.",
        "🌈 Shape Mode: match BOTH color + shape."
    ]
    private let tipTicker = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                GalaxyBackgroundView()

                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Text("ColorNova")
                            .font(.system(size: 44, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(radius: 6)

                        Text("Match fast. Score big. Shine ✨")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(.black.opacity(0.22))
                            .cornerRadius(12)

                        Text(tips[tipIndex])
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(.black.opacity(0.25))
                            .cornerRadius(14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("PLAY")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.70))
                            .padding(.horizontal, 6)

                        VStack(spacing: 12) {
                            ForEach(GameMode.allCases) { mode in
                                Button {
                                    pendingMode = mode
                                    showNameSheet = true
                                } label: {
                                    ModeCard(mode: mode, isPulsing: pulse)
                                }
                                .buttonStyle(PressableCardStyle()) // ✅ ensures tap works
                            }
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Toggle(isOn: $shapeModeEnabled) {
                            Text("Shape Mode (Color + Shape)")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white.opacity(0.9)))
                        .padding(14)
                        .background(.black.opacity(0.22))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
                        .padding(.horizontal)

                        HStack(spacing: 12) {
                            Button {
                                path.append(.leaderboard)
                            } label: {
                                SmallMenuButton(title: "Leaderboard", icon: "trophy.fill")
                            }
                            .buttonStyle(.plain)

                            Button {
                                path.append(.howto)
                            } label: {
                                SmallMenuButton(title: "How to Play", icon: "questionmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 8)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            }
            .onReceive(tipTicker) { _ in
                withAnimation(.easeInOut(duration: 0.25)) { tipIndex = (tipIndex + 1) % tips.count }
            }
            .sheet(isPresented: $showNameSheet) {
                NameEntrySheet(
                    playerName: $playerName,
                    selectedMode: pendingMode?.title ?? "",
                    onStart: {
                        let safe = safeName(playerName)
                        if let m = pendingMode {
                            path.append(.game(mode: m, shapeMode: shapeModeEnabled, name: safe))
                        }
                        pendingMode = nil
                        showNameSheet = false
                    },
                    onCancel: {
                        pendingMode = nil
                        showNameSheet = false
                    }
                )
                .presentationDetents([.medium])
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .game(mode, shapeMode, name):
                    GameView(mode: mode, shapeModeEnabled: shapeMode, initialPlayerName: name)
                case .leaderboard:
                    LeaderboardView()
                case .howto:
                    HowToPlayView()
                }
            }
        }
    }

    private func safeName(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Player" : t
    }
}

// MARK: - Sheets / Menu UI

struct NameEntrySheet: View {
    @Binding var playerName: String
    let selectedMode: String
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.sRGB, red: 0.10, green: 0.15, blue: 0.25, opacity: 1),
                         Color(.sRGB, red: 0.20, green: 0.30, blue: 0.45, opacity: 1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Start Game")
                    .font(.title2.weight(.heavy))
                    .foregroundColor(.white)

                Text("Mode: \(selectedMode)")
                    .foregroundColor(.white.opacity(0.85))

                TextField("Your name (optional)", text: $playerName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 6)

                HStack(spacing: 12) {
                    Button("Cancel") { onCancel() }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.25))
                        .cornerRadius(12)
                        .foregroundColor(.white)

                    Button("Start") { onStart() }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.25))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                }
                .padding(.top, 6)

                Spacer()
            }
            .padding()
        }
    }
}

struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ModeCard: View {
    let mode: GameMode
    let isPulsing: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(mode.accent.opacity(0.22))
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(mode.accent.opacity(0.35), lineWidth: 1))

                Image(systemName: icon(for: mode))
                    .foregroundColor(.white.opacity(0.95))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Play \(mode.title)")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("\(mode.subtitle) • \(mode.roundTime)s • Session \(mode.sessionSeconds)s")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.82))

                Text(mode.tip)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.70))
                    .lineLimit(1)
            }

            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.white.opacity(0.75))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.black.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(mode.accent.opacity(0.35), lineWidth: 1))
        )
        .shadow(radius: 2)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(mode.accent.opacity(0.9))
                .frame(width: 8, height: 8)
                .padding(12)
                .opacity(isPulsing ? 0.9 : 0.7)
        }
    }

    private func icon(for mode: GameMode) -> String {
        switch mode {
        case .easy: return "sparkles"
        case .moderate: return "bolt.fill"
        case .hard: return "flame.fill"
        }
    }
}

struct SmallMenuButton: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(.white)
            Text(title).foregroundColor(.white).fontWeight(.semibold)
            Spacer()
        }
        .padding(14)
        .background(.black.opacity(0.22))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - Game

struct GameView: View {
    let mode: GameMode
    let shapeModeEnabled: Bool
    let initialPlayerName: String

    @EnvironmentObject private var leaderboard: LeaderboardStore

    struct Tile: Identifiable {
        let id = UUID()
        let color: Color
        let shape: TileShape
    }

    @State private var tiles: [Tile] = []
    @State private var targetColor: Color = .red
    @State private var targetShape: TileShape = .circle

    @State private var score = 0
    @State private var streak = 0

    @State private var roundEnd: Date = Date()
    @State private var timeLeft = 0

    @State private var sessionEnd: Date = Date()
    @State private var sessionLeft = 0

    private let ticker = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    @State private var showConfetti = false
    @State private var showWrong = false

    struct BigPopup: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String
        let emoji: String
        let accent: Color
    }
    @State private var popup: BigPopup? = nil

    @State private var gameEnded = false
    @State private var showSaveSheet = false
    @State private var playerName = ""

    private var roundProgress: Double {
        guard mode.roundTime > 0 else { return 0 }
        return max(0, min(1, Double(timeLeft) / Double(mode.roundTime)))
    }

    private var sessionProgress: Double {
        guard mode.sessionSeconds > 0 else { return 0 }
        return max(0, min(1, Double(sessionLeft) / Double(mode.sessionSeconds)))
    }

    var body: some View {
        ZStack {
            GalaxyBackgroundView()

            VStack(spacing: 14) {
                header
                targetPreview
                grid
                Spacer(minLength: 8)
            }
            .padding()

            if showConfetti { ConfettiView().transition(.opacity) }
            if let popup { BigPopupView(popup: popup).transition(.scale.combined(with: .opacity)).zIndex(20) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            playerName = initialPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
            startSession()
            startRound(resetTimer: true)
        }
        .onReceive(ticker) { _ in
            guard !gameEnded else { return }

            timeLeft = max(0, Int(ceil(roundEnd.timeIntervalSinceNow)))
            if timeLeft == 0 {
                streak = 0
                haptic(false)
                showPopup("Time’s Up!", "Round restarted — keep going!", "⏳", mode.accent)
                startRound(resetTimer: true)
            }

            sessionLeft = max(0, Int(ceil(sessionEnd.timeIntervalSinceNow)))
            if sessionLeft == 0 {
                endGame()
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            SaveScoreSheet(
                name: $playerName,
                score: score,
                mode: mode,
                onSave: {
                    leaderboard.upsertBestScore(name: playerName, score: score, mode: mode)
                    showSaveSheet = false
                },
                onSkip: { showSaveSheet = false }
            )
            .presentationDetents([.medium])
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("ColorNova")
                .font(.largeTitle.weight(.heavy))
                .foregroundColor(.white)
                .shadow(radius: 4)

            Text("\(mode.title) • \(mode.subtitle)")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(.black.opacity(0.22))
                .cornerRadius(10)

            HStack(spacing: 10) {
                statPill("Score: \(score)")
                if streak >= 2 { statPill("🔥 \(streak)") }
                statPill("Round ⏳ \(timeLeft)s")
            }

            TimerProgressBar(progress: roundProgress).frame(height: 10)

            HStack {
                Text("Session")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.80))
                Spacer()
                Text("\(sessionLeft)s left")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.80))
            }
            TimerProgressBar(progress: sessionProgress).frame(height: 10)
        }
    }

    private func statPill(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(.black.opacity(0.35))
            .cornerRadius(12)
    }

    private var targetPreview: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.black.opacity(0.20))
                    .frame(width: 120, height: 120)

                if shapeModeEnabled {
                    targetShape.view(color: targetColor)
                        .frame(width: 72, height: 72)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(targetColor)
                        .frame(width: 90, height: 90)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.22), lineWidth: 2))

            Text(shapeModeEnabled ? "Match color + shape" : "Match this color")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.vertical, 6)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: mode.gridSize),
            spacing: 12
        ) {
            ForEach(tiles) { tile in
                TileView(
                    tile: tile,
                    shapeModeEnabled: shapeModeEnabled,
                    isWrong: showWrong && !isCorrect(tile),
                    action: { tileTapped(tile) }
                )
            }
        }
    }

    private func startSession() {
        gameEnded = false
        sessionEnd = Date().addingTimeInterval(Double(mode.sessionSeconds))
        sessionLeft = mode.sessionSeconds
    }

    private func startRound(resetTimer: Bool) {
        showWrong = false

        if resetTimer {
            roundEnd = Date().addingTimeInterval(Double(mode.roundTime))
            timeLeft = mode.roundTime
        }

        let gridCount = mode.gridSize * mode.gridSize
        var palette = generateDistinctColors(count: max(gridCount + 12, 90))
        palette.shuffle()

        targetColor = palette.removeFirst()
        targetShape = TileShape.allCases.randomElement() ?? .circle

        let correctIndex = Int.random(in: 0..<gridCount)
        tiles = (0..<gridCount).map { i in
            let color = (i == correctIndex) ? targetColor : palette.removeFirst()

            let shape: TileShape
            if shapeModeEnabled {
                if i == correctIndex {
                    shape = targetShape
                } else {
                    var s = TileShape.allCases.randomElement() ?? .circle
                    if color == targetColor && s == targetShape {
                        s = TileShape.allCases.filter { $0 != targetShape }.randomElement() ?? .diamond
                    }
                    shape = s
                }
            } else {
                shape = .circle
            }

            return Tile(color: color, shape: shape)
        }
    }

    private func generateDistinctColors(count: Int) -> [Color] {
        (0..<count).map { i in
            Color(
                hue: Double(i) / Double(count),
                saturation: Double.random(in: 0.70...0.95),
                brightness: Double.random(in: 0.75...0.95)
            )
        }
    }

    private func isCorrect(_ tile: Tile) -> Bool {
        shapeModeEnabled
        ? (tile.color == targetColor && tile.shape == targetShape)
        : (tile.color == targetColor)
    }

    private func tileTapped(_ tile: Tile) {
        guard !gameEnded else { return }

        if isCorrect(tile) {
            var gained = 1

            let elapsed = mode.roundTime - timeLeft
            if elapsed <= 2 { gained += 3; showPopup("Speed Bonus!", "+3 Points", "⚡️", mode.accent) }
            else if elapsed <= 5 { gained += 2; showPopup("Quick Bonus!", "+2 Points", "⚡️", mode.accent) }

            streak += 1
            if streak == 3 { gained += 2; showPopup("Streak!", "+2 Points", "🔥", mode.accent) }
            else if streak == 5 { gained += 5; showPopup("HOT STREAK!", "+5 Points", "🔥", mode.accent) }

            score += gained

            showConfetti = true
            haptic(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showConfetti = false }

            startRound(resetTimer: true)
        } else {
            showWrong = true
            streak = 0
            haptic(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showWrong = false }
        }
    }

    private func endGame() {
        gameEnded = true
        let (rank, msg, emoji) = rankMessage(for: score)
        showPopup(rank, msg, emoji, mode.accent)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showSaveSheet = true
        }
    }

    private func rankMessage(for score: Int) -> (String, String, String) {
        switch score {
        case 0...9:   return ("Rookie", "Nice start — try a faster scan pattern!", "🌱")
        case 10...24: return ("Explorer", "Solid! You’re getting the hang of it.", "🛰️")
        case 25...44: return ("Star Runner", "Great speed — keep that streak alive!", "🌟")
        case 45...69: return ("Nova Pro", "🔥 That was impressive!", "🚀")
        default:      return ("Galaxy Legend", "WOW. Absolute top-tier reaction time.", "👑")
        }
    }

    private func showPopup(_ title: String, _ subtitle: String, _ emoji: String, _ accent: Color) {
        let newPopup = BigPopup(title: title, subtitle: subtitle, emoji: emoji, accent: accent)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { popup = newPopup }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) { if popup == newPopup { popup = nil } }
        }
    }

    private func haptic(_ success: Bool) {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(success ? .success : .error)
    }
}

struct SaveScoreSheet: View {
    @Binding var name: String
    let score: Int
    let mode: GameMode
    let onSave: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.sRGB, red: 0.10, green: 0.15, blue: 0.25, opacity: 1),
                         Color(.sRGB, red: 0.20, green: 0.30, blue: 0.45, opacity: 1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Game Over")
                    .font(.title2.weight(.heavy))
                    .foregroundColor(.white)

                Text("Score: \(score) • \(mode.title)")
                    .foregroundColor(.white.opacity(0.85))

                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button("Skip") { onSkip() }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.25))
                        .cornerRadius(12)
                        .foregroundColor(.white)

                    Button("Save to Leaderboard") { onSave() }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.25))
                        .cornerRadius(12)
                        .foregroundColor(.white)
                }
                .padding(.top, 6)

                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Leaderboard

struct LeaderboardView: View {
    @EnvironmentObject private var leaderboard: LeaderboardStore
    @State private var filter: GameMode? = nil

    var body: some View {
        ZStack {
            GalaxyBackgroundView()

            VStack(spacing: 14) {
                Text("🏆 Leaderboard")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundColor(.white)

                HStack(spacing: 10) {
                    filterPill("All", active: filter == nil) { filter = nil }
                    ForEach(GameMode.allCases) { m in
                        filterPill(m.title, active: filter == m) { filter = m }
                    }
                }

                let rows = leaderboard.top(for: filter)
                if rows.isEmpty {
                    Text("No scores yet.\nPlay a game and save your score at the end!")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.top, 18)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, item in
                                HStack {
                                    Text("#\(idx + 1)")
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.85))
                                        .frame(width: 42, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.headline).foregroundColor(.white)
                                        Text(item.mode.title).font(.footnote).foregroundColor(.white.opacity(0.75))
                                    }

                                    Spacer()

                                    Text("\(item.score)")
                                        .font(.title3.weight(.heavy))
                                        .foregroundColor(.white)
                                }
                                .padding(14)
                                .background(.black.opacity(0.22))
                                .cornerRadius(14)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
                            }
                        }
                        .padding(.top, 6)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func filterPill(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.black.opacity(active ? 0.45 : 0.22))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(active ? 0.25 : 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - How To Play (with mini tutorial)

struct HowToPlayView: View {
    @State private var demoShapeMode = false

    var body: some View {
        ZStack {
            GalaxyBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("How to Play")
                        .font(.largeTitle.weight(.heavy))
                        .foregroundColor(.white)
                        .padding(.top, 10)

                    tipCard("Goal", "Tap the tile that matches the target shown above the grid.")
                    tipCard("Timer", "Each correct match resets the round timer. If it hits zero, the round restarts.")
                    tipCard("Session", "The full session timer counts down. When it ends, the game ends.")
                    tipCard("Bonuses", "⚡️ Speed bonus if you tap fast\n🔥 Streak bonus at 3 and 5 correct taps in a row")
                    tipCard("Shape Mode", "When enabled, you must match BOTH color and shape.")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tutorial Preview")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)

                        Toggle(isOn: $demoShapeMode) {
                            Text("Demo Shape Mode")
                                .foregroundColor(.white)
                                .font(.headline)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .white.opacity(0.9)))
                        .padding(12)
                        .background(.black.opacity(0.22))
                        .cornerRadius(14)

                        TutorialMiniGame(shapeMode: demoShapeMode)
                            .padding(.vertical, 4)
                    }
                    .padding(14)
                    .background(.black.opacity(0.18))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))

                    Spacer(minLength: 18)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tipCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundColor(.white)
            Text(body).font(.subheadline).foregroundColor(.white.opacity(0.85))
        }
        .padding(14)
        .background(.black.opacity(0.22))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

struct TutorialMiniGame: View {
    let shapeMode: Bool

    struct DemoTile: Identifiable {
        let id = UUID()
        let color: Color
        let shape: TileShape
        let isCorrect: Bool
    }

    @State private var tiles: [DemoTile] = []
    @State private var targetColor: Color = .red
    @State private var targetShape: TileShape = .circle
    @State private var message: String = "Tap the matching tile!"

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.22))
                    if shapeMode {
                        targetShape.view(color: targetColor).padding(14)
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(targetColor).padding(14)
                    }
                }
                .frame(width: 74, height: 74)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.20), lineWidth: 1))

                Text(message)
                    .foregroundColor(.white.opacity(0.9))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(tiles) { t in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(t.color)
                        if shapeMode {
                            t.shape.view(color: .white.opacity(0.85))
                                .frame(width: 22, height: 22)
                                .blendMode(.overlay)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .onTapGesture {
                        if t.isCorrect {
                            message = "✅ Perfect! New target..."
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                newBoard()
                                message = "Tap the matching tile!"
                            }
                        } else {
                            message = "❌ Close! Try again."
                        }
                    }
                }
            }
        }
        .onAppear { newBoard() }
        .onChange(of: shapeMode) { _ in newBoard() }
    }

    private func newBoard() {
        var palette: [Color] = (0..<30).map {
            Color(hue: Double($0) / 30.0,
                  saturation: Double.random(in: 0.70...0.95),
                  brightness: Double.random(in: 0.75...0.95))
        }
        palette.shuffle()

        targetColor = palette.removeFirst()
        targetShape = TileShape.allCases.randomElement() ?? .circle

        let correctIndex = Int.random(in: 0..<9)
        tiles = (0..<9).map { i in
            let color = (i == correctIndex) ? targetColor : palette.removeFirst()
            let shape: TileShape = shapeMode
                ? ((i == correctIndex) ? targetShape : (TileShape.allCases.randomElement() ?? .diamond))
                : .circle
            return DemoTile(color: color, shape: shape, isCorrect: i == correctIndex)
        }
    }
}

// MARK: - Shared UI Components

struct TileView: View {
    let tile: GameView.Tile
    let shapeModeEnabled: Bool
    let isWrong: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(tile.color)
                .shadow(radius: 4)

            if shapeModeEnabled {
                tile.shape.view(color: Color.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .blendMode(.overlay)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isWrong ? Color.red : Color.clear, lineWidth: 3))
        .scaleEffect(isWrong ? 1.06 : 1.0)
        .animation(.easeInOut(duration: 0.16), value: isWrong)
        .onTapGesture { action() }
    }
}

struct TimerProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule()
                    .fill(.white.opacity(0.75))
                    .frame(width: max(0, geo.size.width * progress))
                    .animation(.linear(duration: 0.15), value: progress)
                Capsule().stroke(.white.opacity(0.25), lineWidth: 1)
            }
        }
        .frame(height: 10)
    }
}

struct BigPopupView: View {
    let popup: GameView.BigPopup
    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                Text(popup.emoji).font(.system(size: 44))
                Text(popup.title)
                    .font(.title2.weight(.heavy))
                    .foregroundColor(.white)
                Text(popup.subtitle)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(.black.opacity(0.45))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(popup.accent.opacity(0.65), lineWidth: 2))
                    .shadow(radius: 8)
            )
            .padding(.bottom, 80)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

struct ConfettiView: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            ForEach(0..<30, id: \.self) { _ in
                Rectangle()
                    .fill([Color.blue, Color.white, Color.purple, Color.cyan].randomElement()!)
                    .frame(width: 6, height: 12)
                    .rotationEffect(.degrees(Double.random(in: 0...360)))
                    .offset(x: CGFloat.random(in: -150...150), y: animate ? 600 : -300)
                    .animation(.linear(duration: Double.random(in: 1.0...1.5)), value: animate)
            }
        }
        .onAppear { animate = true }
        .allowsHitTesting(false)
    }
}

// MARK: - Background (your name)

struct GalaxyBackgroundView: View {
    @State private var animateStars = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.sRGB, red: 0.10, green: 0.15, blue: 0.25, opacity: 1),
                    Color(.sRGB, red: 0.20, green: 0.30, blue: 0.45, opacity: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    ForEach(0..<100, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(Double.random(in: 0.10...0.55)))
                            .frame(width: CGFloat.random(in: 2...6), height: CGFloat.random(in: 2...6))
                            .position(
                                x: CGFloat.random(in: 0...geo.size.width),
                                y: animateStars ? CGFloat.random(in: 0...geo.size.height)
                                                : CGFloat.random(in: 0...geo.size.height)
                            )
                            .animation(.linear(duration: Double.random(in: 3...6)).repeatForever(autoreverses: true),
                                       value: animateStars)
                    }
                }
            }
        }
        .onAppear { animateStars = true }
    }
}

// MARK: - Shapes

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

struct StarShape: Shape {
    let points: Int
    let innerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * innerRatio

        var path = Path()
        let step = .pi * 2 / CGFloat(points * 2)
        var angle: CGFloat = -.pi / 2

        var first = true
        for i in 0..<(points * 2) {
            let r = (i % 2 == 0) ? outerR : innerR
            let pt = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if first { path.move(to: pt); first = false }
            else { path.addLine(to: pt) }
            angle += step
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ContentView()
        .environmentObject(LeaderboardStore())
}
