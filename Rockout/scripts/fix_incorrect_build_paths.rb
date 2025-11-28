#!/usr/bin/env ruby
# encoding: utf-8

# Script to fix incorrect file paths in Xcode build phases
# Removes build phase entries that point to non-existent files

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  puts "   Install with: gem install xcodeproj"
  exit 1
end

# Auto-detect project paths
SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')
SOURCE_DIR = File.join(PROJECT_DIR, 'Rockout')

unless File.exist?(PROJECT_PATH)
  puts "❌ Xcode project not found at: #{PROJECT_PATH}"
  exit 1
end

puts "📦 Opening Xcode project: #{PROJECT_PATH}"

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

puts "🔍 Checking for files with incorrect paths..."

# List of files that are being referenced incorrectly
incorrect_paths = [
  'Services/Feed/BackendFeedService.swift',
  'Services/Leaderboard/LeaderboardService.swift',
  'Views/Profile/EditNameView.swift',
  'Views/Shared/AnimatedGradientBackground.swift',
  'Views/Leaderboard/ArtistLeaderboardView.swift',
  'Views/Leaderboard/MyArtistRanksView.swift',
  'Models/Leaderboard/LeaderboardFilters.swift',
  'Models/Leaderboard/ArtistLeaderboardModels.swift',
  'ViewModels/Leaderboard/MyArtistRanksViewModel.swift',
  'ViewModels/Leaderboard/ArtistLeaderboardViewModel.swift'
]

files_to_remove = []

# Check each build file
build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  # Get the file path
  file_path = file_ref.path || file_ref.display_name || ''
  
  # Check if this path is in our incorrect paths list
  if incorrect_paths.include?(file_path)
    # Check if the file actually exists at this path
    full_path = File.join(PROJECT_DIR, file_path)
    if !File.exist?(full_path)
      # File doesn't exist at this path - remove from build phase
      files_to_remove << {
        build_file: build_file,
        file_ref: file_ref,
        path: file_path
      }
    end
  end
  
  # Also check for paths that don't start with Rockout/ but should
  if file_path && !file_path.start_with?('Rockout/') && !file_path.start_with?('/')
    # Check if file exists at incorrect path
    incorrect_full_path = File.join(PROJECT_DIR, file_path)
    correct_path = File.join(SOURCE_DIR, file_path)
    
    if !File.exist?(incorrect_full_path) && File.exist?(correct_path)
      # File exists at correct path but build phase points to wrong path
      files_to_remove << {
        build_file: build_file,
        file_ref: file_ref,
        path: file_path,
        correct_path: "Rockout/#{file_path}"
      }
    end
  end
end

if files_to_remove.empty?
  puts "✅ No incorrect build paths found!"
  exit 0
end

puts "\n📋 Found #{files_to_remove.length} file(s) with incorrect paths:\n\n"

# Show what will be removed
files_to_remove.each do |item|
  puts "  ✗ Removing: #{item[:path]}"
  if item[:correct_path]
    puts "     (File exists at: #{item[:correct_path]})"
  end
end

# Remove incorrect entries
removed_count = 0
files_to_remove.each do |item|
  build_phase.remove_file_reference(item[:file_ref])
  removed_count += 1
end

# Now add the correct file references
puts "\n🔧 Adding correct file references..."

files_to_remove.each do |item|
  next unless item[:correct_path]
  
  correct_full_path = File.join(PROJECT_DIR, item[:correct_path])
  next unless File.exist?(correct_full_path)
  
  # Find or create the correct file reference
  rel_path = item[:correct_path].sub(/^Rockout\//, '')
  
  # Navigate to the correct group
  group = project.main_group
  dir_path = File.dirname(rel_path)
  
  if dir_path != '.' && !dir_path.empty?
    dir_path.split('/').each do |component|
      next if component.empty?
      existing = group.children.find { |g| g.display_name == component && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
      group = existing || group.new_group(component)
    end
  end
  
  # Check if file reference already exists
  existing_file = group.files.find { |f| f.path == rel_path }
  
  if existing_file
    # Add to build phase if not already there
    build_file = build_phase.files.find { |bf| bf.file_ref == existing_file }
    if build_file.nil? && rel_path.end_with?('.swift')
      target.add_file_references([existing_file])
      puts "  ✓ Added correct path: #{rel_path}"
    end
  else
    # Create new file reference
    file_ref = group.new_file(rel_path)
    file_ref.source_tree = '<group>'
    if rel_path.end_with?('.swift')
      target.add_file_references([file_ref])
      puts "  ✓ Added correct path: #{rel_path}"
    end
  end
end

# Save the project
begin
  project.save
  puts "\n✅ Removed #{removed_count} incorrect path(s) and saved project!"
  puts "\n💡 Try building again - the 'Build input files cannot be found' errors should be gone."
rescue => e
  puts "\n❌ Failed to save project: #{e.message}"
  puts "   Make sure Xcode is closed and try again."
  exit 1
end

