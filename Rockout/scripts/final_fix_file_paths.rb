#!/usr/bin/env ruby
# encoding: utf-8

# Final fix: Ensure all file references have correct paths
# Files should be in groups matching Rockout/ directory structure

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  puts "   Install with: gem install xcodeproj"
  exit 1
end

SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')
SOURCE_DIR = File.join(PROJECT_DIR, 'Rockout')

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

puts "🔍 Fixing file reference paths..."

# Get the Rockout group (should be main group or a child)
rockout_group = project.main_group['Rockout'] || project.main_group

# Files that need fixing
problem_files = [
  'Secrets.swift',
  'ViewModels/Leaderboard/ArtistLeaderboardViewModel.swift',
  'ViewModels/Leaderboard/MyArtistRanksViewModel.swift',
  'Models/Leaderboard/ArtistLeaderboardModels.swift',
  'Models/Leaderboard/LeaderboardFilters.swift',
  'Views/Leaderboard/MyArtistRanksView.swift',
  'Views/Leaderboard/ArtistLeaderboardView.swift',
  'Views/Shared/AnimatedGradientBackground.swift',
  'Views/Profile/EditNameView.swift',
  'Services/Leaderboard/LeaderboardService.swift',
  'Services/Feed/BackendFeedService.swift'
]

fixed = 0

problem_files.each do |rel_path|
  full_path = File.join(SOURCE_DIR, rel_path)
  next unless File.exist?(full_path)
  
  basename = File.basename(rel_path)
  
  # Find file reference
  file_ref = project.files.find do |f|
    f.path && (
      f.path == rel_path ||
      f.path == basename ||
      File.basename(f.path) == basename
    )
  end
  
  next unless file_ref
  
  # Find or create correct group structure
  group = rockout_group
  dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Update path to be relative from Rockout group
  correct_path = rel_path
  
  if file_ref.path != correct_path
    puts "  ✓ Updating path: #{file_ref.path} → #{correct_path}"
    file_ref.path = correct_path
    fixed += 1
  end
  
  # Move to correct group
  if file_ref.parent != group
    file_ref.remove_from_project
    group.children << file_ref
    group_path = group.display_name || 'root'
    puts "  ✓ Moved to group: #{group_path}"
  end
  
  # Ensure in build phase
  build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
  if build_file.nil? && rel_path.end_with?('.swift')
    target.add_file_references([file_ref])
    puts "  ✓ Added to build phase"
  end
end

project.save
puts "\n✅ Fixed #{fixed} file reference(s)!"
puts "💡 Try building again."

