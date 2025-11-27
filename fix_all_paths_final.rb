#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

PROJECT_PATH = 'Rockout.xcodeproj'
SOURCE_DIR = 'Rockout'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

# Remove ALL incorrect build files for these specific files
files_to_fix = [
  'Views/SoundPrint/Features/ListeningStatsView.swift',
  'Views/SoundPrint/Features/TimeAnalysisView.swift',
  'Views/SoundPrint/Features/DiscoveryView.swift',
  'Views/SoundPrint/Features/SocialSharingView.swift',
  'Views/SoundPrint/Features/MoodContextView.swift',
  'Views/SoundPrint/Features/AdvancedAnalyticsView.swift',
  'ViewModels/SharedAlbumHandler.swift',
  'Views/StudioSessions/AcceptSharedAlbumView.swift'
]

# Get all file references first
file_refs = {}

files_to_fix.each do |file_path|
  full_path = File.join(SOURCE_DIR, file_path)
  next unless File.exist?(full_path)
  
  # Find existing file ref or create new one
  file_ref = project.files.find { |f| f.path == file_path }
  
  if file_ref.nil?
    # Create file reference in correct group
    parts = file_path.split('/')
    current_group = project.main_group
    
    parts[0..-2].each do |part|
      next_group = current_group[part]
      if next_group.nil?
        next_group = current_group.new_group(part)
      end
      current_group = next_group
    end
    
    file_ref = current_group.new_file(file_path)
    puts "Created file reference: #{file_path}"
  else
    # Ensure path is correct
    file_ref.path = file_path
    puts "Updated file reference: #{file_path}"
  end
  
  file_refs[file_path] = file_ref
end

# Remove ALL build files for these files (including incorrect ones)
build_phase.files.dup.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  path = file_ref.path
  basename = File.basename(path || '')
  
  # Remove if it's one of our files (by basename match)
  if files_to_fix.any? { |f| File.basename(f) == basename }
    puts "Removing build file: #{path}"
    build_phase.remove_file_reference(file_ref)
  end
end

# Re-add all files with correct references
file_refs.each do |file_path, file_ref|
  build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
  if build_file.nil?
    build_phase.add_file_reference(file_ref)
    puts "Added to build phase: #{file_path}"
  end
end

project.save
puts "All paths fixed successfully!"

