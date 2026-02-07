#!/usr/bin/env ruby
# Fix file reference paths to be relative to their parent groups

require 'xcodeproj'

project = Xcodeproj::Project.open('Rockout.xcodeproj')

# Files to fix - use just the filename, not full path
files_to_fix = {
  'Logger.swift' => 'Logger.swift',
  'Analytics.swift' => 'Analytics.swift',
  'PerformanceMetrics.swift' => 'PerformanceMetrics.swift',
  'RequestCoalescer.swift' => 'RequestCoalescer.swift',
  'RetryPolicy.swift' => 'RetryPolicy.swift'
}

puts "Fixing file reference paths to be relative..."

files_to_fix.each do |filename, relative_path|
  file_refs = project.files.select { |f| f.path && File.basename(f.path) == filename }
  
  file_refs.each do |file_ref|
    current_path = file_ref.path || ''
    
    # Change to relative path (just filename)
    if current_path != relative_path
      puts "  #{filename}: #{current_path} -> #{relative_path}"
      file_ref.path = relative_path
      file_ref.source_tree = '<group>'
    else
      puts "  ✓ #{filename} already relative"
    end
  end
end

project.save
puts "\n✅ Paths fixed!"

