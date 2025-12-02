#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

project = Xcodeproj::Project.open('Rockout.xcodeproj')
target = project.targets.first
build_phase = target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

# Files that need fixing
files_to_fix = [
  'ArtistLeaderboardViewModel.swift',
  'MyArtistRanksViewModel.swift',
  'Date+TimeAgo.swift',
  'MyArtistRanksView.swift',
  'ArtistLeaderboardView.swift',
  'BottomPlayerBar.swift',
  'SocialMediaPlatformSelectorView.swift',
  'ThreadReplyView.swift',
  'BackgroundMusicMuteButton.swift',
  'LeaderboardService.swift',
  'BackendFeedService.swift'
]

puts 'Finding and fixing file references...'

# Step 1: Remove ALL build phase entries for these files
files_to_fix.each do |filename|
  build_files = build_phase.files.select { |bf| 
    ref_path = bf.file_ref&.path || bf.file_ref&.display_name || ''
    ref_path.include?(filename)
  }
  
  build_files.each do |bf|
    path = bf.file_ref&.path || bf.file_ref&.display_name || 'unknown'
    puts "  Removing: #{path}"
    build_phase.remove_file_reference(bf.file_ref)
  end
end

# Step 2: Find correct file references and fix their paths
files_to_fix.each do |filename|
  # Find file reference by searching all files
  file_ref = project.files.find { |f| 
    f_path = f.path || f.display_name || ''
    f_path.end_with?("/#{filename}") || f_path == filename
  }
  
  if file_ref
    # Set path to just filename
    file_ref.path = filename
    puts "  Fixed path for #{filename} -> #{filename}"
    
    # Add to build phase
    build_phase.add_file_reference(file_ref)
    puts "  Added #{filename} to build phase"
  else
    puts "  WARNING: Could not find file reference for #{filename}"
  end
end

project.save
puts 'Done! Fixed all file reference paths.'

