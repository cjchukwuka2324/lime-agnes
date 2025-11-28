#!/usr/bin/env ruby
# encoding: utf-8

# Remove duplicate SharedFilters.swift entries

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  exit 1
end

SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

puts "🔧 Removing duplicate SharedFilters.swift entries..."

# Find all SharedFilters.swift file references
all_refs = project.files.select { |f| f.path == 'SharedFilters.swift' }
puts "Found #{all_refs.length} file reference(s)"

# Keep the first one, remove others
if all_refs.length > 1
  kept = all_refs.first
  duplicates = all_refs[1..-1]
  
  puts "\nKeeping: #{kept.uuid} (in #{kept.parent.display_name rescue 'unknown'})"
  
  duplicates.each do |dup|
    # Remove from build phase
    build_phase.files.each do |bf|
      if bf.file_ref == dup
        build_phase.remove_file_reference(dup)
        puts "  ✗ Removed from build phase: #{dup.uuid}"
      end
    end
    
    # Remove from project
    dup.remove_from_project
    puts "  ✗ Removed file reference: #{dup.uuid}"
  end
end

# Remove duplicate build phase entries
seen_refs = {}
removed = 0

build_phase.files.dup.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref && file_ref.path == 'SharedFilters.swift'
  
  if seen_refs[file_ref.uuid]
    build_phase.remove_file_reference(file_ref)
    removed += 1
    puts "  ✗ Removed duplicate build phase entry: #{file_ref.uuid}"
  else
    seen_refs[file_ref.uuid] = true
  end
end

project.save
puts "\n✅ Removed #{removed} duplicate(s)"
puts "💡 Try building now!"

