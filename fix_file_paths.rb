#!/usr/bin/env ruby
require 'xcodeproj'

project = Xcodeproj::Project.open('Rockout.xcodeproj')

# Files that need path fixes - these are in groups with paths, so should just be filename
files_to_fix = {
  'CCA649B64E36993E03A01A18' => 'CameraPickerView.swift',  # In Shared group with path
  'A6C9D80A7860D1EA28902FF6' => 'HashtagTextView.swift',    # In Shared group with path
}

files_to_fix.each do |uuid, correct_path|
  file_ref = project.files.find { |f| f.uuid == uuid }
  if file_ref
    old_path = file_ref.path
    file_ref.path = correct_path
    puts "Fixed: #{old_path} → #{correct_path}"
  end
end

project.save
puts "✅ Path fixes applied"
