#!/usr/bin/env ruby
# encoding: utf-8

# COMPLETE FIX: Ensure all file references are in Rockout group with correct paths

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
target = project.targets.first
build_phase = target.source_build_phase

puts "🔧 COMPLETE FIX: Rebuilding file structure..."

# Get Rockout group
rockout_group = project.main_group['Rockout'] || project.main_group.new_group('Rockout')
rockout_group.path = 'Rockout'
rockout_group.source_tree = '<group>'

# Clear build phase
build_phase.files.clear

# Get all actual Swift files
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  actual_files[rel_path] = file
end

puts "📋 Found #{actual_files.length} Swift files"

# Remove ALL existing file references (we'll recreate them)
project.files.each { |f| f.remove_from_project if f.path && f.path.end_with?('.swift') }

# Recreate all file references in correct structure
added = 0
actual_files.each do |rel_path, full_path|
  # Navigate/create groups under Rockout
  group = rockout_group
  dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Create file reference with just the filename (path relative to its group)
  filename = File.basename(rel_path)
  file_ref = group.new_file(filename)
  file_ref.path = filename  # Just filename, not full path
  file_ref.source_tree = '<group>'
  
  # Add to build phase
  build_phase.add_file_reference(file_ref)
  added += 1
end

project.save
puts "\n✅ Recreated #{added} file reference(s) in correct structure"
puts "💡 All files are now under Rockout group with correct paths"
puts "💡 Try building now!"

