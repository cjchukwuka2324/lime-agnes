#!/usr/bin/env ruby
# encoding: utf-8

# Fix all file references to use just filename instead of full paths
# This prevents the "Views/Views/..." path doubling issue

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

puts "🔍 Finding files with incorrect paths..."

fixed_count = 0
project.files.each do |file_ref|
  next unless file_ref.path
  next if file_ref.path == File.basename(file_ref.path) # Already correct
  
  # Check if path contains slashes (indicating full path instead of just filename)
  if file_ref.path.include?('/')
    old_path = file_ref.path
    filename = File.basename(file_ref.path)
    
    # Remove from build phase
    build_phase.remove_file_reference(file_ref)
    
    # Fix the path
    file_ref.path = filename
    file_ref.name = filename
    
    # Re-add to build phase if it's a Swift file
    if filename.end_with?('.swift')
      target.add_file_references([file_ref])
    end
    
    puts "  ✓ Fixed: #{old_path} → #{filename}"
    fixed_count += 1
  end
end

if fixed_count > 0
  begin
    project.save
    puts "\n✅ Fixed #{fixed_count} file reference(s)!"
  rescue => e
    puts "\n❌ Failed to save: #{e.message}"
    exit 1
  end
else
  puts "\n✅ All file references are correct!"
end

