#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

PROJECT_PATH = 'Rockout.xcodeproj'
SOURCE_DIR = 'Rockout'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

# Remove incorrect build files and re-add with correct paths
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

# Remove all incorrect build files
build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  path = file_ref.path
  if path && (path.start_with?('/Users/suinoikhioda/Desktop/RockOut/') || 
              files_to_fix.any? { |f| path.include?(File.basename(f)) })
    puts "Removing incorrect build file: #{path}"
    build_phase.remove_file_reference(file_ref)
  end
end

# Re-add files with correct paths
files_to_fix.each do |file_path|
  full_path = File.join(SOURCE_DIR, file_path)
  next unless File.exist?(full_path)
  
  # Find or create file reference
  file_ref = project.files.find { |f| f.path == file_path }
  
  if file_ref.nil?
    # Find the group
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
  end
  
  # Ensure it's in build phase
  build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
  if build_file.nil?
    build_phase.add_file_reference(file_ref)
    puts "Added to build phase: #{file_path}"
  end
end

project.save
puts "Build phase paths fixed"

