#!/usr/bin/env ruby
# Remove deleted file references from Xcode project

require 'xcodeproj'

project_path = 'Rockout.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Rockout' }
unless target
  puts "❌ Could not find 'Rockout' target"
  exit(1)
end

# Files to remove
files_to_remove = [
  'SpeechTranscriber.swift',
  'RecallWakeWordSettings.swift',
  'RecallTranscriptComposer.swift',
  'RecallLiveTranscriptView.swift'
]

puts "Removing references to deleted files..."

# Remove from build phases
target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  file_path = file_ref.path || file_ref.display_name || ''
  if files_to_remove.any? { |f| file_path.include?(f) }
    puts "  Removing from build phase: #{file_path}"
    target.source_build_phase.remove_file_reference(file_ref)
  end
end

# Remove file references
project.files.each do |file|
  file_path = file.path || file.display_name || ''
  if files_to_remove.any? { |f| file_path.include?(f) }
    puts "  Removing file reference: #{file_path}"
    file.remove_from_project
  end
end

# Remove from groups
def remove_from_group(group, files_to_remove)
  group.children.each do |child|
    if child.is_a?(Xcodeproj::Project::Object::PBXGroup)
      remove_from_group(child, files_to_remove)
    elsif child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
      file_path = child.path || child.display_name || ''
      if files_to_remove.any? { |f| file_path.include?(f) }
        puts "  Removing from group: #{file_path}"
        child.remove_from_project
      end
    end
  end
end

remove_from_group(project.main_group, files_to_remove)

project.save
puts "✅ Removed all references to deleted files"






