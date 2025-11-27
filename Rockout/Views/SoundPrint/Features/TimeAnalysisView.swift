import SwiftUI

struct TimeAnalysisView: View {
    let yearInMusic: YearInMusic?
    let monthlyEvolution: [MonthlyEvolution]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                if let year = yearInMusic {
                    YearSummaryCard(year: year)
                }
                
                if !monthlyEvolution.isEmpty {
                    MonthlyEvolutionSection(evolution: monthlyEvolution)
                }
                
                FavoriteDecadeCard(decade: yearInMusic?.favoriteDecade ?? "2020s")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

struct YearSummaryCard: View {
    let year: YearInMusic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your \(year.year) in Music")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                StatRow(label: "Listening Time", value: formatTime(year.totalListeningTimeMinutes))
                StatRow(label: "Most Played Month", value: year.mostPlayedMonth)
                StatRow(label: "Favorite Decade", value: year.favoriteDecade)
            }
            
            if !year.topGenres.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Genres")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(year.topGenres.prefix(5), id: \.self) { genre in
                                Text(genre)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(12)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
    
    private func formatTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        return "\(hours) hours"
    }
}

struct MonthlyEvolutionSection: View {
    let evolution: [MonthlyEvolution]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Monthly Evolution")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            ForEach(evolution.prefix(6), id: \.month) { month in
                MonthlyCard(month: month)
            }
        }
    }
}

struct MonthlyCard: View {
    let month: MonthlyEvolution
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(month.month)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(month.listeningTimeMinutes / 60) hours")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            if !month.topGenres.isEmpty {
                Text(month.topGenres.first ?? "")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct FavoriteDecadeCard: View {
    let decade: String
    
    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .font(.system(size: 30))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.2))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Favorite Decade")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Text(decade)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
}

