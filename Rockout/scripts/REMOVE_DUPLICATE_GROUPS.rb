#!/usr/bin/env ruby
# encoding: utf-8

# Remove duplicate groups and ensure correct structure

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
rockout_group = project.main_group['Rockout'] || project.main_group

puts "🔧 Removing duplicate groups and fixing structure..."

# Get all actual files
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  basename = File.basename(rel_path)
  actual_files[basename] = rel_path
end

# Clear build phase
build_phase.files.clear

# Remove all file references
project.files.each { |f| f.remove_from_project if f.path && f.path.end_with?('.swift') }

# Remove all groups under Rockout (we'll recreate them)
groups_to_remove = []
rockout_group.children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
    groups_to_remove << child
  end
end
groups_to_remove.each { |g| g.remove_from_project }

# Recreate groups and file references correctly
added = 0
actual_files.each do |basename, rel_path|
  # Create group hierarchy
  group = rockout_group
  dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    if existing
      group = existing
    else
      group = group.new_group(part)
      group.path = part
      group.source_tree = '<group>'
    end
  end
  
  # Create file reference
  file_ref = group.new_file(basename)
  file_ref.path = basename
  file_ref.source_tree = '<group>'
  
  # Add to build phase
  build_phase.add_file_reference(file_ref)
  added += 1
end

project.save
puts "\n✅ Recreated #{added} file reference(s) in clean structure"

# Final verification
puts "\n🔍 Final verification..."
errors = []
build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  filename = file_ref.path || ''
  actual_path = actual_files[filename]
  next unless actual_path
  
  # Build path from group hierarchy
  parent = file_ref.parent
  group_chain = []
  current = parent
  while current && current != rockout_group && current != project.main_group
    group_chain.unshift(current.display_name) if current.respond_to?(:display_name)
    current = current.parent
  end
  
  resolved_path = group_chain.empty? ? filename : "#{group_chain.join('/')}/#{filename}"
  
  unless resolved_path == actual_path
    errors << "#{filename}: resolves to #{resolved_path}, should be #{actual_path}"
  end
end

if errors.empty?
  puts "✅ All paths verified correctly!"
else
  puts "❌ Found #{errors.length} error(s):"
  errors.first(10).each { |e| puts "  - #{e}" }
end

puts "\n💡 Try building now!"

