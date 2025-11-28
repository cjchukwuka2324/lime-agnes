#!/usr/bin/env ruby
# encoding: utf-8

# Verify all build phase file paths are correct

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

puts "🔍 Verifying #{build_phase.files.length} build file(s)...\n\n"

incorrect = []
correct = []

build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  file_path = file_ref.path || ''
  full_path = File.join(SOURCE_DIR, file_path)
  
  if File.exist?(full_path)
    correct << file_path
  else
    incorrect << file_path
    puts "  ❌ Not found: #{file_path}"
    puts "     Expected at: #{full_path}"
  end
end

puts "\n✅ Correct: #{correct.length}"
puts "❌ Incorrect: #{incorrect.length}"

if incorrect.length > 0
  puts "\n💡 Run: ruby Rockout/scripts/fix_all_build_paths.rb"
end

