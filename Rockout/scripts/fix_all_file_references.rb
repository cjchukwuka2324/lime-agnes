#!/usr/bin/env ruby
# encoding: utf-8

# Comprehensive script to fix all file reference issues:
# 1. Remove duplicate file references
# 2. Fix incorrect paths
# 3. Ensure files are in correct groups
# 4. Add to build phase correctly

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

puts "🔍 Analyzing file references..."

# Track files by basename to find duplicates
files_by_basename = {}
duplicates_to_remove = []
files_to_fix = []

# List of problematic files
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

# Find all file references
project.files.each do |file_ref|
  next unless file_ref.path
  
  basename = File.basename(file_ref.path)
  
  # Check if this is one of our problem files
  if problem_files.any? { |pf| File.basename(pf) == basename || pf == basename }
    if files_by_basename[basename]
      # Duplicate found
      duplicates_to_remove << file_ref
      puts "  🗑️  Found duplicate: #{file_ref.path}"
    else
      files_by_basename[basename] = file_ref
      files_to_fix << {
        file_ref: file_ref,
        basename: basename,
        current_path: file_ref.path
      }
    end
  end
end

# Remove duplicates
puts "\n🗑️  Removing #{duplicates_to_remove.length} duplicate file reference(s)..."
duplicates_to_remove.each do |file_ref|
  # Remove from build phase first
  build_phase.files.each do |build_file|
    if build_file.file_ref == file_ref
      build_phase.remove_file_reference(file_ref)
    end
  end
  
  # Remove from groups
  file_ref.remove_from_project
end

# Fix remaining file references
puts "\n🔧 Fixing file reference paths..."

files_to_fix.each do |item|
  file_ref = item[:file_ref]
  basename = item[:basename]
  
  # Find the correct path for this file
  correct_path = problem_files.find { |pf| File.basename(pf) == basename || pf == basename }
  next unless correct_path
  
  correct_full_path = File.join(SOURCE_DIR, correct_path)
  next unless File.exist?(correct_full_path)
  
  # Get relative path (without Rockout/ prefix for file reference)
  rel_path = correct_path
  
  # Find or create correct group
  group = project.main_group
  dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Update file reference path
  if file_ref.path != rel_path
    puts "  ✓ Updating: #{file_ref.path} → #{rel_path}"
    file_ref.path = rel_path
  end
  
  # Move to correct group if needed
  if file_ref.parent != group
    file_ref.remove_from_project
    group.children << file_ref
    puts "  ✓ Moved to correct group: #{rel_path}"
  end
  
  # Ensure it's in build phase
  build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
  if build_file.nil? && rel_path.end_with?('.swift')
    target.add_file_references([file_ref])
    puts "  ✓ Added to build phase: #{rel_path}"
  end
end

# Clean up build phase - remove any entries pointing to non-existent files
puts "\n🧹 Cleaning build phase..."

build_phase.files.dup.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  file_path = file_ref.path || ''
  # Check if file exists
  if file_path && !file_path.start_with?('/')
    # Try both with and without Rockout/ prefix
    path_with_rockout = File.join(SOURCE_DIR, file_path)
    path_without_rockout = File.join(PROJECT_DIR, file_path)
    
    unless File.exist?(path_with_rockout) || File.exist?(path_without_rockout)
      # File doesn't exist - remove from build phase
      build_phase.remove_file_reference(file_ref)
      puts "  ✗ Removed non-existent file from build phase: #{file_path}"
    end
  end
end

# Save the project
begin
  project.save
  puts "\n✅ Fixed all file references and saved project!"
  puts "\n💡 Try building again - all file reference errors should be resolved."
rescue => e
  puts "\n❌ Failed to save project: #{e.message}"
  puts "   Make sure Xcode is closed and try again."
  exit 1
end

