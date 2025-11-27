import SwiftUI

struct AdvancedAnalyticsView: View {
    let diversity: MusicTasteDiversity
    let audioFeatures: AverageAudioFeatures
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Diversity Score
                DiversityScoreCard(diversity: diversity)
                
                // Audio Features Radar
                AudioFeaturesRadarView(features: audioFeatures)
                
                // Exploration Metrics
                ExplorationMetricsCard(diversity: diversity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct DiversityScoreCard: View {
    let diversity: MusicTasteDiversity
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Music Taste Diversity")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 12)
                    .frame(width: 150, height: 150)
                
                Circle()
                    .trim(from: 0, to: CGFloat(diversity.score / 100))
                    .stroke(
                        LinearGradient(
                            colors: [Color(red: 0.12, green: 0.72, blue: 0.33), Color(red: 0.18, green: 0.80, blue: 0.44)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(Int(diversity.score))")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    Text("Score")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            HStack(spacing: 30) {
                VStack {
                    Text("\(diversity.genreCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Genres")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                VStack {
                    Text("\(diversity.artistCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Artists")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                VStack {
                    Text("\(Int(diversity.explorationDepth))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Depth")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct AudioFeaturesRadarView: View {
    let features: AverageAudioFeatures
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Features Analysis")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            // Simple radar visualization using bars
            VStack(spacing: 12) {
                FeatureBar(label: "Danceability", value: features.danceability, color: .green)
                FeatureBar(label: "Energy", value: features.energy, color: .orange)
                FeatureBar(label: "Valence", value: features.valence, color: .yellow)
                FeatureBar(label: "Acousticness", value: features.acousticness, color: .blue)
                FeatureBar(label: "Instrumentalness", value: features.instrumentalness, color: .purple)
                FeatureBar(label: "Liveness", value: features.liveness, color: .pink)
                FeatureBar(label: "Speechiness", value: features.speechiness, color: .cyan)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct ExplorationMetricsCard: View {
    let diversity: MusicTasteDiversity
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exploration Metrics")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                MetricRow(label: "Genre Diversity", value: "\(diversity.genreCount) genres")
                MetricRow(label: "Artist Range", value: "\(diversity.artistCount) artists")
                MetricRow(label: "Exploration Depth", value: "\(Int(diversity.explorationDepth))%")
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
}

