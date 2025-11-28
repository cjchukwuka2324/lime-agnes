#!/usr/bin/env ruby
# encoding: utf-8

# Script to fix file reference paths in Xcode project
# Updates file references to point to correct paths (with Rockout/ prefix)

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

puts "🔍 Checking for file references with incorrect paths..."

# List of files that need path fixes
files_to_fix = [
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

fixed_count = 0
removed_count = 0

# First, remove all incorrect build phase entries
puts "\n🗑️  Removing incorrect build phase entries..."

build_phase.files.dup.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  file_path = file_ref.path || file_ref.display_name || ''
  
  # Check if this is one of the files we need to fix
  if files_to_fix.any? { |f| file_path == f || file_path.end_with?("/#{f}") }
    # Check if file exists at incorrect path
    incorrect_full_path = File.join(PROJECT_DIR, file_path)
    correct_path = File.join(SOURCE_DIR, file_path)
    
    if !File.exist?(incorrect_full_path) && File.exist?(correct_path)
      # Remove from build phase
      build_phase.remove_file_reference(file_ref)
      removed_count += 1
      puts "  ✗ Removed from build phase: #{file_path}"
    end
  end
end

# Now fix file references and re-add to build phase
puts "\n🔧 Fixing file reference paths..."

files_to_fix.each do |rel_path|
  incorrect_full_path = File.join(PROJECT_DIR, rel_path)
  correct_full_path = File.join(SOURCE_DIR, rel_path)
  
  # Skip if file doesn't exist at correct path
  unless File.exist?(correct_full_path)
    puts "  ⚠️  File not found: #{rel_path}"
    next
  end
  
  # Find the file reference (might be in wrong group or have wrong path)
  file_ref = project.files.find do |f|
    f.path == rel_path || 
    f.path == "Rockout/#{rel_path}" ||
    File.basename(f.path || '') == File.basename(rel_path)
  end
  
  # Find or create the correct group
  group = project.main_group
  dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  if file_ref
    # Update the path
    if file_ref.path != rel_path
      puts "  ✓ Updating path: #{file_ref.path} → #{rel_path}"
      file_ref.path = rel_path
      fixed_count += 1
    end
    
    # Move to correct group if needed
    if file_ref.parent != group
      file_ref.remove_from_project
      group.children << file_ref
    end
    
    # Ensure it's in build phase
    build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
    if build_file.nil? && rel_path.end_with?('.swift')
      target.add_file_references([file_ref])
      puts "  ✓ Added to build phase: #{rel_path}"
    end
  else
    # Create new file reference
    file_ref = group.new_file(rel_path)
    file_ref.source_tree = '<group>'
    
    if rel_path.end_with?('.swift')
      target.add_file_references([file_ref])
      puts "  ✓ Created file reference: #{rel_path}"
      fixed_count += 1
    end
  end
end

# Save the project
begin
  project.save
  puts "\n✅ Fixed #{fixed_count} file reference(s), removed #{removed_count} incorrect entry(ies)"
  puts "\n💡 Try building again - the file reference errors should be gone."
rescue => e
  puts "\n❌ Failed to save project: #{e.message}"
  puts "   Make sure Xcode is closed and try again."
  exit 1
end

