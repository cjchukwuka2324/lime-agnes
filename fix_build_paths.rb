#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('Rockout.xcodeproj')
target = project.targets.first
build_phase = target.source_build_phase

# The issue might be that Xcode is constructing paths from group hierarchy
# Let's ensure all file references have absolute paths relative to project root
puts "Fixing file reference paths to be project-relative..."

fixed = 0
build_phase.files.each do |bf|
  file_ref = bf.file_ref
  next unless file_ref
  
  path = file_ref.path
  next unless path
  
  # Check if this path would cause the duplicate issue
  # The error shows paths like: Rockout/Services/Notifications/Services/Notifications/...
  # This suggests the group hierarchy is being prepended incorrectly
  
  # Get the actual file location
  basename = File.basename(path)
  found = Dir.glob("Rockout/**/#{basename}").first
  
  if found
    correct_path = found.sub('Rockout/', '')
    
    # Only update if different and doesn't have duplicates
    if path != correct_path && !correct_path.include?('/Services/Services/') && !correct_path.include?('/Views/Views/')
      file_ref.path = correct_path
      puts "Fixed: #{path} -> #{correct_path}"
      fixed += 1
    end
  end
end

project.save
puts "\n✅ Fixed #{fixed} file paths"
