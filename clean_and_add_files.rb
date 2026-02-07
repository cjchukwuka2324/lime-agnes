#!/usr/bin/env ruby
# Script to clean up and properly add files to Xcode project

require 'xcodeproj'

project_path = 'Rockout.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Rockout' }
unless target
  puts "❌ Could not find 'Rockout' target"
  exit(1)
end

# Files to fix with their correct paths
files_to_fix = {
  'Logger.swift' => 'Rockout/Utils/Logger.swift',
  'Analytics.swift' => 'Rockout/Utils/Analytics.swift',
  'PerformanceMetrics.swift' => 'Rockout/Utils/PerformanceMetrics.swift',
  'RequestCoalescer.swift' => 'Rockout/Services/Networking/RequestCoalescer.swift',
  'RetryPolicy.swift' => 'Rockout/Services/Networking/RetryPolicy.swift'
}

puts "Cleaning up file references..."

# Remove ALL file references for these files (both correct and incorrect)
files_to_fix.each do |filename, correct_path|
  # Find all file references with this filename
  refs_to_remove = project.files.select do |file_ref|
    file_ref.path && File.basename(file_ref.path) == filename
  end
  
  refs_to_remove.each do |file_ref|
    puts "  Removing: #{file_ref.path}"
    
    # Remove from compile sources
    target.source_build_phase.files.each do |build_file|
      if build_file.file_ref == file_ref
        target.source_build_phase.remove_file_reference(file_ref)
      end
    end
    
    # Remove from project
    file_ref.remove_from_project
  end
end

puts "\nAdding files with correct paths..."

# Find main group
main_group = project.main_group
rockout_group = main_group['Rockout'] || main_group

# Add files with correct paths
files_to_fix.each do |filename, correct_path|
  # Find or create the appropriate group
  if correct_path.include?('Utils/')
    utils_group = rockout_group['Utils'] || rockout_group.new_group('Utils', 'Rockout/Utils')
    group = utils_group
  elsif correct_path.include?('Services/Networking/')
    services_group = rockout_group['Services'] || rockout_group.new_group('Services', 'Rockout/Services')
    networking_group = services_group['Networking'] || services_group.new_group('Networking', 'Rockout/Services/Networking')
    group = networking_group
  else
    group = rockout_group
  end
  
  # Verify file exists on disk
  unless File.exist?(correct_path)
    puts "  ⚠️  File not found: #{correct_path}"
    next
  end
  
  # Add file reference with correct path (relative to project)
  file_ref = group.new_reference(correct_path)
  
  # Add to compile sources
  target.add_file_references([file_ref])
  
  puts "  ✓ Added #{filename} -> #{correct_path}"
end

# Save the project
project.save
puts "\n✅ Project saved successfully!"

