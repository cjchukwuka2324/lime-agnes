#!/usr/bin/env ruby
# encoding: utf-8

# Fix: Ensure file references don't have path set, so Xcode uses group hierarchy

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

puts "🔧 Ensuring file references use group hierarchy for path resolution..."

# Get all actual files
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  basename = File.basename(rel_path)
  actual_files[basename] = rel_path
end

fixed = 0

# For each file reference, ensure it's in the correct group and path is just filename
project.files.each do |file_ref|
  next unless file_ref.path && file_ref.path.end_with?('.swift')
  
  filename = file_ref.path
  actual_path = actual_files[filename]
  next unless actual_path
  
  # Ensure file reference path is just the filename (not full path)
  if file_ref.path != filename
    file_ref.path = filename
    fixed += 1
    puts "  ✓ Fixed path: #{file_ref.path} → #{filename}"
  end
  
  # Ensure it's in correct group
  group = rockout_group
  dir_parts = File.dirname(actual_path).split('/').reject { |p| p == '.' || p.empty? }
  
  dir_parts.each do |part|
    existing = group.children.find { |g| g.display_name == part && g.is_a?(Xcodeproj::Project::Object::PBXGroup) }
    group = existing || group.new_group(part)
  end
  
  if file_ref.parent != group
    file_ref.remove_from_project
    group.children << file_ref
    fixed += 1
    puts "  ✓ Moved to group: #{filename} → #{dir_parts.join('/')}"
  end
  
  # Ensure source_tree is <group>
  if file_ref.source_tree != '<group>'
    file_ref.source_tree = '<group>'
    fixed += 1
  end
end

project.save
puts "\n✅ Fixed #{fixed} file reference(s)"

# Verify path resolution
puts "\n🔍 Verifying path resolution..."
errors = []
problem_files = ['FeedService.swift', 'FeedView.swift', 'ArtistLeaderboardViewModel.swift', 'Post.swift']

problem_files.each do |filename|
  file_ref = project.files.find { |f| f.path == filename }
  next unless file_ref
  
  # Build path from group hierarchy
  parent = file_ref.parent
  group_chain = []
  current = parent
  while current && current != rockout_group && current != project.main_group
    group_chain.unshift(current.display_name) if current.respond_to?(:display_name)
    current = current.parent
  end
  
  resolved_path = group_chain.empty? ? filename : "#{group_chain.join('/')}/#{filename}"
  expected_path = actual_files[filename]
  
  if resolved_path != expected_path
    errors << "#{filename}: resolves to #{resolved_path}, should be #{expected_path}"
  end
end

if errors.empty?
  puts "✅ All paths resolve correctly!"
else
  puts "❌ Path resolution errors:"
  errors.each { |e| puts "  - #{e}" }
end

puts "\n💡 Try building now!"

