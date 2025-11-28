#!/usr/bin/env ruby
# encoding: utf-8

# Fix VideoPicker.swift file reference path

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
target = project.targets.first
build_phase = target.source_build_phase

puts "🔍 Fixing VideoPicker.swift file reference..."

# Find the VideoPicker file reference
file_ref = project.files.find { |f| f.path == "Views/Shared/VideoPicker.swift" || f.display_name == "VideoPicker.swift" }

if file_ref.nil?
  puts "❌ VideoPicker.swift file reference not found!"
  exit 1
end

puts "📋 Found file reference: #{file_ref.path || file_ref.display_name}"

# Check if file exists at correct location
correct_path = File.join(SOURCE_DIR, "Views/Shared/VideoPicker.swift")
if !File.exist?(correct_path)
  puts "❌ File does not exist at: #{correct_path}"
  exit 1
end

# Fix the path - set it to just the filename, let the group structure handle the path
file_ref.path = "VideoPicker.swift"
file_ref.name = "VideoPicker.swift"

# Ensure it's in the correct group
main_group = project.main_group
views_group = main_group['Views'] || main_group.find_subpath('Views', true)
shared_group = views_group['Shared'] || views_group.find_subpath('Shared', true)

# Move file reference to correct group if needed
if file_ref.parent != shared_group
  file_ref.remove_from_project
  shared_group << file_ref
  puts "  ✓ Moved to correct group: Views/Shared"
end

# Ensure it's in the build phase
build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
if build_file.nil?
  target.add_file_references([file_ref])
  puts "  ✓ Added to build phase"
else
  puts "  ✓ Already in build phase"
end

# Save the project
begin
  project.save
  puts "\n✅ Fixed VideoPicker.swift file reference!"
  puts "   Path: #{file_ref.path}"
  puts "   Group: Views/Shared"
rescue => e
  puts "\n❌ Failed to save project: #{e.message}"
  puts "   Make sure Xcode is closed and try again."
  exit 1
end

