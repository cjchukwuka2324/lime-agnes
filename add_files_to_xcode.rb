#!/usr/bin/env ruby
# Script to add missing Swift files to Xcode project using xcodeproj gem

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not found. Installing..."
  system('gem install xcodeproj') || (puts "❌ Failed to install xcodeproj gem. Please run: gem install xcodeproj" && exit(1))
  require 'xcodeproj'
end

project_path = 'Rockout.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main group (Rockout)
main_group = project.main_group
rockout_group = main_group['Rockout'] || main_group

# Files to add
files_to_add = [
  'Rockout/Utils/Logger.swift',
  'Rockout/Utils/Analytics.swift',
  'Rockout/Utils/PerformanceMetrics.swift',
  'Rockout/Services/Networking/RequestCoalescer.swift',
  'Rockout/Services/Networking/RetryPolicy.swift'
]

# Find or create Utils group
utils_group = rockout_group['Utils'] || rockout_group.new_group('Utils', 'Rockout/Utils')

# Find or create Services/Networking group
services_group = rockout_group['Services'] || rockout_group.new_group('Services', 'Rockout/Services')
networking_group = services_group['Networking'] || services_group.new_group('Networking', 'Rockout/Services/Networking')

# Get the main target
target = project.targets.find { |t| t.name == 'Rockout' }
unless target
  puts "❌ Could not find 'Rockout' target"
  exit(1)
end

# Add files
files_to_add.each do |file_path|
  filename = File.basename(file_path)
  
  # Check if file already exists in project
  existing_file = project.files.find { |f| f.path == filename || f.path == file_path }
  if existing_file
    puts "✓ #{filename} already in project"
    next
  end
  
  # Determine which group to add to
  if file_path.include?('Utils/')
    group = utils_group
  elsif file_path.include?('Services/Networking/')
    group = networking_group
  else
    group = rockout_group
  end
  
  # Add file reference
  file_ref = group.new_reference(file_path)
  
  # Add to target's compile sources
  target.add_file_references([file_ref])
  
  puts "✓ Added #{filename} to project"
end

# Save the project
project.save
puts "\n✅ Project saved successfully!"

