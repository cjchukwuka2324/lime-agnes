import SwiftUI

struct SocialSharingView: View {
    let profile: UnifiedUserProfile?
    let topArtists: [UnifiedArtist]
    let topTracks: [UnifiedTrack]
    let personality: FanPersonality?
    let compatibility: [TasteCompatibility]?
    
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Share SoundPrint Card
                ShareSoundPrintCard(
                    profile: profile,
                    personality: personality,
                    onShare: {
                        generateShareImage()
                        showShareSheet = true
                    }
                )
                
                // Taste Compatibility
                if let compat = compatibility, !compat.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Taste Compatibility")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        ForEach(compat, id: \.userId) { comp in
                            CompatibilityRow(compatibility: comp)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(activityItems: [image])
            }
        }
    }
    
    private func generateShareImage() {
        // Generate shareable image of SoundPrint
        // This would create a beautiful card with user's stats
        // For now, placeholder
    }
}

struct ShareSoundPrintCard: View {
    let profile: UnifiedUserProfile?
    let personality: FanPersonality?
    let onShare: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Share Your SoundPrint")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text("Show off your musical identity")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            Button {
                onShare()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share SoundPrint")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(16)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
    }
}

struct CompatibilityRow: View {
    let compatibility: TasteCompatibility
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(compatibility.userName)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(Int(compatibility.compatibilityScore))% match")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Spacer()
            
            // Compatibility score visual
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 6)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: CGFloat(compatibility.compatibilityScore / 100))
                    .stroke(Color(red: 0.12, green: 0.72, blue: 0.33), lineWidth: 6)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(compatibility.compatibilityScore))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .padding(.vertical, 12)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

