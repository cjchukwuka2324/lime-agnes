#!/usr/bin/env ruby
# encoding: utf-8

# COMPREHENSIVE FIX: Ensure file references are in correct groups matching directory structure

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

puts "🔧 COMPREHENSIVE FIX: Ensuring correct group structure..."

# Get Rockout group
rockout_group = project.main_group['Rockout'] || project.main_group.new_group('Rockout')

# Get all actual files with their full paths
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  basename = File.basename(rel_path)
  actual_files[basename] = rel_path
end

puts "📋 Found #{actual_files.length} Swift files"

# Clear build phase
build_phase.files.clear

# Remove all existing file references
project.files.each { |f| f.remove_from_project if f.path && f.path.end_with?('.swift') }

# Recreate all file references in correct groups
added = 0
actual_files.each do |basename, rel_path|
  # Navigate/create groups to match directory structure
  group = rockout_group
  dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Create file reference with just filename
  file_ref = group.new_file(basename)
  file_ref.path = basename
  file_ref.source_tree = '<group>'
  
  # Add to build phase
  build_phase.add_file_reference(file_ref)
  added += 1
end

project.save
puts "\n✅ Recreated #{added} file reference(s) in correct group structure"

# Verify all paths
puts "\n🔍 Verifying all paths..."
verified = 0
errors = []

build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  filename = file_ref.path || ''
  parent = file_ref.parent
  
  # Build expected path from group hierarchy
  group_path = []
  current = parent
  while current && current != project.main_group && current != rockout_group
    group_path.unshift(current.display_name) if current.respond_to?(:display_name)
    current = current.parent
  end
  
  expected_path = group_path.empty? ? filename : "#{group_path.join('/')}/#{filename}"
  full_expected = File.join(SOURCE_DIR, expected_path)
  
  if File.exist?(full_expected)
    verified += 1
  else
    errors << "#{expected_path} (file: #{filename}, group: #{parent.display_name rescue 'unknown'})"
  end
end

puts "✅ Verified: #{verified}/#{build_phase.files.length}"
if errors.any?
  puts "\n❌ Errors found:"
  errors.first(10).each { |e| puts "  - #{e}" }
  puts "  ... (#{errors.length} total)" if errors.length > 10
else
  puts "\n✅ All paths verified correctly!"
end

puts "\n💡 Try building now!"

