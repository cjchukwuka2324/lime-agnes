#!/usr/bin/env ruby
# Script to properly fix file references in Xcode project

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

# Find main group
main_group = project.main_group
rockout_group = main_group['Rockout'] || main_group

# Remove all incorrect file references
files_to_remove = []
project.files.each do |file_ref|
  filename = File.basename(file_ref.path || '')
  if files_to_fix.key?(filename)
    path = file_ref.path || ''
    # Check if path is incorrect (duplicated)
    if path.include?('Rockout/Rockout') || path.include?('Utils/Utils') || path.include?('Services/Services')
      puts "Removing incorrect reference: #{path}"
      files_to_remove << file_ref
    end
  end
end

# Remove from build phases and groups
files_to_remove.each do |file_ref|
  # Remove from compile sources
  target.source_build_phase.files.each do |build_file|
    if build_file.file_ref == file_ref
      puts "  Removing from compile sources: #{file_ref.path}"
      target.source_build_phase.remove_file_reference(file_ref)
    end
  end
  
  # Remove from group
  file_ref.remove_from_project
end

# Now add files with correct paths
files_to_fix.each do |filename, correct_path|
  # Check if correct reference already exists
  existing = project.files.find { |f| f.path == correct_path }
  if existing
    puts "✓ #{filename} already has correct path: #{correct_path}"
    # Ensure it's in compile sources
    in_sources = target.source_build_phase.files.any? { |bf| bf.file_ref == existing }
    unless in_sources
      target.add_file_references([existing])
      puts "  Added to compile sources"
    end
    next
  end
  
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
  
  # Add file reference
  file_ref = group.new_reference(correct_path)
  target.add_file_references([file_ref])
  puts "✓ Added #{filename} with correct path: #{correct_path}"
end

# Save the project
project.save
puts "\n✅ Project saved successfully!"

