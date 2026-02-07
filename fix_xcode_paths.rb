#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('Rockout.xcodeproj')
target = project.targets.first
build_phase = target.source_build_phase

puts "Verifying all file references point to existing files..."

missing = []
fixed = 0

build_phase.files.each do |bf|
  file_ref = bf.file_ref
  next unless file_ref
  
  path = file_ref.path
  next unless path
  
  full_path = File.join('Rockout', path)
  
  unless File.exist?(full_path)
    basename = File.basename(path)
    found = Dir.glob("Rockout/**/#{basename}").first
    
    if found
      correct_path = found.sub('Rockout/', '')
      file_ref.path = correct_path
      puts "Fixed: #{path} -> #{correct_path}"
      fixed += 1
    else
      missing << path
      puts "Missing: #{path}"
    end
  end
end

if missing.any?
  puts "\n⚠️  #{missing.count} files not found. Removing from build phase..."
  missing.each do |path|
    bf = build_phase.files.find { |f| f.file_ref&.path == path }
    if bf
      bf.remove_from_project
      puts "  Removed: #{path}"
    end
  end
end

project.save
puts "\n✅ Fixed #{fixed} paths, removed #{missing.count} missing files"
