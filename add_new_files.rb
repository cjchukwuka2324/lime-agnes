#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

PROJECT_PATH = 'Rockout.xcodeproj'
SOURCE_DIR = 'Rockout'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
main_group = project.main_group

# Find or create Views/SoundPrint/Features group
views_group = main_group['Views']
if views_group.nil?
  views_group = main_group.new_group('Views')
end

soundprint_group = views_group['SoundPrint']
if soundprint_group.nil?
  soundprint_group = views_group.new_group('SoundPrint')
end

features_group = soundprint_group['Features']
if features_group.nil?
  features_group = soundprint_group.new_group('Features')
end

# Add all SoundPrint Features files
features_files = [
  'Views/SoundPrint/Features/ListeningStatsView.swift',
  'Views/SoundPrint/Features/TimeAnalysisView.swift',
  'Views/SoundPrint/Features/DiscoveryView.swift',
  'Views/SoundPrint/Features/SocialSharingView.swift',
  'Views/SoundPrint/Features/MoodContextView.swift',
  'Views/SoundPrint/Features/AdvancedAnalyticsView.swift'
]

features_files.each do |file_path|
  full_path = File.join(SOURCE_DIR, file_path)
  if File.exist?(full_path)
    # Check if already added
    existing = project.files.find { |f| f.path == file_path }
    if existing.nil?
      file_ref = features_group.new_file(file_path)
      target.add_file_references([file_ref])
      puts "Added #{file_path}"
    else
      puts "Already exists: #{file_path}"
    end
  else
    puts "File not found: #{full_path}"
  end
end

# Add SharedAlbumHandler
viewmodels_group = main_group['ViewModels']
if viewmodels_group.nil?
  viewmodels_group = main_group.new_group('ViewModels')
end

shared_handler_path = File.join(SOURCE_DIR, 'ViewModels/SharedAlbumHandler.swift')
if File.exist?(shared_handler_path)
  existing = project.files.find { |f| f.path == 'ViewModels/SharedAlbumHandler.swift' }
  if existing.nil?
    file_ref = viewmodels_group.new_file('ViewModels/SharedAlbumHandler.swift')
    target.add_file_references([file_ref])
    puts "Added SharedAlbumHandler.swift"
  else
    puts "Already exists: SharedAlbumHandler.swift"
  end
end

# Add AcceptSharedAlbumView
studiosessions_group = views_group['StudioSessions']
if studiosessions_group.nil?
  studiosessions_group = views_group.new_group('StudioSessions')
end

accept_view_path = File.join(SOURCE_DIR, 'Views/StudioSessions/AcceptSharedAlbumView.swift')
if File.exist?(accept_view_path)
  existing = project.files.find { |f| f.path == 'Views/StudioSessions/AcceptSharedAlbumView.swift' }
  if existing.nil?
    file_ref = studiosessions_group.new_file('Views/StudioSessions/AcceptSharedAlbumView.swift')
    target.add_file_references([file_ref])
    puts "Added AcceptSharedAlbumView.swift"
  else
    puts "Already exists: AcceptSharedAlbumView.swift"
  end
end

project.save
puts "Project updated successfully"
