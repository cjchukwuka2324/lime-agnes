#!/usr/bin/env ruby
# encoding: utf-8

# Fix path doubling issue - file references should have paths relative to Rockout, not including group names

begin
  require 'xcodeproj'
rescue LoadError
  puts "⚠️  xcodeproj gem not installed."
  exit 1
end

SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')
SOURCE_DIR = File.join(PROJECT_DIR, 'Rockout')

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

puts "🔧 Fixing path doubling issue..."

# Get all actual files
actual_files = {}
Dir.glob(File.join(SOURCE_DIR, '**', '*.swift')).each do |file|
  rel_path = file.sub("#{SOURCE_DIR}/", '')
  actual_files[rel_path] = file
end

# Fix all file references
fixed = 0
project.files.each do |file_ref|
  next unless file_ref.path && file_ref.path.end_with?('.swift')
  
  current_path = file_ref.path
  
  # Check if path has doubling (e.g., "ViewModels/ViewModels/...")
  if current_path.include?('/ViewModels/ViewModels/') || 
     current_path.include?('/Models/Models/') ||
     current_path.include?('/Views/Views/') ||
     current_path.include?('/Services/Services/') ||
     current_path.include?('/Extensions/Extensions/') ||
     current_path.include?('/App/App/') ||
     current_path.include?('/Utils/Utils/')
    
    # Find the correct path by checking actual files
    basename = File.basename(current_path)
    correct_path = actual_files.keys.find { |p| File.basename(p) == basename }
    
    if correct_path && correct_path != current_path
      file_ref.path = correct_path
      fixed += 1
      puts "  ✓ Fixed: #{current_path} → #{correct_path}"
    end
  end
end

project.save
puts "\n✅ Fixed #{fixed} file reference path(s)"
puts "💡 Try building now!"

