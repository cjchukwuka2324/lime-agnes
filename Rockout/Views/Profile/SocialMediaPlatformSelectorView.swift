import SwiftUI

struct SocialMediaPlatformSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (SocialMediaPlatform) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    Text("Select Social Media")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    VStack(spacing: 12) {
                        socialMediaOption(.instagram)
                        socialMediaOption(.twitter)
                        socialMediaOption(.tiktok)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                }
            }
            .navigationTitle("Add Social Media")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private func socialMediaOption(_ platform: SocialMediaPlatform) -> some View {
        Button {
            onSelect(platform)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: platform.iconName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(platform.color.opacity(0.3))
                    )
                
                Text(platform.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
    }
}


