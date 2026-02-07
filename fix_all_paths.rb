#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('Rockout.xcodeproj')
target = project.targets.first
build_phase = target.source_build_phase

# List of files from error messages that need fixing
problem_files = [
  'DeviceTokenService.swift',
  'AccountSettingsView.swift',
  'UserProfileDetailView.swift',
  'FollowersFollowingListView.swift',
  'MultiImagePicker.swift',
  'ImageSlideshowView.swift',
  'SpotifyConnectionService.swift',
  'MusicPlatformConnectionView.swift',
  'FeedView.swift',
  'FeedViewModel.swift',
  'TrendingFeedView.swift',
  'TrendingFeedViewModel.swift',
  'HashtagService.swift',
  'FeedService.swift',
  'MusicPlatformModels.swift',
  'RecallModels.swift',
  'RecallService.swift',
  'RecallThreadTitleService.swift',
  'RecallThreadStore.swift',
  'SupabaseFeedService.swift',
  'MentionService.swift',
  'FeedStore.swift',
  'FeedPersistence.swift',
  'FeedImageService.swift',
  'FeedMediaService.swift',
  'InMemorySocialGraphService.swift',
  'SupabaseSocialGraphService.swift',
  'SharedFilters.swift',
  'SocialMediaPlatform.swift',
  'ArtistLeaderboardModels.swift',
  'LeaderboardFilters.swift',
  'View+ScrollDetection.swift',
  'AnimatedGradientBackground.swift',
  'VideoPicker.swift',
  'SocialMediaButtonsView.swift',
  'EditSocialMediaView.swift',
  'EditNameView.swift',
  'EditUsernameView.swift',
  'ImageCropView.swift',
  'UserSearchViewModel.swift',
  'ContactsService.swift',
  'ContactSyncService.swift',
  'MutualFollowSuggestionCard.swift',
  'ContactSuggestionCard.swift',
  'InviteLinkGenerator.swift',
  'SuggestedFollowService.swift',
  'UserCardView.swift',
  'UserProfileService.swift',
  'FollowService.swift',
  'MusicPlatformConnectionService.swift',
  'Post.swift',
  'GreenRoomBranding.swift',
  'Notification.swift',
  'PostComposerView.swift',
  'VoiceRecordingView.swift',
  'MentionAutocompleteView.swift',
  'HashtagAutocompleteView.swift',
  'UserSearchView.swift',
  'ContactPickerView.swift',
  'FullScreenMediaView.swift',
  'NotificationsViewModel.swift',
  'UserProfileViewModel.swift',
  'NotificationService.swift',
  'AppNotification.swift',
  'NotificationsView.swift',
  'PostDetailView.swift',
  'ThreadReplyView.swift',
  'MediaGridView.swift',
  'PostDetailViewModel.swift',
  'FeedCardView.swift',
  'LeaderboardAttachmentView.swift',
  'View+GlassMorphism.swift',
  'Notification+Feed.swift',
  'ParentPostReferenceView.swift',
  'VideoPlayerView.swift',
  'FeedAudioPlayerView.swift',
  'BackgroundMusicPlayerView.swift',
  'SpotifyLinkCardView.swift',
  'PollView.swift',
  'TabBarController.swift',
  'SpotifyLinkAddView.swift',
  'RecallImageInputView.swift',
  'RecallTextInputView.swift',
  'RecallResultsView.swift',
  'RecallVoiceInputView.swift',
  'RecallHomeView.swift',
  'RecallStashedThreadsView.swift',
  'RecallSettingsView.swift',
  'PollCreationView.swift',
  'BackgroundMusicSelectorView.swift',
  'PollVoteService.swift',
  'Color+Hex.swift',
  'SpotifyListeningStats.swift',
  'SpotifyPlaylistService.swift',
  'AppleMusicPlaylistService.swift',
  'ErrorMessageBanner.swift',
  'AppleMusicWebAPI.swift',
  'SpotifyAuthService.swift',
  'SupabaseService.swift',
  'StudioAlbumRecord.swift',
  'SpotifyAPI.swift',
  'ShareableLink.swift',
  'SpotifyModels.swift',
  'AudioPlayerViewModel.swift',
  'StudioTrackRecord.swift',
  'TrackComment.swift',
  'WaveformData.swift',
  'SpotifyTokenStore.swift',
  'SpotifyTokens.swift',
  'String+SHA256.swift',
  'Dictionary+PercentEncoding.swift',
  'AlbumService.swift',
  'ImagePicker.swift',
  'PublicAlbumCard.swift',
  'DiscoveryEngine.swift',
  'RecallViewModel.swift',
  'RecallStashedThreadsViewModel.swift',
  'AuthViewModel.swift',
  'ShareService.swift',
  'GenreStat.swift',
  'TrackService.swift',
  'AddTrackView.swift',
  'Date+TimeAgo.swift',
  'OnboardingVideoScreen.swift',
  'OnboardingFlowView.swift',
  'OnboardingSlideView.swift',
  'OnboardingState.swift',
  'StudioSessionsViewModel.swift',
  'RockOutApp.swift',
  'AppDelegate.swift',
  'AnimatedGenreBarChart.swift',
  'WelcomeView.swift',
  'ConnectSpotifyView.swift',
  'LoginView.swift',
  'ListeningStatsService.swift',
  'ForgotPasswordView.swift',
  'ResetPasswordView.swift',
  'AuthFlowView.swift',
  'SignUpView.swift',
  'SetUsernameView.swift',
  'LoginForm.swift',
  'SignupForm.swift',
  'GoogleLoginButton.swift',
  'StudioSessionsView.swift',
  'CreateAlbumView.swift',
  'AlbumDetailView.swift',
  'UploadTrackSelectorView.swift',
  'RootAppView.swift',
  'SupabaseAuthService.swift',
  'SupabaseStorageService.swift',
  'SpotifyError.swift',
  'AuthService.swift',
  'UniversalFileImportService.swift',
  'Item.swift',
  'User.swift',
  'ShareExporter.swift',
  'ImageCache.swift',
  'TabBarState.swift',
  'AppleMusicAuthService.swift',
  'StudioSessionsTabBar.swift',
  'AppleMusicAPI.swift',
  'RecallOrbView.swift',
  'RecallComposerBar.swift',
  'RecallMessageBubble.swift',
  'RecallSourcesSheet.swift',
  'RecallStashedView.swift',
  'RecallRepromptSheet.swift',
  'RecallCandidateCard.swift',
  'TrackVersion.swift',
  'SpotifyConnectionView.swift',
  'SpotifyConnection.swift',
  'VoiceRecorder.swift',
  'VoiceResponseService.swift',
  'AppleMusicModels.swift',
  'AppleMusicConnection.swift',
  'Color+Brand.swift',
  'VideoAudioExtractor.swift',
  'GifImage.swift',
  'Logger.swift',
  'Analytics.swift',
  'PerformanceMetrics.swift',
  'RequestCoalescer.swift',
  'RetryPolicy.swift',
  'ProfileCache.swift',
  'RecallStateMachine.swift',
  'AudioSessionManager.swift',
  'RecallCache.swift',
  'RecallMetrics.swift'
]

puts "Fixing #{problem_files.count} problematic files..."

fixed = 0
build_phase.files.each do |bf|
  file_ref = bf.file_ref
  next unless file_ref
  
  path = file_ref.path
  next unless path
  
  basename = File.basename(path)
  
  # Only process if it's in our problem list
  next unless problem_files.include?(basename)
  
  # Find actual file
  found = Dir.glob("Rockout/**/#{basename}").first || 
          Dir.glob("**/#{basename}").reject { |f| 
            f.include?('.xcodeproj') || 
            f.include?('DerivedData') || 
            f.include?('.git')
          }.first
  
  if found
    # Get correct path relative to Rockout/
    if found.start_with?('./Rockout/')
      correct_path = found.sub('./Rockout/', '')
    elsif found.start_with?('Rockout/')
      correct_path = found.sub('Rockout/', '')
    else
      # File outside Rockout - check if it should be there
      if File.exist?("Rockout/#{File.dirname(found)}/#{basename}")
        correct_path = "#{File.dirname(found).sub('./', '')}/#{basename}".sub('Rockout/', '')
      else
        correct_path = found.sub('./', '')
      end
    end
    
    # Remove duplicate directory segments
    new_path = correct_path
    new_path = new_path.gsub(/Services\/([^\/]+)\/Services\/([^\/]+)\//, 'Services/\1/')
    new_path = new_path.gsub(/Views\/([^\/]+)\/Views\/([^\/]+)\//, 'Views/\1/')
    new_path = new_path.gsub(/Models\/([^\/]+)\/Models\/([^\/]+)\//, 'Models/\1/')
    new_path = new_path.gsub(/ViewModels\/([^\/]+)\/ViewModels\/([^\/]+)\//, 'ViewModels/\1/')
    new_path = new_path.gsub(/Extensions\/([^\/]+)\/Extensions\/([^\/]+)\//, 'Extensions/\1/')
    new_path = new_path.gsub(/Utils\/([^\/]+)\/Utils\/([^\/]+)\//, 'Utils/\1/')
    
    if new_path != path
      # Verify file exists
      if File.exist?("Rockout/#{new_path}") || File.exist?(new_path)
        file_ref.path = new_path
        puts "Fixed: #{path} -> #{new_path}"
        fixed += 1
      end
    end
  end
end

project.save
puts "\n✅ Fixed #{fixed} file paths"
