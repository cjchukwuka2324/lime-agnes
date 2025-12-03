#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

PROJECT_PATH = 'Rockout.xcodeproj'
SOURCE_DIR = 'Rockout'
FILE_PATH = 'Views/Shared/CameraPickerView.swift'
FULL_PATH = File.join(SOURCE_DIR, FILE_PATH)

puts "════════════════════════════════════════════════════════"
puts "🔧 Fixing Xcode Project Recognition for CameraPickerView"
puts "════════════════════════════════════════════════════════"
puts ""

# Verify file exists
unless File.exist?(FULL_PATH)
  puts "❌ ERROR: File not found: #{FULL_PATH}"
  exit 1
end

puts "✅ File exists: #{FULL_PATH}"
puts ""

# Open project
project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

puts "✅ Opened project: #{PROJECT_PATH}"
puts "✅ Target: #{target.name}"
puts ""

# Navigate to Views/Shared group
main_group = project.main_group
rockout_group = main_group['Rockout']

unless rockout_group
  puts "❌ ERROR: 'Rockout' group not found"
  exit 1
end

# Navigate to Views/Shared
views_group = rockout_group['Views']
unless views_group
  views_group = rockout_group.new_group('Views')
  puts "✅ Created Views group"
end

shared_group = views_group['Shared']
unless shared_group
  shared_group = views_group.new_group('Shared')
  puts "✅ Created Shared group"
end

puts "✅ Found Views/Shared group"
puts ""

# Find existing file reference
existing_ref = project.files.find { |f| f.path == FILE_PATH || f.path&.end_with?('CameraPickerView.swift') }

if existing_ref
  puts "📋 Found existing file reference: #{existing_ref.uuid}"
  puts "   Path: #{existing_ref.path}"
  
  # Check if it's in the correct group
  if existing_ref.parent != shared_group
    puts "⚠️  File reference is in wrong group, moving..."
    existing_ref.remove_from_project
    existing_ref = nil
  else
    puts "✅ File reference is in correct group"
  end
end

# Remove from build phase if exists but wrong
if existing_ref
  build_file = build_phase.files.find { |bf| bf.file_ref == existing_ref }
  if build_file
    puts "✅ File is already in Sources build phase"
  else
    puts "⚠️  File reference exists but not in build phase, adding..."
    target.add_file_references([existing_ref])
    puts "✅ Added to Sources build phase"
  end
else
  # Create new file reference
  puts "📝 Creating new file reference..."
  file_ref = shared_group.new_file(FILE_PATH)
  file_ref.include_in_index = '1'
  puts "✅ Created file reference: #{file_ref.uuid}"
  puts "   Path: #{file_ref.path}"
  
  # Add to build phase
  target.add_file_references([file_ref])
  puts "✅ Added to Sources build phase"
end

# Save project
project.save
puts ""
puts "✅ Project saved successfully!"
puts ""

# Verify final state
final_ref = project.files.find { |f| f.path == FILE_PATH }
if final_ref
  puts "════════════════════════════════════════════════════════"
  puts "✅ VERIFICATION COMPLETE"
  puts "════════════════════════════════════════════════════════"
  puts "File Reference UUID: #{final_ref.uuid}"
  puts "Path: #{final_ref.path}"
  puts "Group: #{final_ref.parent&.name || 'Unknown'}"
  puts "includeInIndex: #{final_ref.include_in_index}"
  
  build_file = build_phase.files.find { |bf| bf.file_ref == final_ref }
  if build_file
    puts "Build Phase: ✅ In Sources"
  else
    puts "Build Phase: ❌ NOT in Sources"
  end
  puts ""
  puts "📋 NEXT STEPS:"
  puts "1. Close Xcode completely (⌘Q)"
  puts "2. Reopen Rockout.xcodeproj"
  puts "3. Wait for indexing (30-60 seconds)"
  puts "4. Build the project (⌘B)"
  puts "════════════════════════════════════════════════════════"
else
  puts "❌ ERROR: File reference not found after save"
  exit 1
end

