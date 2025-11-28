#!/usr/bin/env ruby
# encoding: utf-8

# Set explicit paths on groups to match directory structure

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  exit 1
end

SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')
SOURCE_DIR = File.join(PROJECT_DIR, 'Rockout')

project = Xcodeproj::Project.open(PROJECT_PATH)
rockout_group = project.main_group['Rockout'] || project.main_group

puts "🔧 Setting explicit paths on groups..."

def set_group_paths(group, base_path = '')
  # Set path for this group
  if group.display_name != 'Rockout' && group.display_name != 'Main Group'
    group.path = group.display_name
    group.source_tree = '<group>'
  end
  
  # Recursively set paths for children
  group.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      new_path = base_path.empty? ? child.display_name : "#{base_path}/#{child.display_name}"
      set_group_paths(child, new_path)
    end
  end
end

set_group_paths(rockout_group)

project.save
puts "✅ Set paths on all groups"

# Verify
puts "\n🔍 Verifying group paths..."
feed_group = rockout_group['Services']['Feed'] rescue nil
if feed_group
  puts "Feed group path: #{feed_group.path rescue 'nil'}"
  puts "Feed group sourceTree: #{feed_group.source_tree rescue 'nil'}"
end

puts "\n💡 Try building now!"

