#!/usr/bin/env ruby
# Script to fix file reference paths directly

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

puts "Fixing file reference paths..."

# Find and fix each file reference
files_to_fix.each do |filename, correct_path|
  # Find all file references with this filename
  file_refs = project.files.select do |file_ref|
    file_ref.path && File.basename(file_ref.path) == filename
  end
  
  file_refs.each do |file_ref|
    current_path = file_ref.path || ''
    
    # Check if path is incorrect
    if current_path != correct_path
      puts "  Fixing #{filename}:"
      puts "    Old: #{current_path}"
      puts "    New: #{correct_path}"
      
      # Set correct path and sourceTree
      file_ref.path = correct_path
      file_ref.source_tree = '<group>'
    else
      puts "  ✓ #{filename} already has correct path: #{correct_path}"
    end
  end
end

# Save the project
project.save
puts "\n✅ File references fixed!"

