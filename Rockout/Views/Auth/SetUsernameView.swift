import SwiftUI

struct SetUsernameView: View {
    @EnvironmentObject var authVM: AuthViewModel
    private let profileService = UserProfileService.shared
    
    @State private var username = ""
    @State private var isLoading = false
    @State private var message: String?
    @State private var messageType: MessageType = .error
    @State private var isCheckingAvailability = false
    @State private var availabilityStatus: UsernameAvailabilityStatus = .none
    @State private var checkAvailabilityTask: Task<Void, Never>?
    
    var body: some View {
        ZStack {
            // Solid black background
            Color.black
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Logo and Title
                    VStack(spacing: 6) {
                        Image("authIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                        Text("RockOut")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose a username")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Your username will be displayed as @username throughout the app. It must be 3-20 characters and contain only letters, numbers, and underscores.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 20)
                    
                    // Username Input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Username")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        HStack {
                            Text("@")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.body)
                            
                            TextField("username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(8)
                                .onChange(of: username) { _, newValue in
                                    checkUsernameAvailability(newValue)
                                }
                        }
                        
                        // Username availability status
                        if availabilityStatus != .none {
                            HStack(spacing: 8) {
                                if isCheckingAvailability {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white.opacity(0.7))
                                    Text("Checking availability...")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                } else {
                                    Image(systemName: availabilityStatus == .available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(availabilityStatus == .available ? .green : .red)
                                        .font(.caption)
                                    Text(availabilityStatus == .available ? "Available" : "Already taken")
                                        .font(.caption)
                                        .foregroundColor(availabilityStatus == .available ? .green : .red)
                                }
                            }
                        }
                        
                        // Error/success message banner
                        if let message = message {
                            ErrorMessageBanner(message, type: messageType)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Continue Button
                    Button {
                        setUsername()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Continue")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        username.isEmpty || !isValidUsername(username) 
                            ? Color.gray.opacity(0.3) 
                            : Color(hex: "#1ED760")
                    )
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .disabled(username.isEmpty || !isValidUsername(username) || isLoading || availabilityStatus == .taken)
                    
                    Spacer()
                }
            }
        }
    }
    
    private func isValidUsername(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        let regex = "^[a-z0-9_]{3,20}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: trimmed)
    }
    
    enum UsernameAvailabilityStatus {
        case none
        case available
        case taken
        case checking
    }
    
    private func checkUsernameAvailability(_ input: String) {
        // Cancel previous check task
        checkAvailabilityTask?.cancel()
        
        let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Reset status if empty or invalid
        guard !trimmed.isEmpty else {
            availabilityStatus = .none
            message = nil
            return
        }
        
        guard isValidUsername(trimmed) else {
            availabilityStatus = .none
            message = nil
            return
        }
        
        // Debounce the check
        checkAvailabilityTask = Task {
            // Wait 500ms after user stops typing
            try? await Task.sleep(for: .milliseconds(500))
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                isCheckingAvailability = true
                availabilityStatus = .checking
            }
            
            do {
                // Use public method since user might not be fully authenticated yet
                let isAvailable = try await profileService.checkUsernameAvailabilityPublic(trimmed)
                
                // Check again if task was cancelled
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    isCheckingAvailability = false
                    availabilityStatus = isAvailable ? .available : .taken
                    message = nil // Clear any previous error messages
                }
            } catch {
                // Check again if task was cancelled
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    isCheckingAvailability = false
                    availabilityStatus = .none
                    // Don't show error for availability check failures - just reset status
                    print("⚠️ Username availability check failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func setUsername() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        
        guard !trimmedUsername.isEmpty else {
            message = "Please enter a username"
            messageType = .error
            return
        }
        
        guard isValidUsername(trimmedUsername) else {
            message = "Username must be 3-20 characters and contain only letters, numbers, and underscores"
            messageType = .error
            return
        }
        
        // Check availability status before updating
        if availabilityStatus == .taken {
            message = "This username (@\(trimmedUsername)) is already taken. Please choose another one."
            messageType = .error
            return
        }
        
        Task {
            isLoading = true
            message = nil // Clear previous messages
            defer { isLoading = false }
            
            do {
                try await profileService.updateUsername(trimmedUsername)
                message = "Username set successfully!"
                messageType = .success
                
                // Update username status in AuthViewModel
                await authVM.checkUsernameStatus()
                
                // Set flag to navigate to profile tab
                authVM.shouldShowProfile = true
                
                // Small delay to show success message
                try? await Task.sleep(for: .milliseconds(500))
            } catch {
                message = formatErrorMessage(error, username: trimmedUsername)
                messageType = .error
            }
        }
    }
    
    private func formatErrorMessage(_ error: Error, username: String) -> String {
        // Use the service's error formatting helper
        let baseMessage = profileService.formatSupabaseError(error, context: "set username")
        
        // Enhance username-specific errors with the @ symbol
        if baseMessage.contains("already taken") && !username.isEmpty {
            return "This username (@\(username)) is already taken. Please choose another one."
        }
        
        return baseMessage
    }
}

