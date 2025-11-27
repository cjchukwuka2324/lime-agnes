import SwiftUI

struct MoodContextView: View {
    let moodPlaylists: [MoodPlaylist]
    let timePatterns: [TimePattern]
    let seasonalTrends: [SeasonalTrend]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Mood Playlists
                if !moodPlaylists.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Mood Playlists")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        ForEach(moodPlaylists, id: \.mood) { playlist in
                            MoodPlaylistCard(playlist: playlist)
                        }
                    }
                }
                
                // Time Patterns
                if !timePatterns.isEmpty {
                    TimePatternsChart(patterns: timePatterns)
                }
                
                // Seasonal Trends
                if !seasonalTrends.isEmpty {
                    SeasonalTrendsSection(trends: seasonalTrends)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct MoodPlaylistCard: View {
    let playlist: MoodPlaylist
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(playlist.mood.capitalized)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(playlist.tracks.count) tracks")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Text(playlist.description)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct TimePatternsChart: View {
    let patterns: [TimePattern]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Listening Patterns")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                ForEach(patterns.sorted(by: { $0.hour < $1.hour }), id: \.hour) { pattern in
                    TimePatternRow(pattern: pattern, maxCount: patterns.map { $0.playCount }.max() ?? 1)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct TimePatternRow: View {
    let pattern: TimePattern
    let maxCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(pattern.hour):00")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 60, alignment: .leading)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 24)
                        .cornerRadius(12)
                    
                    Rectangle()
                        .fill(Color(red: 0.12, green: 0.72, blue: 0.33))
                        .frame(width: geometry.size.width * CGFloat(pattern.playCount) / CGFloat(maxCount), height: 24)
                        .cornerRadius(12)
                }
            }
            .frame(height: 24)
            
            Text("\(pattern.playCount)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 40, alignment: .trailing)
        }
    }
}

struct SeasonalTrendsSection: View {
    let trends: [SeasonalTrend]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Seasonal Trends")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            ForEach(trends, id: \.season) { trend in
                SeasonalTrendCard(trend: trend)
            }
        }
    }
}

struct SeasonalTrendCard: View {
    let trend: SeasonalTrend
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trend.season)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text("\(trend.listeningTimeMinutes / 60) hours")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            if !trend.topGenres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(trend.topGenres.prefix(5), id: \.self) { genre in
                            Text(genre)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(10)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
}

