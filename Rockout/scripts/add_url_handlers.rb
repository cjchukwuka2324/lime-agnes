require 'xcodeproj'

project_path = 'Rockout.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Rockout' }
main_group = project.main_group['Rockout'] || project.main_group
app_group = main_group['App'] || main_group.new_group('App')

# Add AppDelegate.swift
app_delegate_path = 'Rockout/App/AppDelegate.swift'
existing_ref = app_group.find_subpath('AppDelegate.swift', true)
unless existing_ref
  file_ref = app_group.new_file(app_delegate_path)
  target.add_file_references([file_ref])
  puts "Added AppDelegate.swift"
else
  puts "AppDelegate.swift already exists"
end

# Add SceneDelegate.swift (optional, for iOS 13+)
scene_delegate_path = 'Rockout/App/SceneDelegate.swift'
existing_ref = app_group.find_subpath('SceneDelegate.swift', true)
unless existing_ref
  file_ref = app_group.new_file(scene_delegate_path)
  target.add_file_references([file_ref])
  puts "Added SceneDelegate.swift"
else
  puts "SceneDelegate.swift already exists"
end

project.save
puts "Project saved successfully"

