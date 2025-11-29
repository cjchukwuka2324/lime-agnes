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
  
  # Start from Rockout group (not main group) to avoid duplicate groups
  main_group = project.main_group
  group = main_group['Rockout'] || main_group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && (g.name == 'Rockout' || g.path == 'Rockout') }
  
  if group.nil?
    # Fallback to main group if Rockout group doesn't exist
    group = project.main_group
  end
  
  # Navigate to the correct sub-group based on file path
  dir_path = File.dirname(rel_path)
  if dir_path != '.' && !dir_path.empty?
    dir_path.split('/').each do |component|
      next if component.empty?
      # Look for existing group by name (prefer groups under Rockout)
      existing = group.children.find { |g| g.is_a?(Xcodeproj::Project::Object::PBXGroup) && g.name == component }
      group = existing || group.new_group(component)
    end
  end
  
  # Check if file already exists in this group
  existing_file = group.files.find { |f| 
    (f.path == rel_path) ||
    (f.path == File.basename(rel_path) && File.dirname(f.path || '') == dir_path)
  }
  
  if existing_file
    # Check if it's already in build phase (check by file ref, not just basename)
    build_phase = target.source_build_phase
    build_file = build_phase.files.find { |bf| bf.file_ref == existing_file }
    if build_file.nil? && rel_path.end_with?('.swift')
      # Also check if any other file ref with same basename is in build phase
      basename = File.basename(rel_path)
      already_in_build = build_phase.files.any? do |bf|
        bf.file_ref && File.basename(bf.file_ref.path || bf.file_ref.display_name || '') == basename
      end
      
      if already_in_build
        puts "⊘ Already in build phase (duplicate): #{rel_path}"
      else
        target.add_file_references([existing_file])
        puts "✓ Added to build phase: #{rel_path}"
      end
    else
      puts "⊘ Already exists: #{rel_path}"
    end
    return
  end
  
  # Check if a file with the same basename is already in build phase
  basename = File.basename(rel_path)
  build_phase = target.source_build_phase
  already_in_build = build_phase.files.any? do |bf|
    bf.file_ref && File.basename(bf.file_ref.path || bf.file_ref.display_name || '') == basename
  end
  
  if already_in_build
    puts "⊘ Skipping (already in build phase): #{rel_path}"
    return
  end
  
  # Add file reference to the group - use just the filename, not the full path
  # The group hierarchy will handle the path resolution
  filename = File.basename(rel_path)
  full_file_path = File.join(source_dir, rel_path)
  
  # CRITICAL: Ensure file exists first, then create file reference (not group)
  unless File.exist?(full_file_path)
    puts "⚠️  File does not exist: #{full_file_path}"
    return
  end
  
  # Create file reference - xcodeproj will create PBXFileReference for existing files
  file_ref = group.new_file(full_file_path)
  
  # Double-check it's a file reference, not a group (should never happen for existing files)
  if file_ref.isa == 'PBXGroup'
    puts "⚠️  ERROR: Created group instead of file reference for #{rel_path}"
    file_ref.remove_from_project
    # Force create as file reference
    file_ref = group.new_reference(full_file_path)
  end
  
  # Set path to just filename (group hierarchy handles the rest)
  file_ref.path = filename if file_ref.path != filename
  file_ref.source_tree = '<group>' if file_ref.source_tree != '<group>'
  
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
  # Silently exit if no files to add (common case)
  exit 0
end

# Process files
files_to_add.each do |file|
  file = File.expand_path(file)
  next unless File.exist?(file)
  begin
    add_file_to_project(project, target, file, SOURCE_DIR)
  rescue => e
    # Log error but continue processing other files
    STDERR.puts "Warning: Failed to add #{file}: #{e.message}" if ENV['DEBUG']
  end
end

# Save project (wrap in error handling)
# Note: This might fail if Xcode has the project file open, which is OK
begin
  project.save
rescue => e
  # Silently ignore save errors (project might be locked by Xcode)
  # This is expected behavior - files will be added on next build
end

# Clean up
begin
  File.delete(new_files_list) if File.exist?(new_files_list)
rescue
  # Ignore cleanup errors
end

# Always exit successfully
exit 0
