#!/usr/bin/env ruby
# encoding: utf-8

# FINAL FIX: Match file reference paths to actual file locations

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

puts "🔧 FINAL FIX: Matching file paths to actual locations..."

# Get all actual Swift files with their full relative paths
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  basename = File.basename(rel_path)
  actual_files[basename] = rel_path  # Store by basename for lookup
end

puts "📋 Found #{actual_files.length} Swift files"

# Fix all file references
fixed = 0
build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  current_path = file_ref.path || ''
  basename = File.basename(current_path)
  
  # Find the actual file location
  actual_path = actual_files[basename]
  
  if actual_path && actual_path != current_path
    # Update the path
    file_ref.path = actual_path
    fixed += 1
    puts "  ✓ Fixed: #{current_path} → #{actual_path}"
  elsif actual_path.nil?
    puts "  ⚠️  File not found: #{basename}"
  end
end

# Save
project.save
puts "\n✅ Fixed #{fixed} file reference path(s)"
puts "💡 Try building now!"

