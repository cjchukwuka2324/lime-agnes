#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('Rockout.xcodeproj')

# Map of file names to their correct paths
file_path_fixes = {
  'DeviceTokenService.swift' => 'Rockout/Services/Notifications/DeviceTokenService.swift',
  'SpotifyConnectionService.swift' => 'Rockout/Services/Supabase/SpotifyConnectionService.swift',
  'FollowersFollowingListView.swift' => 'Rockout/Views/Profile/FollowersFollowingListView.swift',
  'MultiImagePicker.swift' => 'Rockout/Views/Shared/MultiImagePicker.swift',
  'ImageSlideshowView.swift' => 'Rockout/Views/Feed/ImageSlideshowView.swift',
  'SpotifyConnectionView.swift' => 'Rockout/Views/Profile/SpotifyConnectionView.swift',
  'SpotifyPresentationContextProvider.swift' => 'Rockout/Views/Profile/SpotifyPresentationContextProvider.swift',
  'DiscoverFeedAlbumCard.swift' => 'Rockout/Views/StudioSessions/DiscoverFeedAlbumCard.swift',
  'DiscoveriesAlbumCard.swift' => 'Rockout/Views/StudioSessions/DiscoveriesAlbumCard.swift',
  'AlbumSavedUsersView.swift' => 'Rockout/Views/StudioSessions/AlbumSavedUsersView.swift',
  'TrackPlayService.swift' => 'Rockout/Services/Supabase/TrackPlayService.swift',
  'PublicAlbumsSearchView.swift' => 'Rockout/Views/StudioSessions/PublicAlbumsSearchView.swift',
  'UserPublicAlbumsView.swift' => 'Rockout/Views/StudioSessions/UserPublicAlbumsView.swift',
  'TrackPlayBreakdownView.swift' => 'Rockout/Views/StudioSessions/TrackPlayBreakdownView.swift',
  'BottomPlayerBar.swift' => 'Rockout/Views/StudioSessions/BottomPlayerBar.swift',
  'AudioPlayerView.swift' => 'Rockout/Views/StudioSessions/AudioPlayerView.swift',
  'VersionService.swift' => 'Rockout/Services/Supabase/VersionService.swift',
  'ShareSheetView.swift' => 'Rockout/Views/StudioSessions/ShareSheetView.swift',
  'ProfileView.swift' => 'Rockout/Views/Profile/ProfileView.swift',
}

fixed_count = 0

# Find and fix file references
project.files.each do |file_ref|
  next unless file_ref.path
  
  filename = File.basename(file_ref.path)
  
  if file_path_fixes.key?(filename)
    correct_path = file_path_fixes[filename]
    old_path = file_ref.path
    
    # Only fix if the path is wrong
    if file_ref.path != correct_path
      file_ref.path = correct_path
      puts "Fixed: #{old_path} → #{correct_path}"
      fixed_count += 1
    end
  end
end

# Remove SpotifyConnection.swift if it doesn't exist
spotify_connection_file = project.files.find { |f| f.path == 'SpotifyConnection.swift' || f.path == 'Rockout/Services/Supabase/SpotifyConnection.swift' }
if spotify_connection_file
  # Check if file actually exists
  file_paths = [
    'Rockout/Services/Supabase/SpotifyConnection.swift',
    'Services/Supabase/SpotifyConnection.swift',
    'SpotifyConnection.swift'
  ]
  
  file_exists = file_paths.any? { |path| File.exist?(path) }
  
  unless file_exists
    puts "Removing non-existent file: #{spotify_connection_file.path}"
    spotify_connection_file.remove_from_project
    fixed_count += 1
  end
end

project.save
puts "✅ Fixed #{fixed_count} file path(s)"

