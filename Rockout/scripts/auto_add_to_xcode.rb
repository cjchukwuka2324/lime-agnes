#!/usr/bin/env ruby
# encoding: utf-8

# Ruby script to automatically add files to Xcode project
# Requires: gem install xcodeproj
# Usage: ruby auto_add_to_xcode.rb

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  puts "   Install with: gem install xcodeproj"
  puts "   Or use: sudo gem install xcodeproj"
  exit 1
end

# Auto-detect project paths
SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))

# Find Xcode project - should be in PROJECT_DIR
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')

unless File.exist?(PROJECT_PATH)
  puts "❌ Xcode project not found at: #{PROJECT_PATH}"
  exit 1
end

puts "📦 Opening Xcode project: #{PROJECT_PATH}"

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
SOURCE_DIR = File.join(PROJECT_DIR, 'Rockout')

puts "📁 Source directory: #{SOURCE_DIR}"
puts "📦 Project directory: #{PROJECT_DIR}"

def add_file_to_project(project, target, file_path, source_dir)
  # Get relative path from SOURCE_DIR (Rockout/)
  rel_path = file_path.sub("#{source_dir}/", '')
  
  # Start from main group
  group = project.main_group
  
  # Navigate to the correct sub-group based on file path
  dir_path = File.dirname(rel_path)
  if dir_path != '.' && !dir_path.empty?
    dir_path.split('/').each do |component|
      next if component.empty?
      existing = group.children.find { |g| g.display_name == component && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
      group = existing || group.new_group(component)
    end
  end
  
  # Check if file already exists in this group
  existing_file = group.files.find { |f| 
    (f.path == rel_path) ||
    (f.path == File.basename(rel_path) && File.dirname(f.path || '') == dir_path)
  }
  
  if existing_file
    # Ensure it's in build phase
    build_phase = target.source_build_phase
    build_file = build_phase.files.find { |bf| bf.file_ref == existing_file }
    if build_file.nil? && rel_path.end_with?('.swift')
      target.add_file_references([existing_file])
      puts "✓ Added to build phase: #{rel_path}"
    else
      puts "⊘ Already exists: #{rel_path}"
    end
    return
  end
  
  # Add file reference to the group
  file_ref = group.new_file(rel_path)
  file_ref.source_tree = '<group>'
  
  # Add to build phases (only for Swift files)
  if rel_path.end_with?('.swift')
    target.add_file_references([file_ref])
  end
  
  puts "✓ Added: #{rel_path}"
rescue => e
  puts "✗ Failed to add #{file_path}: #{e.message}"
  puts "   Error details: #{e.backtrace.first(3).join("\n   ")}"
end

# Read list of files to add
new_files_list = File.join(SOURCE_DIR, 'new_files_to_add.txt')
files_to_add = []

if File.exist?(new_files_list)
  files_to_add = File.readlines(new_files_list).map(&:chomp).reject(&:empty?)
else
  # Find all Swift files in source directory
  Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
    next if file.include?('.build/') || file.include?('DerivedData/') || file.include?('.git/') || file.include?('scripts/')
    files_to_add << file
  end
end

if files_to_add.empty?
  puts "✅ No new files to add!"
  exit 0
end

puts "Found #{files_to_add.length} file(s) to add:\n\n"

files_to_add.each do |file|
  file = File.expand_path(file)
  next unless File.exist?(file)
  add_file_to_project(project, target, file, SOURCE_DIR)
end

project.save
puts "\n✅ Project saved successfully!"

# Clean up
File.delete(new_files_list) if File.exist?(new_files_list)

puts "\n🎉 All files added to Xcode project!"
