#!/usr/bin/env ruby
# encoding: utf-8

# Move VideoPicker to the correct group (Rockout/Views/Shared, not root Views/Shared)

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

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

puts "🔍 Finding VideoPicker and correct group..."

# Find VideoPicker
video_picker = project.files.find { |f| f.display_name == "VideoPicker.swift" }

if video_picker.nil?
  puts "❌ VideoPicker not found!"
  exit 1
end

current_parent = video_picker.parent
puts "📄 VideoPicker current parent: #{current_parent.name} (path: #{current_parent.path || 'nil'})"

# Find the CORRECT group: Rockout/Views/Shared
main_group = project.main_group
rockout_group = main_group['Rockout']
if rockout_group.nil?
  rockout_group = main_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.path == 'Rockout' }
end

if rockout_group.nil?
  puts "❌ Rockout group not found!"
  exit 1
end

views_group = rockout_group['Views']
if views_group.nil?
  views_group = rockout_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.name == 'Views' }
end

if views_group.nil?
  puts "❌ Rockout/Views group not found!"
  exit 1
end

shared_group = views_group['Shared']
if shared_group.nil?
  shared_group = views_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.name == 'Shared' }
end

if shared_group.nil?
  puts "❌ Rockout/Views/Shared group not found!"
  exit 1
end

puts "✅ Found correct group: Rockout/Views/Shared (path: #{shared_group.path || 'nil'})"

# Check if ImagePicker is in the same group (for reference)
image_picker = project.files.find { |f| f.display_name == "ImagePicker.swift" }
if image_picker
  puts "📄 ImagePicker parent: #{image_picker.parent.name} (path: #{image_picker.parent.path || 'nil'})"
  if image_picker.parent == shared_group
    puts "  ✓ ImagePicker is in the correct group"
  else
    puts "  ⚠️  ImagePicker is in a different group - this might be the issue"
  end
end

# If VideoPicker is not in the correct group, move it
if video_picker.parent != shared_group
  puts "\n🔄 Moving VideoPicker to correct group..."
  
  # Remove from build phase first
  build_phase.remove_file_reference(video_picker)
  
  # Remove from current parent
  video_picker.remove_from_project
  
  # Add to correct group
  shared_group << video_picker
  
  # Re-add to build phase
  target.add_file_references([video_picker])
  
  puts "  ✓ Moved VideoPicker to Rockout/Views/Shared"
else
  puts "\n✅ VideoPicker is already in the correct group"
end

# Save
begin
  project.save
  puts "\n✅ Fixed VideoPicker group location!"
  puts "   VideoPicker is now in: Rockout/Views/Shared"
rescue => e
  puts "\n❌ Failed to save: #{e.message}"
  exit 1
end

