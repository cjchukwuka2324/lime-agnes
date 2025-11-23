#!/usr/bin/env ruby

# Ruby script to automatically add files to Xcode project
# Requires: gem install xcodeproj
# Usage: ruby auto_add_to_xcode.rb

require 'xcodeproj'

# Auto-detect project paths
SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..'))

# Find Xcode project
xcode_projects = Dir.glob(File.join(PROJECT_DIR, '*.xcodeproj'))
if xcode_projects.empty?
  # Try parent directory
  parent_dir = File.dirname(PROJECT_DIR)
  xcode_projects = Dir.glob(File.join(parent_dir, '*.xcodeproj'))
  PROJECT_DIR = parent_dir if !xcode_projects.empty?
end

PROJECT_PATH = xcode_projects.first || File.join(PROJECT_DIR, 'Rockout.xcodeproj')

def add_file_to_project(project, file_path, group_path = nil)
  # Get relative path from Rockout directory
  rel_path = file_path.sub("#{PROJECT_DIR}/Rockout/", '')
  rel_path = rel_path.sub(/^Rockout\//, '') # Remove Rockout/ prefix if present
  
  # Start from main group (Rockout)
  group = project.main_group
  
  # Navigate to the correct sub-group based on file path
  if group_path && !group_path.empty?
    # Split group path and navigate/create groups
    group_path.split('/').each do |path_component|
      next if path_component.empty?
      
      # Look for existing group with this name
      existing = group.children.find { |g| g.display_name == path_component && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
      
      if existing
        group = existing
      else
        # Create new group
        group = group.new_group(path_component)
      end
    end
  else
    # No group path specified, try to infer from file path
    dir_path = File.dirname(rel_path)
    if dir_path != '.' && !dir_path.empty?
      dir_path.split('/').each do |component|
        next if component.empty?
        existing = group.children.find { |g| g.display_name == component && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
        group = existing || group.new_group(component)
      end
    end
  end
  
  # Check if file already exists in this group
  existing_file = group.files.find { |f| f.path == File.basename(rel_path) || f.path == rel_path }
  if existing_file
    puts "⊘ Already exists in #{group.display_name}: #{File.basename(rel_path)}"
    return
  end
  
  # Add file reference to the group
  # Use basename for the reference if group structure matches filesystem
  file_ref = group.new_file(rel_path)
  
  # Ensure file reference has correct source tree
  file_ref.source_tree = '<group>'
  
  # Add to build phases (only for Swift files)
  if rel_path.end_with?('.swift')
    target = project.targets.first
    if target
      target.add_file_references([file_ref])
    end
  end
  
  puts "✓ Added to #{group.display_name}: #{File.basename(rel_path)}"
rescue => e
  puts "✗ Failed to add #{file_path}: #{e.message}"
  puts "   Error details: #{e.backtrace.first(3).join("\n   ")}"
end

begin
  project = Xcodeproj::Project.open(PROJECT_PATH)
  
  # Read list of new files if it exists
  new_files_list = File.join(PROJECT_DIR, 'Rockout', 'new_files_to_add.txt')
  files_to_add = []
  
  if File.exist?(new_files_list)
    files_to_add = File.readlines(new_files_list).map(&:chomp).reject(&:empty?)
  else
    # Find all Swift files not in project
    Dir.glob(File.join(PROJECT_DIR, 'Rockout', '**', '*.swift')).each do |file|
      next if file.include?('.build/') || file.include?('DerivedData/') || file.include?('.git/')
      files_to_add << file
    end
  end
  
  if files_to_add.empty?
    puts "✅ No new files to add!"
    exit 0
  end
  
  puts "Found #{files_to_add.length} file(s) to add:\n\n"
  
  files_to_add.each do |file|
    # Normalize path
    file = File.expand_path(file)
    next unless File.exist?(file)
    
    # Determine group based on directory
    rel_path = file.sub("#{PROJECT_DIR}/", '')
    rel_path = rel_path.sub(/^Rockout\//, '')
    dir_path = File.dirname(rel_path)
    
    # Determine group path from directory structure
    # The rel_path is already normalized (Rockout/ prefix removed)
    dir_path = File.dirname(rel_path)
    
    # Map directories to groups
    group_path = if dir_path == '.' || dir_path.empty?
      nil  # Root level file
    else
      # Use the full directory path as group path
      # This will create/use groups like "Views/Profile", "Services/Supabase", etc.
      dir_path
    end
    
    add_file_to_project(project, file, group_path)
  end
  
  project.save
  puts "\n✅ Project updated successfully!"
  puts "   Added #{files_to_add.length} file(s) to Xcode project"
  
  # Clean up the new_files_to_add.txt file
  if File.exist?(new_files_list)
    File.delete(new_files_list)
    puts "   Cleaned up new_files_to_add.txt"
  end
rescue LoadError
  puts "Error: xcodeproj gem not installed"
  puts "Install with: gem install xcodeproj"
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5)
end

