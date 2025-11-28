#!/usr/bin/env ruby
# encoding: utf-8

# Fix group hierarchy to match directory structure exactly

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

puts "🔧 Fixing group hierarchy..."

# Get all actual files with their full paths
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  basename = File.basename(rel_path)
  actual_files[basename] = rel_path
end

moved = 0

# Process each file reference
project.files.each do |file_ref|
  next unless file_ref.path && file_ref.path.end_with?('.swift')
  
  filename = file_ref.path
  actual_path = actual_files[filename]
  next unless actual_path
  
  # Build correct group hierarchy from actual path
  group = rockout_group
  dir_parts = File.dirname(actual_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Move file reference if in wrong group
  current_parent = file_ref.parent
  expected_parent_name = dir_parts.last || 'Rockout'
  
  if current_parent.display_name != expected_parent_name || current_parent != group
    file_ref.remove_from_project
    group.children << file_ref
    moved += 1
    current_path = current_parent.display_name rescue 'unknown'
    puts "  ✓ Moved: #{filename} from '#{current_path}' to '#{expected_parent_name}' (#{actual_path})"
  end
end

project.save
puts "\n✅ Moved #{moved} file reference(s)"

# Final verification
puts "\n🔍 Final verification..."
errors = []
build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  filename = file_ref.path || ''
  actual_path = actual_files[filename]
  next unless actual_path
  
  # Build expected path from group hierarchy
  parent = file_ref.parent
  group_chain = []
  current = parent
  while current && current != rockout_group && current != project.main_group
    group_chain.unshift(current.display_name) if current.respond_to?(:display_name)
    current = current.parent
  end
  
  expected_path = group_chain.empty? ? filename : "#{group_chain.join('/')}/#{filename}"
  full_expected = File.join(SOURCE_DIR, expected_path)
  
  unless File.exist?(full_expected)
    errors << "#{filename}: expected #{expected_path}, but file is at #{actual_path}"
  end
end

if errors.empty?
  puts "✅ All paths verified correctly!"
else
  puts "❌ Found #{errors.length} path error(s):"
  errors.first(10).each { |e| puts "  - #{e}" }
end

puts "\n💡 Try building now!"

