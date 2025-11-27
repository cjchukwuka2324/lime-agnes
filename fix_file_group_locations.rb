#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

PROJECT_PATH = 'Rockout.xcodeproj'

project = Xcodeproj::Project.open(PROJECT_PATH)
main_group = project.main_group
rockout_group = main_group['Rockout']

unless rockout_group
  puts "ERROR: Rockout group not found!"
  exit 1
end

# Files that need to be under Rockout group
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
  # Find file reference (might be at root or in Rockout group)
  file_ref = project.files.find { |f| 
    f.path == file_path || 
    f.path == File.basename(file_path) ||
    (f.path && File.basename(f.path) == File.basename(file_path))
  }
  
  if file_ref
    # Check if it's already in the right group
    parent = file_ref.parent
    if parent != rockout_group
      # Remove from current parent
      parent.remove_reference(file_ref) if parent.respond_to?(:remove_reference)
      
      # Add to Rockout group (navigate to correct subgroup)
      parts = file_path.split('/')
      current_group = rockout_group
      
      parts[0..-2].each do |part|
        next_group = current_group[part]
        if next_group.nil?
          next_group = current_group.new_group(part)
        end
        current_group = next_group
      end
      
      current_group.children << file_ref unless current_group.children.include?(file_ref)
      puts "Moved #{File.basename(file_path)} to #{current_group.display_name}"
    else
      puts "Already in correct group: #{File.basename(file_path)}"
    end
  else
    puts "File ref not found: #{file_path}"
  end
end

project.save
puts "Fixed file group locations"

