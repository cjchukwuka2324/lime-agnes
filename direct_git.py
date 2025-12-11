#!/usr/bin/env python3
"""
Direct git execution script that bypasses shell entirely
"""
import subprocess
import sys
import os

def main():
    os.chdir('/Users/chukwudiebube/Downloads/RockOut-main')
    
    # Create minimal environment
    env = {
        'PATH': '/usr/bin:/bin:/usr/local/bin',
        'HOME': os.environ.get('HOME', '/Users/chukwudiebube'),
        'USER': os.environ.get('USER', 'chukwudiebube'),
    }
    
    # Copy essential git-related env vars
    for key in ['GIT_EDITOR', 'GIT_PAGER', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM']:
        if key in os.environ:
            env[key] = os.environ[key]
    
    commands = [
        ('status', False),
        ('reset', ['--hard', 'HEAD']),
        ('clean', ['-fd']),
        ('fetch', ['origin', 'main']),
        ('pull', ['origin', 'main']),
    ]
    
    print("=== Step 1: Checking git status ===")
    result = subprocess.run(['/usr/bin/git', 'status'], 
                          env=env, cwd='/Users/chukwudiebube/Downloads/RockOut-main',
                          capture_output=True, text=True)
    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    
    print("\n=== Step 2: Discarding uncommitted changes ===")
    subprocess.run(['/usr/bin/git', 'reset', '--hard', 'HEAD'],
                  env=env, cwd='/Users/chukwudiebube/Downloads/RockOut-main')
    subprocess.run(['/usr/bin/git', 'clean', '-fd'],
                  env=env, cwd='/Users/chukwudiebube/Downloads/RockOut-main',
                  capture_output=True)
    
    print("\n=== Step 3: Fetching from remote main ===")
    result = subprocess.run(['/usr/bin/git', 'fetch', 'origin', 'main'],
                          env=env, cwd='/Users/chukwudiebube/Downloads/RockOut-main',
                          capture_output=True, text=True)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr)
    
    print("\n=== Step 4: Attempting merge ===")
    result = subprocess.run(['/usr/bin/git', 'pull', 'origin', 'main'],
                          env=env, cwd='/Users/chukwudiebube/Downloads/RockOut-main',
                          capture_output=True, text=True)
    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    
    if result.returncode != 0:
        print("\n=== Merge conflicts detected! ===")
        print("\n=== Step 5: Identifying conflicts ===")
        status_result = subprocess.run(['/usr/bin/git', 'status'],
                                      env=env, cwd='/Users/chukwudiebube/Downloads/RockOut-main',
                                      capture_output=True, text=True)
        print(status_result.stdout)
        if status_result.stderr:
            print(status_result.stderr, file=sys.stderr)
        sys.exit(1)
    else:
        print("\n=== Merge completed successfully ===")
        status_result = subprocess.run(['/usr/bin/git', 'status'],
                                      env=env, cwd='/Users/chukwudiebube/Downloads/RockOut-main',
                                      capture_output=True, text=True)
        print(status_result.stdout)
        if status_result.stderr:
            print(status_result.stderr, file=sys.stderr)

if __name__ == '__main__':
    main()
