#!/usr/bin/env ruby
# encoding: utf-8

# Force fix VideoPicker with absolute path approach

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

puts "🔍 Finding and fixing VideoPicker..."

# Find VideoPicker file reference
video_picker = project.files.find { |f| f.display_name == "VideoPicker.swift" }

if video_picker.nil?
  puts "❌ VideoPicker.swift not found!"
  exit 1
end

puts "📄 Current: path=#{video_picker.path}, name=#{video_picker.name}"

# Remove from build phase
build_phase.remove_file_reference(video_picker)
puts "  ✓ Removed from build phase"

# Delete the file reference completely
video_picker.remove_from_project
puts "  ✓ Deleted old file reference"

# Now create a completely new one with the correct full path
main_group = project.main_group

# Navigate to Rockout/Views/Shared
rockout_group = main_group['Rockout'] || main_group.find_subpath('Rockout', true)
views_group = rockout_group['Views'] || rockout_group.find_subpath('Views', true)
shared_group = views_group['Shared'] || views_group.find_subpath('Shared', true)

# Create new file reference with full path
new_ref = shared_group.new_file("Rockout/Views/Shared/VideoPicker.swift")
new_ref.path = "Rockout/Views/Shared/VideoPicker.swift"
new_ref.name = "VideoPicker.swift"
new_ref.source_tree = "<group>"

puts "  ✓ Created new file reference with path: Rockout/Views/Shared/VideoPicker.swift"

# Verify file exists
full_path = File.join(PROJECT_DIR, "Rockout/Views/Shared/VideoPicker.swift")
if File.exist?(full_path)
  puts "  ✓ File exists at: #{full_path}"
else
  puts "  ❌ File does NOT exist at: #{full_path}"
end

# Add to build phase
target.add_file_references([new_ref])
puts "  ✓ Added to build phase"

# Save
begin
  project.save
  puts "\n✅ Completely recreated VideoPicker file reference!"
  puts "   Path: Rockout/Views/Shared/VideoPicker.swift"
rescue => e
  puts "\n❌ Failed to save: #{e.message}"
  exit 1
end

