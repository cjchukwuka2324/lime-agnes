import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var spotifyAuth = SpotifyAuthService.shared
    @StateObject private var userPostsViewModel = FeedViewModel()
    @StateObject private var userRepliesViewModel = FeedViewModel()
    @StateObject private var userLikedViewModel = FeedViewModel()

    @State private var isLoading = false
    @State private var message: String?
    @State private var currentUserId: String?
    @State private var selectedProfileTab: ProfileContentTab = .posts
    @State private var userProfile: UserProfileService.UserProfile?
    @State private var profilePictureURL: URL?
    @State private var showSettings = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isUploadingProfilePicture = false
    @State private var showSocialMediaEditor = false
    @State private var selectedSocialPlatform: SocialMediaPlatform?
    
    enum ProfileContentTab: String, CaseIterable {
        case posts = "Posts"
        case replies = "Replies"
        case likes = "Likes"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Solid black background
                Color.black
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile Header with Picture
                        profileHeaderSection
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                        
                        // Social Media Buttons
                        SocialMediaButtonsView(
                            instagramHandle: userProfile?.instagramHandle,
                            twitterHandle: userProfile?.twitterHandle,
                            tiktokHandle: userProfile?.tiktokHandle,
                            onEdit: { platform in
                                selectedSocialPlatform = platform
                            }
                        )
                        .padding(.top, 8)
                        
                        // Content Tabs (Posts, Replies, Likes)
                        if let userId = currentUserId {
                            profileContentTabs(userId: userId)
                                .padding(.horizontal, 20)
                        }
                        
                        Spacer()
                            .frame(height: 20)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                // Ensure navigation bar is always opaque
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = .black
                appearance.shadowColor = .clear
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                UINavigationBar.appearance().compactAppearance = appearance
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    }
                }
            }
            .task {
                await authVM.refreshUser()
                await loadUserProfile()
                if let userId = currentUserId {
                    await loadCurrentContent()
                }
            }
            .sheet(isPresented: $showSettings) {
                AccountSettingsView()
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .sheet(item: $selectedSocialPlatform) { platform in
                EditSocialMediaView(platform: platform)
                    .onDisappear {
                        // Reload profile when editor closes
                        Task {
                            await loadUserProfile()
                        }
                    }
            }
            .onChange(of: selectedImage) { _, newImage in
                if let image = newImage {
                    Task {
                        await uploadProfileImage(image)
                    }
                }
            }
            .onChange(of: selectedProfileTab) { _, newTab in
                if let userId = currentUserId {
                    Task {
                        await loadContentForTab(newTab, userId: userId)
                    }
                }
            }
        }
    }
    
    // MARK: - Profile Header Section
    
    private var profileHeaderSection: some View {
        VStack(spacing: 20) {
            // Profile Picture
            ZStack(alignment: .bottomTrailing) {
                Button {
                    showImagePicker = true
                } label: {
                    ZStack {
                        if let imageURL = profilePictureURL {
                            AsyncImage(url: imageURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .tint(.white)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                case .failure:
                                    defaultProfileAvatar
                                @unknown default:
                                    defaultProfileAvatar
                                }
                            }
                        } else if let selectedImage = selectedImage {
                            Image(uiImage: selectedImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            defaultProfileAvatar
                        }
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 3)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .disabled(isUploadingProfilePicture)
                
                // Camera Button - positioned outside the circle
                Button {
                    showImagePicker = true
                } label: {
                    Circle()
                        .fill(Color(hex: "#1ED760"))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .medium))
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .offset(x: 4, y: 4)
                .disabled(isUploadingProfilePicture)
            }
            
            if isUploadingProfilePicture {
                ProgressView()
                    .tint(.white)
            }
            
            // User Name
            Text(profileDisplayName)
                .font(.title2.bold())
                .foregroundColor(.white)
            
            if let handle = profileHandle {
                Text(handle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    private var defaultProfileAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(profileInitials)
                    .font(.title.bold())
                    .foregroundColor(.white)
            )
    }
    
    private var profileDisplayName: String {
        guard let profile = userProfile else { return "User" }
        if let firstName = profile.firstName, let lastName = profile.lastName {
            return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        } else if let displayName = profile.displayName {
            return displayName
        } else {
            return authVM.currentUserEmail?.components(separatedBy: "@").first?.capitalized ?? "User"
        }
    }
    
    private var profileHandle: String? {
        guard let profile = userProfile else { return nil }
        if let username = profile.username {
            return "@\(username)"
        } else if let email = authVM.currentUserEmail {
            let emailPrefix = email.components(separatedBy: "@").first ?? "user"
            return "@\(emailPrefix)"
        } else if let firstName = profile.firstName {
            return "@\(firstName.lowercased())"
        }
        return nil
    }
    
    private var profileInitials: String {
        guard let profile = userProfile else { return "U" }
        if let firstName = profile.firstName, let lastName = profile.lastName {
            let firstInitial = String(firstName.prefix(1)).uppercased()
            let lastInitial = String(lastName.prefix(1)).uppercased()
            return "\(firstInitial)\(lastInitial)"
        } else if let displayName = profile.displayName {
            return String(displayName.prefix(2)).uppercased()
        } else if let email = authVM.currentUserEmail {
            return String(email.prefix(2)).uppercased()
        }
        return "U"
    }
    
    
    // MARK: - Profile Content Tabs
    
    @ViewBuilder
    private func profileContentTabs(userId: String) -> some View {
        VStack(spacing: 20) {
            // Tab Picker
            Picker("Content Type", selection: $selectedProfileTab) {
                ForEach(ProfileContentTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Content View
            Group {
                switch selectedProfileTab {
                case .posts:
                    profileContentList(viewModel: userPostsViewModel, emptyIcon: "square.and.pencil", emptyTitle: "No posts yet", emptyMessage: "Share your thoughts and RockList rankings!")
                case .replies:
                    profileContentList(viewModel: userRepliesViewModel, emptyIcon: "bubble.left", emptyTitle: "No replies yet", emptyMessage: "Start replying to posts to see them here!")
                case .likes:
                    profileContentList(viewModel: userLikedViewModel, emptyIcon: "heart", emptyTitle: "No likes yet", emptyMessage: "Like posts to see them here!")
                }
            }
        }
    }
    
    @ViewBuilder
    private func profileContentList(viewModel: FeedViewModel, emptyIcon: String, emptyTitle: String, emptyMessage: String) -> some View {
        if viewModel.isLoading {
            HStack {
                Spacer()
                ProgressView()
                    .tint(.white)
                Spacer()
            }
            .padding()
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if viewModel.posts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: emptyIcon)
                    .font(.largeTitle)
                    .foregroundColor(.white.opacity(0.5))
                Text(emptyTitle)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.7))
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.posts) { post in
                    FeedCardView(
                        post: post,
                        showInlineReplies: true,
                        service: InMemoryFeedService.shared
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadUserProfile() async {
        if let profile = try? await UserProfileService.shared.getCurrentUserProfile() {
            userProfile = profile
            currentUserId = profile.id.uuidString
            
            // Load profile picture URL
            if let pictureURLString = profile.profilePictureURL, let url = URL(string: pictureURLString) {
                profilePictureURL = url
            }
        }
    }
    
    private func loadCurrentContent() async {
        guard let userId = currentUserId else { return }
        await loadContentForTab(selectedProfileTab, userId: userId)
    }
    
    private func loadContentForTab(_ tab: ProfileContentTab, userId: String) async {
        switch tab {
        case .posts:
            await userPostsViewModel.loadUserPosts(userId: userId)
        case .replies:
            await userRepliesViewModel.loadUserReplies(userId: userId)
        case .likes:
            await userLikedViewModel.loadUserLikedPosts(userId: userId)
        }
    }
    
    private func uploadProfileImage(_ image: UIImage) async {
        // Upload profile picture
        isUploadingProfilePicture = true
        defer { isUploadingProfilePicture = false }
        
        // Upload to Supabase storage
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            message = "Failed to process image"
            return
        }
        
        guard let userId = SupabaseService.shared.client.auth.currentUser?.id else {
            message = "Not authenticated"
            return
        }
        
        do {
            let filename = "\(UUID().uuidString).jpg"
            let path = "profile_pictures/\(userId.uuidString)/\(filename)"
            
            let supabase = SupabaseService.shared.client
            try await supabase.storage
                .from("feed-images")
                .upload(path: path, file: imageData)
            
            let publicURL = try supabase.storage
                .from("feed-images")
                .getPublicURL(path: path)
            
            // Update profile with new picture URL
            try await UserProfileService.shared.updateProfilePicture(publicURL.absoluteString)
            
            profilePictureURL = publicURL
            await loadUserProfile() // Reload profile
        } catch {
            message = "Failed to upload profile picture: \(error.localizedDescription)"
        }
    }
}
