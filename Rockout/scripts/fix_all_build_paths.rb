#!/usr/bin/env ruby
# encoding: utf-8

# Comprehensive fix for all build path issues
# 1. Remove ALL incorrect build phase entries
# 2. Re-add all files with correct paths

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

puts "🔍 Analyzing build phase..."

# Get all Swift files that actually exist
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  actual_files[rel_path] = file
end

puts "📋 Found #{actual_files.length} Swift files in Rockout/"

# Remove ALL build phase entries that point to incorrect paths
puts "\n🗑️  Removing incorrect build phase entries..."

removed_count = 0
build_phase.files.dup.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  file_path = file_ref.path || ''
  
  # Check if this path is incorrect
  incorrect = false
  
  # Path without Rockout/ prefix
  if file_path && !file_path.start_with?('Rockout/') && !file_path.start_with?('/')
    full_path = File.join(PROJECT_DIR, file_path)
    if !File.exist?(full_path)
      incorrect = true
    end
  end
  
  # Path with double nesting (e.g., Rockout/ViewModels/ViewModels/...)
  if file_path && file_path.include?('/ViewModels/ViewModels/') || 
     file_path.include?('/Models/Models/') || 
     file_path.include?('/Views/Views/') ||
     file_path.include?('/Services/Services/')
    incorrect = true
  end
  
  if incorrect
    build_phase.remove_file_reference(file_ref)
    removed_count += 1
    puts "  ✗ Removed: #{file_path}"
  end
end

puts "\n✅ Removed #{removed_count} incorrect entries"

# Now ensure all actual files are in build phase with correct paths
puts "\n🔧 Adding files with correct paths..."

added_count = 0
skipped_count = 0

actual_files.each do |rel_path, full_path|
  # Navigate to correct group
  group = project.main_group
  dir_parts = rel_path.split('/')[0..-2] # All but filename
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  # Find or create file reference
  file_ref = group.files.find { |f| f.path == rel_path }
  
  if file_ref.nil?
    # Create new file reference
    file_ref = group.new_file(rel_path)
    file_ref.source_tree = '<group>'
    puts "  ✓ Created: #{rel_path}"
  else
    # Update path if incorrect
    if file_ref.path != rel_path
      file_ref.path = rel_path
      puts "  ✓ Fixed path: #{rel_path}"
    end
  end
  
  # Ensure in build phase
  build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
  if build_file.nil?
    target.add_file_references([file_ref])
    added_count += 1
  else
    skipped_count += 1
  end
end

# Save
project.save
puts "\n✅ Added #{added_count} file(s), skipped #{skipped_count} (already in build phase)"
puts "💡 Try building again!"

