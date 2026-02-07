#!/usr/bin/env python3
"""
Script to add missing Swift files to Xcode project
"""
import re
import uuid
import os

def generate_uuid():
    """Generate a 24-character hex string for Xcode project IDs"""
    return ''.join([format(ord(c), '02X') for c in os.urandom(12)])

def add_file_to_project(project_path, file_path, group_path):
    """Add a Swift file to the Xcode project"""
    with open(project_path, 'r') as f:
        content = f.read()
    
    # Files to add
    files_to_add = [
        'Rockout/Utils/Logger.swift',
        'Rockout/Utils/Analytics.swift',
        'Rockout/Utils/PerformanceMetrics.swift',
        'Rockout/Services/Networking/RequestCoalescer.swift',
        'Rockout/Services/Networking/RetryPolicy.swift'
    ]
    
    # Check which files are already in the project
    existing_files = set()
    for match in re.finditer(r'(\w+) \/\* ([^*]+\.swift) \*\/ = \{', content):
        existing_files.add(match.group(2))
    
    print("Files already in project:")
    for f in sorted(existing_files):
        if any(x in f for x in ['Logger', 'RequestCoalescer', 'PerformanceMetrics', 'Analytics', 'RetryPolicy']):
            print(f"  ✓ {f}")
    
    print("\nFiles to add:")
    files_to_add_filtered = []
    for f in files_to_add:
        filename = os.path.basename(f)
        if filename not in existing_files:
            print(f"  + {f}")
            files_to_add_filtered.append(f)
        else:
            print(f"  ✓ {f} (already exists)")
    
    if not files_to_add_filtered:
        print("\nAll files are already in the project!")
        return
    
    print(f"\n⚠️  Note: This script can detect missing files but cannot safely modify .pbxproj")
    print("Please add these files manually in Xcode:")
    for f in files_to_add_filtered:
        print(f"  - {f}")

if __name__ == '__main__':
    project_path = 'Rockout.xcodeproj/project.pbxproj'
    if os.path.exists(project_path):
        add_file_to_project(project_path, None, None)
    else:
        print(f"Project file not found: {project_path}")

