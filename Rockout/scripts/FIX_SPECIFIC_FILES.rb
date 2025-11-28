#!/usr/bin/env ruby
# encoding: utf-8

# Fix specific files that are in wrong groups

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  exit 1
end

SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')
SOURCE_DIR = File.join(PROJECT_DIR, 'Rockout')

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase
rockout_group = project.main_group['Rockout'] || project.main_group

puts "🔧 Fixing specific files in wrong groups..."

# Map of files to their correct paths
file_corrections = {
  # Services
  'FeedService.swift' => 'Services/Feed/FeedService.swift',
  'FeedImageService.swift' => 'Services/Feed/FeedImageService.swift',
  'FeedMediaService.swift' => 'Services/Feed/FeedMediaService.swift',
  'BackendFeedService.swift' => 'Services/Feed/BackendFeedService.swift',
  'RockListService.swift' => 'Services/RockList/RockListService.swift',
  'RockListDataService.swift' => 'Services/RockList/RockListDataService.swift',
  'LeaderboardService.swift' => 'Services/Leaderboard/LeaderboardService.swift',
  
  # Views
  'FeedView.swift' => 'Views/Feed/FeedView.swift',
  'NotificationsView.swift' => 'Views/Feed/NotificationsView.swift',
  'ParentPostReferenceView.swift' => 'Views/Feed/ParentPostReferenceView.swift',
  'UserSearchView.swift' => 'Views/Feed/UserSearchView.swift',
  'FeedAudioPlayerView.swift' => 'Views/Feed/FeedAudioPlayerView.swift',
  'FeedCardView.swift' => 'Views/Feed/FeedCardView.swift',
  'PostDetailView.swift' => 'Views/Feed/PostDetailView.swift',
  'VideoPlayerView.swift' => 'Views/Feed/VideoPlayerView.swift',
  'PostComposerView.swift' => 'Views/Feed/PostComposerView.swift',
  'LeaderboardAttachmentView.swift' => 'Views/Feed/LeaderboardAttachmentView.swift',
  'RockListView.swift' => 'Views/RockList/RockListView.swift',
  'MyRockListView.swift' => 'Views/RockList/MyRockListView.swift',
  'ArtistLeaderboardView.swift' => 'Views/Leaderboard/ArtistLeaderboardView.swift',
  'MyArtistRanksView.swift' => 'Views/Leaderboard/MyArtistRanksView.swift',
  
  # Models
  'Post.swift' => 'Models/Feed/Post.swift',
  'Notification.swift' => 'Models/Feed/Notification.swift',
  'LeaderboardFilters.swift' => 'Models/Leaderboard/LeaderboardFilters.swift',
  'ArtistLeaderboardModels.swift' => 'Models/Leaderboard/ArtistLeaderboardModels.swift',
  
  # ViewModels
  'FeedViewModel.swift' => 'ViewModels/Feed/FeedViewModel.swift',
  'PostDetailViewModel.swift' => 'ViewModels/Feed/PostDetailViewModel.swift',
  'RockListViewModel.swift' => 'ViewModels/RockList/RockListViewModel.swift',
  'MyRockListViewModel.swift' => 'ViewModels/RockList/MyRockListViewModel.swift',
  'MyArtistRanksViewModel.swift' => 'ViewModels/Leaderboard/MyArtistRanksViewModel.swift',
  'ArtistLeaderboardViewModel.swift' => 'ViewModels/Leaderboard/ArtistLeaderboardViewModel.swift'
}

fixed = 0

file_corrections.each do |filename, correct_path|
  # Find the file reference
  file_ref = project.files.find { |f| f.path == filename }
  next unless file_ref
  
  # Verify file exists at correct location
  full_path = File.join(SOURCE_DIR, correct_path)
  unless File.exist?(full_path)
    puts "  ⚠️  File not found: #{correct_path}"
    next
  end
  
  # Get correct group
  group = rockout_group
  dir_parts = File.dirname(correct_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Move file reference to correct group
  if file_ref.parent != group
    file_ref.remove_from_project
    group.children << file_ref
    fixed += 1
    puts "  ✓ Moved: #{filename} → #{correct_path}"
  end
end

# Ensure all are in build phase
build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  filename = file_ref.path || ''
  correct_path = file_corrections[filename]
  next unless correct_path
  
  # Verify it's in correct group
  parent = file_ref.parent
  expected_group_name = File.dirname(correct_path).split('/').last
  if parent.display_name != expected_group_name
    puts "  ⚠️  Still in wrong group: #{filename} (in #{parent.display_name}, should be in #{expected_group_name})"
  end
end

project.save
puts "\n✅ Fixed #{fixed} file reference(s)"
puts "💡 Try building now!"

