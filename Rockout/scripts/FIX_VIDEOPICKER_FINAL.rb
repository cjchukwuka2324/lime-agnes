#!/usr/bin/env ruby
# encoding: utf-8

# Aggressive fix for VideoPicker.swift - remove ALL references and re-add correctly

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

puts "🔍 Finding ALL VideoPicker references..."

# Find ALL file references that might be VideoPicker
video_picker_refs = project.files.select do |f|
  f.display_name == "VideoPicker.swift" || 
  f.path&.include?("VideoPicker") ||
  f.path == "Views/Shared/VideoPicker.swift"
end

puts "📋 Found #{video_picker_refs.length} VideoPicker file reference(s):"
video_picker_refs.each do |ref|
  puts "  - Path: #{ref.path || 'nil'}, Display: #{ref.display_name || 'nil'}"
end

# Remove ALL VideoPicker entries from build phase
puts "\n🗑️  Removing ALL VideoPicker entries from build phase..."
removed_count = 0
build_phase.files.dup.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  if file_ref.display_name == "VideoPicker.swift" || 
     file_ref.path&.include?("VideoPicker") ||
     file_ref.path == "Views/Shared/VideoPicker.swift"
    build_phase.remove_file_reference(file_ref)
    removed_count += 1
    puts "  ✗ Removed from build phase: #{file_ref.path || file_ref.display_name}"
  end
end

# Delete ALL VideoPicker file references
puts "\n🗑️  Deleting ALL VideoPicker file references..."
video_picker_refs.each do |ref|
  ref.remove_from_project
  puts "  ✗ Deleted file reference: #{ref.path || ref.display_name}"
end

# Now create a fresh file reference in the correct location
puts "\n✨ Creating new VideoPicker file reference..."

# Navigate to Views/Shared group
main_group = project.main_group
views_group = main_group['Views'] || main_group.find_subpath('Views', true)
shared_group = views_group['Shared'] || views_group.find_subpath('Shared', true)

# Create new file reference with just the filename
file_ref = shared_group.new_file("VideoPicker.swift")
file_ref.path = "VideoPicker.swift"
file_ref.name = "VideoPicker.swift"
file_ref.source_tree = "<group>"

puts "  ✓ Created file reference: #{file_ref.path} in Views/Shared group"

# Add to build phase
target.add_file_references([file_ref])
puts "  ✓ Added to build phase"

# Verify the file exists
correct_path = File.join(SOURCE_DIR, "Views/Shared/VideoPicker.swift")
if File.exist?(correct_path)
  puts "  ✓ File exists at: #{correct_path}"
else
  puts "  ❌ WARNING: File does NOT exist at: #{correct_path}"
end

# Save the project
begin
  project.save
  puts "\n✅ Fixed VideoPicker.swift completely!"
  puts "   - Removed #{removed_count} old build phase entry(ies)"
  puts "   - Deleted #{video_picker_refs.length} old file reference(s)"
  puts "   - Created new file reference with correct path"
  puts "   - Added to build phase"
rescue => e
  puts "\n❌ Failed to save project: #{e.message}"
  puts "   Make sure Xcode is closed and try again."
  exit 1
end

