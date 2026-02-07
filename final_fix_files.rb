#!/usr/bin/env ruby
# Final script to properly fix all file references

require 'xcodeproj'

project_path = 'Rockout.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Rockout' }
unless target
  puts "❌ Could not find 'Rockout' target"
  exit(1)
end

# Files to fix
files_to_fix = {
  'Logger.swift' => 'Rockout/Utils/Logger.swift',
  'Analytics.swift' => 'Rockout/Utils/Analytics.swift',
  'PerformanceMetrics.swift' => 'Rockout/Utils/PerformanceMetrics.swift',
  'RequestCoalescer.swift' => 'Rockout/Services/Networking/RequestCoalescer.swift',
  'RetryPolicy.swift' => 'Rockout/Services/Networking/RetryPolicy.swift'
}

puts "Removing ALL references to these files..."

# Remove ALL file references and build files for these files
files_to_fix.each do |filename, _|
  # Find all file references
  refs = project.files.select { |f| f.path && File.basename(f.path) == filename }
  refs.each do |ref|
    puts "  Removing file ref: #{ref.path}"
    
    # Remove from all build phases
    target.source_build_phase.files.each do |bf|
      if bf.file_ref == ref
        target.source_build_phase.remove_file_reference(ref)
      end
    end
    
    ref.remove_from_project
  end
end

puts "\nAdding files correctly..."

# Find main group
main_group = project.main_group
rockout_group = main_group['Rockout'] || main_group

files_to_fix.each do |filename, correct_path|
  # Find or create groups
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
  
  # Verify file exists
  unless File.exist?(correct_path)
    puts "  ⚠️  File not found: #{correct_path}"
    next
  end
  
  # Create file reference with explicit sourceTree
  file_ref = group.new_file(correct_path)
  file_ref.source_tree = '<group>'
  
  # Add to compile sources
  file_build_phase = target.source_build_phase
  build_file = file_build_phase.add_file_reference(file_ref)
  build_file.settings = { 'COMPILER_FLAGS' => '' }
  
  puts "  ✓ Added #{filename}"
end

project.save
puts "\n✅ Done!"

