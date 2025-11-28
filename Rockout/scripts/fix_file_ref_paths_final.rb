#!/usr/bin/env ruby
# encoding: utf-8

# Final fix: Update all file reference paths to be correct
# Files should have paths relative to Rockout group, not project root

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

puts "🔍 Fixing all file reference paths..."

# Get all Swift files that actually exist
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  actual_files[rel_path] = file
end

puts "📋 Found #{actual_files.length} actual Swift files"

# Clear build phase
build_phase.files.clear

# Fix all file references
fixed = 0
added = 0

actual_files.each do |rel_path, full_path|
  # Find file reference by searching all groups
  file_ref = nil
  
  def find_file_in_groups(groups, target_path)
    groups.each do |group|
      if group.is_a?(Xcodeproj::Project::Object::PBXGroup)
        group.files.each do |f|
          if f.path && (f.path == target_path || File.basename(f.path) == File.basename(target_path))
            return f
          end
        end
        found = find_file_in_groups(group.children, target_path)
        return found if found
      end
    end
    nil
  end
  
  file_ref = find_file_in_groups([project.main_group], rel_path)
  
  # If not found, create it in correct group
  if file_ref.nil?
    group = project.main_group
    dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' || p.empty? }
    
    dir_parts.each do |part|
      existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
      group = existing || group.new_group(part)
    end
    
    file_ref = group.new_file(rel_path)
    file_ref.source_tree = '<group>'
    fixed += 1
    puts "  ✓ Created: #{rel_path}"
  else
    # Update path if incorrect
    if file_ref.path != rel_path
      file_ref.path = rel_path
      fixed += 1
      puts "  ✓ Fixed: #{file_ref.path} → #{rel_path}"
    end
  end
  
  # Add to build phase
  build_phase.add_file_reference(file_ref)
  added += 1
end

project.save
puts "\n✅ Fixed #{fixed} file reference(s), added #{added} to build phase"
puts "💡 Try building now!"

