#!/usr/bin/env ruby
# encoding: utf-8

# Fix the group hierarchy for VideoPicker to ensure correct path resolution

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

puts "🔍 Checking group hierarchy for VideoPicker..."

# Get main group
main_group = project.main_group

# Find or create Views group
views_group = main_group['Views']
if views_group.nil?
  views_group = main_group.find_subpath('Views', true)
end

puts "📁 Views group: path=#{views_group.path || 'nil'}, name=#{views_group.name}"

# Ensure Views group path is correct
if views_group.path.nil? || views_group.path != "Views"
  views_group.path = "Views"
  puts "  ✓ Set Views group path to 'Views'"
end

# Find or create Shared group under Views
shared_group = views_group['Shared']
if shared_group.nil?
  shared_group = views_group.find_subpath('Shared', true)
end

puts "📁 Shared group: path=#{shared_group.path || 'nil'}, name=#{shared_group.name}"

# Ensure Shared group path is correct
if shared_group.path.nil? || shared_group.path != "Shared"
  shared_group.path = "Shared"
  puts "  ✓ Set Shared group path to 'Shared'"
end

# Find VideoPicker file reference
video_picker = shared_group.files.find { |f| f.display_name == "VideoPicker.swift" }

if video_picker.nil?
  puts "❌ VideoPicker.swift not found in Shared group!"
  exit 1
end

puts "📄 VideoPicker.swift: path=#{video_picker.path || 'nil'}, name=#{video_picker.name}"

# Ensure VideoPicker has correct path
if video_picker.path != "VideoPicker.swift"
  video_picker.path = "VideoPicker.swift"
  video_picker.name = "VideoPicker.swift"
  puts "  ✓ Set VideoPicker path to 'VideoPicker.swift'"
end

# Verify the full path resolution
full_path = File.join(SOURCE_DIR, "Views", "Shared", "VideoPicker.swift")
if File.exist?(full_path)
  puts "  ✓ File exists at: #{full_path}"
else
  puts "  ❌ File does NOT exist at: #{full_path}"
end

# Save the project
begin
  project.save
  puts "\n✅ Fixed group hierarchy!"
  puts "   Views group path: #{views_group.path}"
  puts "   Shared group path: #{shared_group.path}"
  puts "   VideoPicker path: #{video_picker.path}"
  puts "\n💡 The file should now resolve to: Rockout/Views/Shared/VideoPicker.swift"
rescue => e
  puts "\n❌ Failed to save project: #{e.message}"
  puts "   Make sure Xcode is closed and try again."
  exit 1
end

