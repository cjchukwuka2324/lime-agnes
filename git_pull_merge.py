#!/usr/bin/env python3
import subprocess
import sys
import os

os.chdir('/Users/chukwudiebube/Downloads/RockOut-main')

def run_git_command(cmd, check=True):
    """Run a git command and return the result"""
    try:
        # Use minimal clean environment to avoid shell issues
        env = os.environ.copy()
        # Remove problematic shell-related variables
        for key in list(env.keys()):
            if 'CURSOR' in key.upper() or 'SHELL' in key.upper():
                env.pop(key, None)
        # Set minimal PATH
        env['PATH'] = '/usr/bin:/bin:/usr/local/bin'
        env['SHELL'] = '/bin/bash'
        
        result = subprocess.run(
            ['/usr/bin/git'] + cmd.split(),
            capture_output=True,
            text=True,
            check=check,
            env=env,
            cwd='/Users/chukwudiebube/Downloads/RockOut-main',
            shell=False  # Explicitly don't use shell
        )
        return result.stdout, result.stderr, result.returncode
    except subprocess.CalledProcessError as e:
        return e.stdout, e.stderr, e.returncode
    except Exception as e:
        return '', str(e), 1

print("=== Step 1: Checking git status ===")
stdout, stderr, code = run_git_command('status', check=False)
print(stdout)
if stderr:
    print(stderr, file=sys.stderr)

print("\n=== Step 2: Discarding uncommitted changes ===")
run_git_command('reset --hard HEAD')
run_git_command('clean -fd', check=False)  # May fail if no untracked files

print("\n=== Step 3: Fetching from remote main ===")
stdout, stderr, code = run_git_command('fetch origin main')
print(stdout)
if stderr:
    print(stderr)

print("\n=== Step 4: Attempting merge ===")
stdout, stderr, code = run_git_command('pull origin main', check=False)
print(stdout)
if stderr:
    print(stderr, file=sys.stderr)

if code != 0:
    print("\n=== Merge conflicts detected! ===")
    print("\n=== Step 5: Identifying conflicts ===")
    stdout, stderr, _ = run_git_command('status', check=False)
    print(stdout)
    if stderr:
        print(stderr, file=sys.stderr)
    sys.exit(1)
else:
    print("\n=== Merge completed successfully ===")
    stdout, stderr, _ = run_git_command('status', check=False)
    print(stdout)
    if stderr:
        print(stderr, file=sys.stderr)
