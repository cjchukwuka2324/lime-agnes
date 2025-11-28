import SwiftUI

struct EditSocialMediaView: View {
    @Environment(\.dismiss) private var dismiss
    private let profileService = UserProfileService.shared
    
    let platform: SocialMediaPlatform
    
    @State private var handle = ""
    @State private var isLoading = false
    @State private var isLoadingProfile = false
    @State private var message: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Solid black background
                Color.black
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Instructions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add \(platform.name) Handle")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Enter your \(platform.name) username to link your profile. Users can tap the button to visit your \(platform.name) page.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Handle Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(platform.name) Username")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            HStack {
                                Text("@")
                                    .foregroundColor(.white.opacity(0.7))
                                    .font(.body)
                                
                                TextField("username", text: $handle)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.white.opacity(0.15))
                                    .cornerRadius(8)
                            }
                            
                            if let message = message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(message.contains("success") ? .green : .red)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Save Button
                        Button {
                            updateHandle()
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            handle.isEmpty
                                ? Color.gray.opacity(0.3)
                                : platform.color
                        )
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                        .disabled(handle.isEmpty || isLoading)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Edit \(platform.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .task {
                await loadProfile()
            }
        }
    }
    
    private func loadProfile() async {
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        
        do {
            if let profile = try await profileService.getCurrentUserProfile() {
                switch platform {
                case .instagram:
                    handle = profile.instagramHandle ?? ""
                case .twitter:
                    handle = profile.twitterHandle ?? ""
                case .tiktok:
                    handle = profile.tiktokHandle ?? ""
                }
            }
        } catch {
            message = "Failed to load profile: \(error.localizedDescription)"
        }
    }
    
    private func updateHandle() {
        let trimmedHandle = handle.trimmingCharacters(in: .whitespaces)
        
        guard !trimmedHandle.isEmpty else {
            message = "Please enter a handle"
            return
        }
        
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                try await profileService.updateSocialMediaHandle(platform: platform, handle: trimmedHandle)
                message = "\(platform.name) handle updated successfully"
                
                // Dismiss after a short delay
                try? await Task.sleep(for: .milliseconds(800))
                dismiss()
            } catch {
                message = "Failed to update handle: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    EditSocialMediaView(platform: .instagram)
}

