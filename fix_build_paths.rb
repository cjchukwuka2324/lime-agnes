#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

PROJECT_PATH = 'Rockout.xcodeproj'
SOURCE_DIR = 'Rockout'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

# Files that need fixing
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

# Find all file references
file_refs = {}
files_to_fix.each do |file_path|
  file_ref = project.files.find { |f| f.path == file_path }
  if file_ref
    file_refs[file_path] = file_ref
    puts "Found file ref: #{file_path}"
  else
    puts "WARNING: File ref not found: #{file_path}"
  end
end

# Remove ALL build files for these files
build_phase.files.dup.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  # Check if this is one of our files by basename
  basename = File.basename(file_ref.path || '')
  if files_to_fix.any? { |f| File.basename(f) == basename }
    puts "Removing build file: #{file_ref.path}"
    build_phase.remove_file_reference(file_ref)
  end
end

# Re-add all files with correct file references
file_refs.each do |file_path, file_ref|
  build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
  if build_file.nil?
    build_phase.add_file_reference(file_ref)
    puts "Added to build phase: #{file_path}"
  end
end

project.save
puts "Fixed all build phase paths"

