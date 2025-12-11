import Foundation
import Supabase
import Combine
import SwiftUI

@MainActor
class UserProfileService: ObservableObject {
    static let shared = UserProfileService()
    
    private let supabase = SupabaseService.shared.client
    
    struct UserProfile: Codable {
        let id: UUID
        let displayName: String?
        let firstName: String?
        let lastName: String?
        let username: String?
        let instagramHandle: String?
        let twitterHandle: String?
        let tiktokHandle: String?
        let profilePictureURL: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case firstName = "first_name"
            case lastName = "last_name"
            case username
            case instagramHandle = "instagram"
            case twitterHandle = "twitter"
            case tiktokHandle = "tiktok"
            case profilePictureURL = "profile_picture_url"
        }
    }
    
    func getCurrentUserProfile() async throws -> UserProfile? {
        guard let userId = supabase.auth.currentUser?.id else {
            return nil
        }
        
        let profile = try await getUserProfile(userId: userId)
        
        // Check if profile has NULL values for name and we have stored signup data
        if let profile = profile,
           (profile.firstName == nil || profile.lastName == nil),
           let signupData = loadPendingSignupData(for: userId) {
            // Profile is incomplete and we have signup data - update it
            print("🔍 Profile incomplete, updating with stored signup data...")
            try await updateProfileFromPendingSignupData(userId: userId, signupData: signupData)
            // Reload profile after update
            return try await getUserProfile(userId: userId)
        }
        
        return profile
    }
    
    // MARK: - Store Signup Data Temporarily (PendingSignupData struct)
    struct PendingSignupData: Codable {
        let userId: UUID
        let firstName: String
        let lastName: String
        let email: String
    }
    
    func savePendingSignupData(userId: UUID, firstName: String, lastName: String, email: String) {
        let data = PendingSignupData(userId: userId, firstName: firstName, lastName: lastName, email: email)
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: "pending_signup_\(userId.uuidString)")
            print("✅ Saved pending signup data for user \(userId)")
        }
    }
    
    func loadPendingSignupData(for userId: UUID) -> PendingSignupData? {
        if let savedData = UserDefaults.standard.data(forKey: "pending_signup_\(userId.uuidString)"),
           let decodedData = try? JSONDecoder().decode(PendingSignupData.self, from: savedData) {
            print("✅ Loaded pending signup data for user \(userId)")
            return decodedData
        }
        return nil
    }
    
    func clearPendingSignupData(for userId: UUID) {
        UserDefaults.standard.removeObject(forKey: "pending_signup_\(userId.uuidString)")
        print("✅ Cleared pending signup data for user \(userId)")
    }
    
    private func updateProfileFromPendingSignupData(userId: UUID, signupData: PendingSignupData) async throws {
        let displayNameValue = "\(signupData.firstName) \(signupData.lastName)".trimmingCharacters(in: .whitespaces)
        
        var profileData: [String: String] = [
            "first_name": signupData.firstName,
            "last_name": signupData.lastName,
            "display_name": displayNameValue,
            "email": signupData.email,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        try await supabase
            .from("profiles")
            .update(profileData)
            .eq("id", value: userId.uuidString)
            .execute()
        
        // Clear stored data after successful update
        clearPendingSignupData(for: userId)
        print("✅ Profile updated from pending signup data")
    }
    
    func getUserProfile(userId: UUID) async throws -> UserProfile? {
        let response: [UserProfile] = try await supabase
            .from("profiles")
            .select("""
                id,
                display_name,
                first_name,
                last_name,
                username,
                instagram,
                twitter,
                tiktok,
                profile_picture_url
            """)
            .eq("id", value: userId)
            .execute()
            .value
        
        return response.first
    }
    
    func updateInstagramHandle(_ handle: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Remove @ if present
        let cleanHandle = handle.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        
        try await supabase
            .from("profiles")
            .update(["instagram": cleanHandle])
            .eq("id", value: userId)
            .execute()
    }
    
    func checkUsernameAvailability(_ username: String) async throws -> Bool {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Check if username is taken by someone other than the current user
        let response: [UserProfile] = try await supabase
            .from("profiles")
            .select("id, username")
            .eq("username", value: username.lowercased())
            .neq("id", value: userId.uuidString)
            .execute()
            .value
        
        return response.isEmpty
    }
    
    // Public method to check username availability without authentication (for signup flow)
    func checkUsernameAvailabilityPublic(_ username: String) async throws -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        
        print("🔍 Checking username availability for: '\(trimmedUsername)'")
        
        do {
            // Check if username is taken by anyone
            // We only select username and id (id is needed for UserProfile decoding)
            let response: [UserProfile] = try await supabase
                .from("profiles")
                .select("id, username")
                .eq("username", value: trimmedUsername)
                .execute()
                .value
            
            let isAvailable = response.isEmpty
            print("✅ Username availability check: '\(trimmedUsername)' is \(isAvailable ? "available" : "taken")")
            return isAvailable
        } catch {
            print("❌ Username availability check failed for '\(trimmedUsername)':")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            
            // Cast error to NSError to access domain, code, and userInfo
            let nsError = error as NSError
            print("   Domain: \(nsError.domain)")
            print("   Code: \(nsError.code)")
            print("   UserInfo: \(nsError.userInfo)")
            
            // Try to extract Supabase-specific error details
            let errorString = String(describing: error).lowercased()
            print("   Full error string: \(errorString)")
            
            // Check for permission errors
            if errorString.contains("permission denied") || 
               errorString.contains("access denied") ||
               errorString.contains("new row violates row-level security") {
                print("⚠️ PERMISSION ERROR DETECTED: Anonymous users may not have SELECT permission on profiles table")
                print("⚠️ Run the SQL: GRANT SELECT ON public.profiles TO anon;")
            }
            throw error
        }
    }
    
    // MARK: - Create Profile After Signup
    // This method updates the profile created by the trigger with user-provided data
    // Note: The profile row is already created by the trigger, so we use UPDATE
    // Username is optional and can be set later by the user
    func createOrUpdateProfileAfterSignup(userId: UUID, firstName: String, lastName: String, email: String) async throws {
        // Always store signup data in case email confirmation is required
        savePendingSignupData(userId: userId, firstName: firstName, lastName: lastName, email: email)
        let displayNameValue = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        print("🔍 Creating profile after signup for user: \(userId)")
        
        // Wait a moment for the trigger to create the profile row
        try? await Task.sleep(for: .milliseconds(500))
        
        // Verify we have an active session (required for RLS)
        if let currentUserId = supabase.auth.currentUser?.id, currentUserId == userId {
            // Session exists and matches - proceed with update
            print("✅ Session verified for user: \(userId)")
        } else {
            // If no session, try to get it
            do {
                let session = try await supabase.auth.session
                guard session.user.id == userId else {
                    throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session user ID does not match signup user ID"])
                }
                print("✅ Session established for user: \(userId)")
            } catch {
                print("⚠️ No active session found. Profile will be updated when user confirms email.")
                throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "No active session. Profile will be created when you confirm your email."])
            }
        }
        
        var profileData: [String: String] = [
            "first_name": firstName,
            "last_name": lastName,
            "display_name": displayNameValue,
            "email": email,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Use UPDATE instead of UPSERT since the profile row already exists from the trigger
        // The trigger creates a row with NULL values, so we just update it
        print("📝 Updating profile with user data...")
        try await supabase
            .from("profiles")
            .update(profileData)
            .eq("id", value: userId.uuidString)
            .execute()
        
        print("✅ Profile updated successfully")
    }
    
    func createOrUpdateProfile(firstName: String, lastName: String, username: String? = nil, displayName: String? = nil, email: String? = nil) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Check username availability if provided
        if let username = username {
            let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
            let isAvailable = try await checkUsernameAvailability(trimmedUsername)
            if !isAvailable {
                throw NSError(domain: "UserProfileService", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])
            }
        }
        
        let displayNameValue = displayName ?? "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        // Get email from auth user if not provided
        let emailValue = email ?? supabase.auth.currentUser?.email
        
        var profileData: [String: String] = [
            "id": userId.uuidString,
            "first_name": firstName,
            "last_name": lastName,
            "display_name": displayNameValue,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let username = username {
            profileData["username"] = username.trimmingCharacters(in: .whitespaces).lowercased()
        }
        
        if let emailValue = emailValue {
            profileData["email"] = emailValue
        }
        
        try await supabase
            .from("profiles")
            .upsert(profileData)
            .execute()
    }
    
    func updateProfilePicture(_ imageURL: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await supabase
            .from("profiles")
            .update(["profile_picture_url": imageURL])
            .eq("id", value: userId)
            .execute()
    }
    
    func updateName(firstName: String, lastName: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let displayNameValue = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        
        try await supabase
            .from("profiles")
            .update([
                "first_name": firstName,
                "last_name": lastName,
                "display_name": displayNameValue,
                "updated_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: userId)
            .execute()
    }
    
    func updateUsername(_ username: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Check username availability
        let isAvailable = try await checkUsernameAvailability(trimmedUsername)
        if !isAvailable {
            throw NSError(domain: "UserProfileService", code: 409, userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])
        }
        
        do {
            try await supabase
                .from("profiles")
                .update([
                    "username": trimmedUsername,
                    "updated_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("id", value: userId)
                .execute()
        } catch {
            // Format error into user-friendly message
            let userFriendlyError = formatSupabaseError(error, context: "update username")
            throw NSError(domain: "UserProfileService", code: 500, userInfo: [NSLocalizedDescriptionKey: userFriendlyError])
        }
    }
    
    // MARK: - Error Formatting Helper
    
    /// Formats Supabase errors into user-friendly messages
    func formatSupabaseError(_ error: Error, context: String = "") -> String {
        let nsError = error as NSError
        let errorString = String(describing: error).lowercased()
        let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
        
        // Check for specific error patterns
        if description.lowercased().contains("already taken") || errorString.contains("already taken") {
            return "This username is already taken. Please choose another one."
        }
        
        if errorString.contains("permission denied") || errorString.contains("access denied") || 
           errorString.contains("new row violates row-level security") || errorString.contains("row-level security") {
            return "You don't have permission to perform this action. Please try again."
        }
        
        if nsError.domain == NSURLErrorDomain || errorString.contains("network") || errorString.contains("connection") {
            return "Network error. Please check your connection and try again."
        }
        
        if errorString.contains("decoding") || errorString.contains("couldn't be read") || errorString.contains("missing") {
            return "Failed to process the response. Please try again."
        }
        
        // Check for authentication errors
        if errorString.contains("not authenticated") || errorString.contains("unauthorized") || nsError.code == 401 {
            return "You need to be logged in to perform this action. Please log in and try again."
        }
        
        // For other errors, provide a generic message
        return "An error occurred. Please try again."
    }
    
    func updateSocialMediaHandle(platform: SocialMediaPlatform, handle: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Remove @ if present
        let cleanHandle = handle.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        
        let columnName: String
        switch platform {
        case .instagram:
            columnName = "instagram"
        case .twitter:
            columnName = "twitter"
        case .tiktok:
            columnName = "tiktok"
        }
        
        try await supabase
            .from("profiles")
            .update([columnName: cleanHandle])
            .eq("id", value: userId)
            .execute()
    }
    
    // MARK: - Delete Account
    
    func deleteAccount() async throws {
        guard let currentUser = supabase.auth.currentUser else {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Get access token before deletion
        let session: Session
        do {
            session = try await supabase.auth.session
        } catch {
            throw NSError(domain: "UserProfileService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Could not get session: \(error.localizedDescription)"])
        }
        
        let accessToken = session.accessToken
        
        // Step 1: Call the database function to delete all user data from public tables
        try await supabase
            .rpc("delete_user_account")
            .execute()
        
        print("✅ User data deleted from public tables")
        
        // Step 2: Call edge function to delete auth user
        do {
            try await deleteAuthUser(accessToken: accessToken)
            print("✅ Auth user deleted successfully")
        } catch {
            print("⚠️ Failed to delete auth user: \(error.localizedDescription)")
            // Continue with sign out even if edge function fails
            // The auth user may have been deleted, or it will need manual deletion
        }
        
        // Step 3: Sign out the user (this will fail silently if user already deleted)
        try? await supabase.auth.signOut()
    }
    
    // MARK: - Delete Auth User via Edge Function
    
    private func deleteAuthUser(accessToken: String) async throws {
        guard let supabaseURL = URL(string: Secrets.supabaseUrl) else {
            throw NSError(domain: "UserProfileService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL"])
        }
        
        let functionURL = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("delete_auth_user")
        
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "UserProfileService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage: String
            if let errorDict = try? JSONDecoder().decode([String: String].self, from: data),
               let error = errorDict["error"] {
                errorMessage = error
            } else {
                errorMessage = "Unknown error"
            }
            throw NSError(
                domain: "UserProfileService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete auth user: \(errorMessage)"]
            )
        }
    }
}


