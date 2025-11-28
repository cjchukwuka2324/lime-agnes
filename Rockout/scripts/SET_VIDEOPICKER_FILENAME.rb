#!/usr/bin/env ruby
# encoding: utf-8

require 'xcodeproj'

SCRIPT_DIR = File.expand_path(File.dirname(__FILE__))
PROJECT_DIR = File.expand_path(File.join(SCRIPT_DIR, '..', '..'))
PROJECT_PATH = File.join(PROJECT_DIR, 'Rockout.xcodeproj')
project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.first
build_phase = target.source_build_phase

vp = project.files.find { |f| f.display_name == "VideoPicker.swift" }
if vp.nil?
  puts "VideoPicker not found!"
  exit 1
end

puts "Current path: #{vp.path}"

build_phase.remove_file_reference(vp)
vp.path = "VideoPicker.swift"
vp.name = "VideoPicker.swift"
target.add_file_references([vp])

project.save
puts "Set VideoPicker path to: VideoPicker.swift"

