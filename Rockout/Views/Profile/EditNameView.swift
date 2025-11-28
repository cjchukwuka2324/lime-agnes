import SwiftUI

struct EditNameView: View {
    @Environment(\.dismiss) private var dismiss
    private let profileService = UserProfileService.shared
    
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var isLoading = false
    @State private var message: String?
    @State private var isLoadingProfile = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated gradient background matching Settings
                AnimatedGradientBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        if isLoadingProfile {
                            ProgressView()
                                .tint(.white)
                                .padding(.top, 40)
                        } else {
                            VStack(spacing: 20) {
                                Text("Update Your Name")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.top, 20)
                                
                                VStack(spacing: 16) {
                                    TextField("First Name", text: $firstName)
                                        .textFieldStyle(.plain)
                                        .padding()
                                        .background(Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                    
                                    TextField("Last Name", text: $lastName)
                                        .textFieldStyle(.plain)
                                        .padding()
                                        .background(Color.white.opacity(0.1))
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                    
                                    if let message = message {
                                        Text(message)
                                            .foregroundColor(message.contains("success") || message.contains("updated") ? .green : .red)
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal)
                                    }
                                    
                                    Button(action: updateName) {
                                        if isLoading {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Text("Update Name")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        (firstName.isEmpty || lastName.isEmpty) ?
                                        Color.white.opacity(0.2) :
                                        Color.green.opacity(0.8)
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                    .disabled(isLoading || firstName.isEmpty || lastName.isEmpty)
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
                firstName = profile.firstName ?? ""
                lastName = profile.lastName ?? ""
            }
        } catch {
            message = "Failed to load profile: \(error.localizedDescription)"
        }
    }
    
    private func updateName() {
        guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
              !lastName.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = "Please enter both first and last name"
            return
        }
        
        Task {
            isLoading = true
            defer { isLoading = false }
            
            do {
                try await profileService.updateName(
                    firstName: firstName.trimmingCharacters(in: .whitespaces),
                    lastName: lastName.trimmingCharacters(in: .whitespaces)
                )
                message = "Name updated successfully"
                
                // Dismiss after a short delay
                try? await Task.sleep(for: .milliseconds(800))
                dismiss()
            } catch {
                message = "Failed to update name: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    EditNameView()
}

