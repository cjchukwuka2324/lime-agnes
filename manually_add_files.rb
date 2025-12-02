#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

PROJECT_PATH = 'Rockout.xcodeproj'
SOURCE_DIR = 'Rockout'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
rockout_group = project.main_group['Rockout']

files_to_add = [
  'Views/Shared/CameraPickerView.swift',
  'Views/Shared/HashtagTextView.swift'
]

files_to_add.each do |file_path|
  full_path = File.join(SOURCE_DIR, file_path)
  next unless File.exist?(full_path)
  
  # Navigate to correct group
  parts = file_path.split('/')
  current_group = rockout_group
  
  parts[0..-2].each do |part|
    next_group = current_group[part]
    if next_group.nil?
      next_group = current_group.new_group(part)
    end
    current_group = next_group
  end
  
  # Check if file ref exists
  basename = File.basename(file_path)
  existing = current_group.files.find { |f| File.basename(f.path || '') == basename }
  
  if existing
    file_ref = existing
    puts "Found existing: #{file_path}"
  else
    file_ref = current_group.new_file(file_path)
    puts "Created: #{file_path}"
  end
  
  # Ensure in build phase
  build_phase = target.source_build_phase
  build_file = build_phase.files.find { |bf| bf.file_ref == file_ref }
  if build_file.nil? && file_path.end_with?('.swift')
    target.add_file_references([file_ref])
    puts "  Added to build phase"
  end
end

project.save
puts "\n✅ All files added successfully!"

