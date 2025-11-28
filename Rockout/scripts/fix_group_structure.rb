#!/usr/bin/env ruby
# encoding: utf-8

# Fix group structure - ensure all files are under Rockout group
# or have Rockout/ prefix in their paths

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

puts "🔍 Fixing group structure..."

# Get or create Rockout group
rockout_group = project.main_group['Rockout']
if rockout_group.nil?
  rockout_group = project.main_group.new_group('Rockout')
  puts "✓ Created Rockout group"
end

# Find all file references that need to be moved
files_to_move = []

project.files.each do |file_ref|
  next unless file_ref.path && file_ref.path.end_with?('.swift')
  
  # Check if file exists at Rockout/ path
  rockout_path = File.join(SOURCE_DIR, file_ref.path)
  if File.exist?(rockout_path)
    # File is in Rockout/ but reference might not be in Rockout group
    parent = file_ref.parent
    in_rockout_group = false
    current = parent
    while current && current != project.main_group
      if current.display_name == 'Rockout'
        in_rockout_group = true
        break
      end
      current = current.parent
    end
    
    unless in_rockout_group
      files_to_move << {
        file_ref: file_ref,
        path: file_ref.path,
        current_group: parent
      }
    end
  end
end

puts "\n📦 Moving #{files_to_move.length} file(s) to Rockout group structure..."

moved = 0
files_to_move.each do |item|
  file_ref = item[:file_ref]
  rel_path = item[:path]
  
  # Navigate to correct sub-group within Rockout
  group = rockout_group
  dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Move file reference
  if file_ref.parent != group
    file_ref.remove_from_project
    group.children << file_ref
    moved += 1
    puts "  ✓ Moved: #{rel_path}"
  end
end

# Now ensure all build phase entries use correct file references
puts "\n🔧 Verifying build phase..."

build_phase.files.dup.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  file_path = file_ref.path || ''
  rockout_path = File.join(SOURCE_DIR, file_path)
  
  # If file doesn't exist at this path, remove from build phase
  unless File.exist?(rockout_path)
    build_phase.remove_file_reference(file_ref)
    puts "  ✗ Removed non-existent: #{file_path}"
  end
end

project.save
puts "\n✅ Moved #{moved} file(s) to Rockout group structure"
puts "💡 Try building again!"

