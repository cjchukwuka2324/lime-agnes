#!/usr/bin/env ruby
# encoding: utf-8

# Move file references to correct groups based on actual file locations

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

puts "🔧 Moving files to correct groups..."

# Find all actual file locations
actual_locations = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  basename = File.basename(rel_path)
  actual_locations[basename] = rel_path
end

moved = 0

# Process all file references
project.files.each do |file_ref|
  next unless file_ref.path && file_ref.path.end_with?('.swift')
  
  filename = file_ref.path
  actual_path = actual_locations[filename]
  next unless actual_path
  
  # Get correct group based on actual file location
  group = rockout_group
  dir_parts = File.dirname(actual_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Move if in wrong group
  if file_ref.parent != group
    file_ref.remove_from_project
    group.children << file_ref
    moved += 1
    puts "  ✓ Moved: #{filename} → #{actual_path}"
  end
end

project.save
puts "\n✅ Moved #{moved} file reference(s) to correct groups"

# Verify all problematic files
puts "\n🔍 Verifying problematic files..."
problem_files = [
  'FeedService.swift', 'FeedImageService.swift', 'FeedMediaService.swift', 'BackendFeedService.swift',
  'RockListService.swift', 'RockListDataService.swift', 'LeaderboardService.swift',
  'FeedView.swift', 'NotificationsView.swift', 'ParentPostReferenceView.swift', 'UserSearchView.swift',
  'FeedAudioPlayerView.swift', 'FeedCardView.swift', 'PostDetailView.swift', 'VideoPlayerView.swift',
  'PostComposerView.swift', 'LeaderboardAttachmentView.swift', 'RockListView.swift', 'MyRockListView.swift',
  'ArtistLeaderboardView.swift', 'MyArtistRanksView.swift', 'Post.swift', 'Notification.swift',
  'LeaderboardFilters.swift', 'ArtistLeaderboardModels.swift', 'FeedViewModel.swift', 'PostDetailViewModel.swift',
  'RockListViewModel.swift', 'MyRockListViewModel.swift', 'MyArtistRanksViewModel.swift', 'ArtistLeaderboardViewModel.swift'
]

all_correct = true
problem_files.each do |filename|
  file_ref = project.files.find { |f| f.path == filename }
  next unless file_ref
  
  actual_path = actual_locations[filename]
  next unless actual_path
  
  parent = file_ref.parent
  expected_group = File.dirname(actual_path).split('/').last
  
  if parent.display_name != expected_group
    puts "  ❌ #{filename}: in '#{parent.display_name}', should be in '#{expected_group}'"
    all_correct = false
  end
end

if all_correct
  puts "✅ All files in correct groups!"
else
  puts "\n⚠️  Some files still need fixing"
end

puts "\n💡 Try building now!"

