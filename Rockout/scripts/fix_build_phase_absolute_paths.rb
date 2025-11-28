#!/usr/bin/env ruby
# encoding: utf-8

# Fix build phase to use correct paths
# The issue is Xcode is looking for files at project root instead of Rockout/

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

puts "🔍 Fixing build phase file paths..."

# Remove ALL entries from build phase
puts "\n🗑️  Clearing build phase..."
build_phase.files.clear

# Get Rockout group
rockout_group = project.main_group['Rockout']
unless rockout_group
  puts "❌ Rockout group not found!"
  exit 1
end

# Recursively find all Swift files in Rockout group
def find_swift_files(group, base_path = '')
  files = []
  group.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
      if child.path && child.path.end_with?('.swift')
        full_path = base_path.empty? ? child.path : "#{base_path}/#{child.path}"
        files << { file_ref: child, path: full_path }
      end
    elsif child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      new_base = base_path.empty? ? child.display_name : "#{base_path}/#{child.display_name}"
      files.concat(find_swift_files(child, new_base))
    end
  end
  files
end

# Find all Swift files
all_files = find_swift_files(rockout_group)

puts "\n📋 Found #{all_files.length} Swift file(s)"

# Add them to build phase with correct file references
added = 0
all_files.each do |item|
  file_ref = item[:file_ref]
  path = item[:path]
  
  # Verify file exists
  full_path = File.join(SOURCE_DIR, path)
  unless File.exist?(full_path)
    puts "  ⚠️  File not found: #{path}"
    next
  end
  
  # Add to build phase
  build_phase.add_file_reference(file_ref)
  added += 1
end

# Save
project.save
puts "\n✅ Added #{added} file(s) to build phase"
puts "💡 Try building again!"

