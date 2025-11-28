#!/usr/bin/env ruby
# encoding: utf-8

# Move EditUsernameView to the correct group (Rockout/Views/Profile)

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  exit 1
end

SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

puts "🔍 Finding EditUsernameView and correct group..."

# Find EditUsernameView
eu = project.files.find { |f| f.display_name == "EditUsernameView.swift" }
if eu.nil?
  puts "❌ EditUsernameView not found!"
  exit 1
end

current_parent = eu.parent
puts "📄 Current parent: #{current_parent.name} (UUID: #{current_parent.uuid})"

# Find the CORRECT group: Rockout/Views/Profile
main_group = project.main_group
rockout_group = main_group['Rockout'] || main_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && (g.name == 'Rockout' || g.path == 'Rockout') }

if rockout_group.nil?
  puts "❌ Rockout group not found!"
  exit 1
end

views_group = rockout_group['Views'] || rockout_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.name == 'Views' }

if views_group.nil?
  puts "❌ Rockout/Views group not found!"
  exit 1
end

profile_group = views_group['Profile'] || views_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.name == 'Profile' }

if profile_group.nil?
  puts "❌ Rockout/Views/Profile group not found!"
  exit 1
end

puts "✅ Correct Profile group: #{profile_group.name} (UUID: #{profile_group.uuid})"

# Check if EditNameView is in the correct group (for reference)
en = project.files.find { |f| f.display_name == "EditNameView.swift" }
if en
  puts "📄 EditNameView parent: #{en.parent.name} (UUID: #{en.parent.uuid})"
  if en.parent == profile_group
    puts "  ✓ EditNameView is in the correct group"
  else
    puts "  ⚠️  EditNameView is in a different group"
  end
end

# If EditUsernameView is not in the correct group, move it
if eu.parent != profile_group
  puts "\n🔄 Moving EditUsernameView to correct group..."
  
  # Remove from build phase
  build_phase.remove_file_reference(eu)
  
  # Remove from current parent
  eu.remove_from_project
  
  # Add to correct group
  profile_group << eu
  
  # Ensure path is just filename
  eu.path = "EditUsernameView.swift"
  eu.name = "EditUsernameView.swift"
  
  # Re-add to build phase
  target.add_file_references([eu])
  
  puts "  ✓ Moved EditUsernameView to Rockout/Views/Profile"
else
  puts "\n✅ EditUsernameView is already in the correct group"
  
  # Still ensure path is correct
  if eu.path != "EditUsernameView.swift"
    build_phase.remove_file_reference(eu)
    eu.path = "EditUsernameView.swift"
    eu.name = "EditUsernameView.swift"
    target.add_file_references([eu])
    puts "  ✓ Fixed path to just filename"
  end
end

# Save
begin
  project.save
  puts "\n✅ Fixed EditUsernameView group location and path!"
rescue => e
  puts "\n❌ Failed to save: #{e.message}"
  exit 1
end

