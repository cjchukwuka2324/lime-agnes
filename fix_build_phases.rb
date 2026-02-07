#!/usr/bin/env ruby
# Script to fix build phases by removing bad file references

require 'xcodeproj'

project_path = 'Rockout.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Rockout' }
unless target
  puts "❌ Could not find 'Rockout' target"
  exit(1)
end

# Files to fix
files_to_fix = ['Logger.swift', 'Analytics.swift', 'PerformanceMetrics.swift', 'RequestCoalescer.swift', 'RetryPolicy.swift']

puts "Cleaning build phases..."

# Get all build files in compile sources
build_files_to_remove = []
target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  path = file_ref.path || ''
  filename = File.basename(path)
  
  # Check if this is one of our files with a bad path
  if files_to_fix.include?(filename)
    # Check if path is duplicated (bad)
    if path.include?('Rockout/Rockout') || path.include?('Utils/Utils') || path.include?('Services/Services')
      puts "  Removing bad build file: #{path}"
      build_files_to_remove << build_file
    end
  end
end

# Remove bad build files
build_files_to_remove.each do |build_file|
  target.source_build_phase.remove_file_reference(build_file.file_ref)
end

# Also remove the file references themselves if they have bad paths
project.files.each do |file_ref|
  next unless file_ref.path
  filename = File.basename(file_ref.path)
  
  if files_to_fix.include?(filename)
    path = file_ref.path
    if path.include?('Rockout/Rockout') || path.include?('Utils/Utils') || path.include?('Services/Services')
      puts "  Removing bad file reference: #{path}"
      file_ref.remove_from_project
    end
  end
end

# Save the project
project.save
puts "\n✅ Build phases cleaned!"

