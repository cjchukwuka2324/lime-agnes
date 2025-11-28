#!/usr/bin/env ruby
# encoding: utf-8

# Set VideoPicker to use full relative path from project root

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

puts "🔍 Finding VideoPicker file reference..."

# Find VideoPicker
video_picker = project.files.find { |f| f.display_name == "VideoPicker.swift" }

if video_picker.nil?
  puts "❌ VideoPicker.swift not found!"
  exit 1
end

puts "📄 Found: path=#{video_picker.path || 'nil'}"

# Remove from build phase first
build_phase.remove_file_reference(video_picker)

# Set the full relative path
video_picker.path = "Rockout/Views/Shared/VideoPicker.swift"
video_picker.name = "VideoPicker.swift"
video_picker.source_tree = "<group>"

puts "  ✓ Set path to: Rockout/Views/Shared/VideoPicker.swift"

# Verify file exists
full_path = File.join(PROJECT_DIR, video_picker.path)
if File.exist?(full_path)
  puts "  ✓ File exists at: #{full_path}"
else
  puts "  ❌ File does NOT exist at: #{full_path}"
end

# Re-add to build phase
target.add_file_references([video_picker])
puts "  ✓ Re-added to build phase"

# Save the project
begin
  project.save
  puts "\n✅ Fixed VideoPicker with full path!"
  puts "   Path: Rockout/Views/Shared/VideoPicker.swift"
rescue => e
  puts "\n❌ Failed to save project: #{e.message}"
  puts "   Make sure Xcode is closed and try again."
  exit 1
end

