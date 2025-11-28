#!/usr/bin/env ruby
# encoding: utf-8

# Fix: File references should have just filename, not full path
# Xcode resolves paths as: group_path + file_ref.path

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

puts "🔧 Fixing file reference paths to use just filenames..."

# Get all actual files
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  basename = File.basename(rel_path)
  actual_files[basename] = rel_path
end

fixed = 0
project.files.each do |file_ref|
  next unless file_ref.path && file_ref.path.end_with?('.swift')
  
  current_path = file_ref.path
  basename = File.basename(current_path)
  
  # If path includes directory (not just filename), fix it
  if current_path.include?('/')
    # Update to just filename
    file_ref.path = basename
    fixed += 1
    puts "  ✓ Fixed: #{current_path} → #{basename}"
  end
end

project.save
puts "\n✅ Fixed #{fixed} file reference(s) to use just filenames"
puts "💡 Try building now!"

