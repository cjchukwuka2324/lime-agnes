#!/usr/bin/env ruby
# Script to fix file paths in Xcode project

require 'xcodeproj'

project_path = 'Rockout.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Files to fix
files_to_fix = {
  'Logger.swift' => 'Rockout/Utils/Logger.swift',
  'Analytics.swift' => 'Rockout/Utils/Analytics.swift',
  'PerformanceMetrics.swift' => 'Rockout/Utils/PerformanceMetrics.swift',
  'RequestCoalescer.swift' => 'Rockout/Services/Networking/RequestCoalescer.swift',
  'RetryPolicy.swift' => 'Rockout/Services/Networking/RetryPolicy.swift'
}

# Find and fix file references
project.files.each do |file_ref|
  filename = File.basename(file_ref.path || '')
  if files_to_fix.key?(filename)
    correct_path = files_to_fix[filename]
    if file_ref.path != correct_path
      puts "Fixing #{filename}: #{file_ref.path} -> #{correct_path}"
    file_ref.path = correct_path
    else
      puts "✓ #{filename} already has correct path"
    end
  end
end

# Save the project
project.save
puts "\n✅ Project saved successfully!"
