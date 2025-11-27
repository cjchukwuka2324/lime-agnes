import SwiftUI

struct ListeningStatsView: View {
    let stats: ListeningStats
    let audioFeatures: AverageAudioFeatures
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Total Listening Time
                StatCardLarge(
                    title: "Total Listening Time",
                    value: formatTime(stats.totalListeningTimeMinutes),
                    icon: "clock.fill",
                    color: Color(red: 0.12, green: 0.72, blue: 0.33)
                )
                
                // Streaks
                HStack(spacing: 16) {
                    StatCard(
                        title: "Current Streak",
                        value: "\(stats.currentStreak) days",
                        icon: "flame.fill",
                        color: Color.orange
                    )
                    StatCard(
                        title: "Longest Streak",
                        value: "\(stats.longestStreak) days",
                        icon: "star.fill",
                        color: Color.yellow
                    )
                }
                
                // Active Times
                VStack(alignment: .leading, spacing: 16) {
                    Text("Most Active Times")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Day")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Text(stats.mostActiveDay)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hour")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                            Text("\(stats.mostActiveHour):00")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                
                // Discovery Stats
                HStack(spacing: 16) {
                    StatCard(
                        title: "New Songs",
                        value: "\(stats.songsDiscoveredThisMonth)",
                        icon: "sparkles",
                        color: Color.purple
                    )
                    StatCard(
                        title: "New Artists",
                        value: "\(stats.artistsDiscoveredThisMonth)",
                        icon: "person.2.fill",
                        color: Color.blue
                    )
                }
                
                // Audio Features Radar
                AudioFeaturesRadarChart(features: audioFeatures)
                    .frame(height: 300)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.1))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
    
    private func formatTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

struct StatCardLarge: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(color)
                .frame(width: 60, height: 60)
                .background(
                    Circle()
                        .fill(color.opacity(0.2))
                )
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct AudioFeaturesRadarChart: View {
    let features: AverageAudioFeatures
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Features")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                FeatureBar(label: "Danceability", value: features.danceability, color: .green)
                FeatureBar(label: "Energy", value: features.energy, color: .orange)
                FeatureBar(label: "Valence", value: features.valence, color: .yellow)
                FeatureBar(label: "Tempo", value: features.tempo / 200.0, color: .red) // Normalized
                FeatureBar(label: "Acousticness", value: features.acousticness, color: .blue)
                FeatureBar(label: "Instrumentalness", value: features.instrumentalness, color: .purple)
            }
        }
    }
}

struct FeatureBar: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value), height: 8)
                        .cornerRadius(4)
                }
            }
            .frame(height: 8)
        }
    }
}

