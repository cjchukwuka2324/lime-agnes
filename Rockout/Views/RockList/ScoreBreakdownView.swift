import SwiftUI

struct ScoreBreakdownView: View {
    let userId: UUID
    let userName: String
    let artistId: String
    let artistName: String
    let rank: Int
    let currentScore: Double
    
    @StateObject private var viewModel: ScoreBreakdownViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(userId: UUID, userName: String, artistId: String, artistName: String, rank: Int, currentScore: Double) {
        self.userId = userId
        self.userName = userName
        self.artistId = artistId
        self.artistName = artistName
        self.rank = rank
        self.currentScore = currentScore
        self._viewModel = StateObject(wrappedValue: ScoreBreakdownViewModel(userId: userId, artistId: artistId))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated gradient background
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading score breakdown...")
                            .foregroundColor(.white.opacity(0.8))
                    }
                } else if let error = viewModel.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Retry") {
                            Task {
                                await viewModel.loadBreakdown()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if let breakdown = viewModel.breakdown {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            headerSection(breakdown: breakdown)
                            
                            // Score Summary
                            scoreSummarySection(breakdown: breakdown)
                            
                            // Individual Index Cards
                            indexCardsSection(breakdown: breakdown)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Score Breakdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await viewModel.loadBreakdown()
            }
        }
    }
    
    // MARK: - Header Section
    
    private func headerSection(breakdown: ListenerScoreBreakdown) -> some View {
        VStack(spacing: 12) {
            Text("#\(rank)")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.white)
            
            Text(userName)
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text(artistName)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            Text("Total Score: \(formatScore(breakdown.listenerScore))")
                .font(.title3.bold())
                .foregroundColor(Color(hex: "#1ED760"))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassMorphism()
    }
    
    // MARK: - Score Summary Section
    
    private func scoreSummarySection(breakdown: ListenerScoreBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Score Components")
                .font(.headline)
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                indexSummaryRow(
                    name: "Stream Index",
                    value: breakdown.streamIndex.value,
                    weight: breakdown.streamIndex.weight,
                    contribution: breakdown.streamIndex.contribution
                )
                
                indexSummaryRow(
                    name: "Duration Index",
                    value: breakdown.durationIndex.value,
                    weight: breakdown.durationIndex.weight,
                    contribution: breakdown.durationIndex.contribution
                )
                
                indexSummaryRow(
                    name: "Completion Index",
                    value: breakdown.completionIndex.value,
                    weight: breakdown.completionIndex.weight,
                    contribution: breakdown.completionIndex.contribution
                )
                
                indexSummaryRow(
                    name: "Recency Index",
                    value: breakdown.recencyIndex.value,
                    weight: breakdown.recencyIndex.weight,
                    contribution: breakdown.recencyIndex.contribution
                )
                
                indexSummaryRow(
                    name: "Engagement Index",
                    value: breakdown.engagementIndex.value,
                    weight: breakdown.engagementIndex.weight,
                    contribution: breakdown.engagementIndex.contribution
                )
                
                indexSummaryRow(
                    name: "Fan Spread Index",
                    value: breakdown.fanSpreadIndex.value,
                    weight: breakdown.fanSpreadIndex.weight,
                    contribution: breakdown.fanSpreadIndex.contribution
                )
            }
        }
        .padding(20)
        .glassMorphism()
    }
    
    private func indexSummaryRow(name: String, value: Double, weight: Double, contribution: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                
                Text("\(Int(weight * 100))% weight")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(formatScore(contribution))")
                    .font(.subheadline.bold())
                    .foregroundColor(Color(hex: "#1ED760"))
                
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    // MARK: - Index Cards Section
    
    private func indexCardsSection(breakdown: ListenerScoreBreakdown) -> some View {
        VStack(spacing: 16) {
            Text("Detailed Breakdown")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            indexCard(
                title: "Stream Index",
                subtitle: "\(Int(breakdown.streamIndex.weight * 100))% weight",
                index: breakdown.streamIndex,
                rawData: breakdown.streamIndex.raw
            )
            
            indexCard(
                title: "Duration Index",
                subtitle: "\(Int(breakdown.durationIndex.weight * 100))% weight",
                index: breakdown.durationIndex,
                rawData: breakdown.durationIndex.raw
            )
            
            indexCard(
                title: "Completion Index",
                subtitle: "\(Int(breakdown.completionIndex.weight * 100))% weight",
                index: breakdown.completionIndex,
                rawData: breakdown.completionIndex.raw
            )
            
            indexCard(
                title: "Recency Index",
                subtitle: "\(Int(breakdown.recencyIndex.weight * 100))% weight",
                index: breakdown.recencyIndex,
                rawData: breakdown.recencyIndex.raw
            )
            
            indexCard(
                title: "Engagement Index",
                subtitle: "\(Int(breakdown.engagementIndex.weight * 100))% weight",
                index: breakdown.engagementIndex,
                rawData: breakdown.engagementIndex.raw
            )
            
            indexCard(
                title: "Fan Spread Index",
                subtitle: "\(Int(breakdown.fanSpreadIndex.weight * 100))% weight",
                index: breakdown.fanSpreadIndex,
                rawData: breakdown.fanSpreadIndex.raw
            )
        }
    }
    
    private func indexCard(title: String, subtitle: String, index: ScoreIndex, rawData: RawData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(formatScore(index.contribution))")
                        .font(.title3.bold())
                        .foregroundColor(Color(hex: "#1ED760"))
                    
                    Text("\(Int(index.value * 100))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(Color(hex: "#1ED760"))
                        .frame(width: geometry.size.width * CGFloat(index.value), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
            
            // Raw data display
            rawDataView(rawData: rawData, indexType: title)
        }
        .padding(16)
        .glassMorphism()
    }
    
    @ViewBuilder
    private func rawDataView(rawData: RawData, indexType: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch indexType {
            case "Stream Index":
                if let streamCount = rawData.streamCount, let maxCount = rawData.maxStreamCount {
                    HStack {
                        Text("Streams:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(formatNumber(streamCount)) / \(formatNumber(maxCount))")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                    }
                }
                
            case "Duration Index":
                if let minutes = rawData.totalMinutes, let maxMinutes = rawData.maxMinutes {
                    HStack {
                        Text("Listening Time:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(formatMinutes(minutes)) / \(formatMinutes(maxMinutes))")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                    }
                }
                
            case "Completion Index":
                if let completion = rawData.avgCompletionRate {
                    HStack {
                        Text("Avg Completion:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(Int(completion * 100))%")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                    }
                }
                
            case "Recency Index":
                if let days = rawData.daysSinceLastListen {
                    HStack {
                        Text("Days Since Last Listen:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(Int(days)) days")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                    }
                }
                
            case "Engagement Index":
                VStack(alignment: .leading, spacing: 4) {
                    if let raw = rawData.engagementRaw, let maxRaw = rawData.maxEngagementRaw {
                        HStack {
                            Text("Engagement Score:")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Text("\(raw) / \(maxRaw)")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                        }
                    }
                    
                    if let saves = rawData.albumSaves, let likes = rawData.trackLikes, let adds = rawData.playlistAdds {
                        HStack(spacing: 12) {
                            Label("\(saves)", systemImage: "square.and.arrow.down")
                            Label("\(likes)", systemImage: "heart")
                            Label("\(adds)", systemImage: "music.note.list")
                        }
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                    }
                }
                
            case "Fan Spread Index":
                if let unique = rawData.uniqueTracks, let total = rawData.totalTracks {
                    HStack {
                        Text("Tracks Listened:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(unique) / \(total)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                    }
                }
                
            default:
                EmptyView()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatScore(_ score: Double) -> String {
        String(format: "%.1f", score)
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func formatMinutes(_ minutes: Double) -> String {
        if minutes >= 60 {
            let hours = Int(minutes / 60)
            let mins = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(hours)h \(mins)m"
        } else {
            return "\(Int(minutes))m"
        }
    }
}

// MARK: - View Model

@MainActor
final class ScoreBreakdownViewModel: ObservableObject {
    @Published var breakdown: ListenerScoreBreakdown?
    @Published var isLoading = false
    @Published var error: String?
    
    private let userId: UUID
    private let artistId: String
    private let service = RockListService.shared
    
    init(userId: UUID, artistId: String) {
        self.userId = userId
        self.artistId = artistId
    }
    
    func loadBreakdown() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            breakdown = try await service.getScoreBreakdown(
                userId: userId,
                artistId: artistId
            )
        } catch {
            self.error = error.localizedDescription
            print("❌ Failed to load score breakdown: \(error.localizedDescription)")
        }
    }
}

