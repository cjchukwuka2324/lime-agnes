#!/usr/bin/env ruby
# encoding: utf-8

# Script to fix duplicate file references in Xcode build phases
# This removes duplicate entries that cause "Multiple commands produce" errors

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  puts "   Install with: gem install xcodeproj"
  exit 1
end

# Auto-detect project paths
SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')

unless File.exist?(PROJECT_PATH)
  puts "❌ Xcode project not found at: #{PROJECT_PATH}"
  exit 1
end

puts "📦 Opening Xcode project: #{PROJECT_PATH}"

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

puts "🔍 Checking for duplicate build files..."

# Track files by their normalized path to find duplicates
seen_files = {}
duplicates = []
files_to_remove = []

build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  # Get the file path or name
  file_path = file_ref.path || file_ref.display_name || ''
  
  # Normalize the path - use basename as key since Xcode can store paths differently
  basename = File.basename(file_path)
  
  # Also try to get a unique identifier
  file_id = file_ref.uuid
  
  # Check if we've seen this file before (by basename)
  if seen_files[basename]
    # This is a duplicate
    duplicates << {
      build_file: build_file,
      file_ref: file_ref,
      path: file_path,
      basename: basename,
      existing: seen_files[basename]
    }
    files_to_remove << build_file
  else
    # First time seeing this file - keep it
    seen_files[basename] = {
      build_file: build_file,
      file_ref: file_ref,
      path: file_path,
      basename: basename
    }
  end
end

if duplicates.empty?
  puts "✅ No duplicate build files found!"
  exit 0
end

puts "\n📋 Found #{duplicates.length} duplicate(s):\n\n"

# Show what will be removed
duplicates.each do |dup|
  puts "  ✗ Removing duplicate: #{dup[:basename]}"
  puts "     Path: #{dup[:path]}" if dup[:path] && !dup[:path].empty?
end

# Remove duplicates
removed_count = 0
files_to_remove.each do |build_file|
  file_ref = build_file.file_ref
  build_phase.remove_file_reference(file_ref)
  removed_count += 1
end

# Save the project
begin
  project.save
  puts "\n✅ Removed #{removed_count} duplicate(s) and saved project!"
  puts "\n💡 Try building again - the 'Multiple commands produce' errors should be gone."
rescue => e
  puts "\n❌ Failed to save project: #{e.message}"
  puts "   Make sure Xcode is closed and try again."
  exit 1
end
