#!/usr/bin/env ruby

require 'xcodeproj'

project_path = File.join(__dir__, '..', '..', 'Rockout.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Files that need path fixes
files_to_fix = {
  'BottomPlayerBar.swift' => 'Views/StudioSessions/BottomPlayerBar.swift',
  'ArtistLeaderboardViewModel.swift' => 'ViewModels/Leaderboard/ArtistLeaderboardViewModel.swift',
  'MyArtistRanksViewModel.swift' => 'ViewModels/Leaderboard/MyArtistRanksViewModel.swift',
  'Date+TimeAgo.swift' => 'Extensions/Date+TimeAgo.swift',
  'MyArtistRanksView.swift' => 'Views/Leaderboard/MyArtistRanksView.swift',
  'ArtistLeaderboardView.swift' => 'Views/Leaderboard/ArtistLeaderboardView.swift',
  'SocialMediaPlatformSelectorView.swift' => 'Views/Profile/SocialMediaPlatformSelectorView.swift',
  'BackgroundMusicMuteButton.swift' => 'Views/Feed/BackgroundMusicMuteButton.swift',
  'LeaderboardService.swift' => 'Services/Leaderboard/LeaderboardService.swift',
  'BackendFeedService.swift' => 'Services/Feed/BackendFeedService.swift'
}

files_to_fix.each do |filename, correct_path|
  # Find file reference by name
  file_ref = project.files.find { |f| 
    f.path == filename || 
    f.path&.end_with?("/#{filename}") ||
    f.path == correct_path
  }
  
  if file_ref
    if file_ref.path != correct_path
      puts "Fixing: #{file_ref.path} -> #{correct_path}"
      file_ref.path = correct_path
    else
      puts "Already correct: #{correct_path}"
    end
  else
    puts "Not found: #{filename}"
  end
end

project.save
puts '✅ Fixed file paths'

