#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

PROJECT_PATH = 'Rockout.xcodeproj'
SOURCE_DIR = 'Rockout'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first

# Files that need path fixes
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

files_to_fix.each do |file_path|
  full_path = File.join(SOURCE_DIR, file_path)
  
  # Find the file reference
  file_ref = project.files.find { |f| f.path == file_path || f.path&.end_with?(File.basename(file_path)) }
  
  if file_ref
    # Update the path
    file_ref.path = file_path
    puts "Fixed path for: #{file_path}"
    
    # Ensure it's in the build phase
    build_file = target.source_build_phase.files.find { |bf| bf.file_ref == file_ref }
    if build_file.nil?
      target.add_file_references([file_ref])
      puts "  Added to build phase"
    end
  else
    puts "Could not find: #{file_path}"
  end
end

project.save
puts "File paths fixed"

