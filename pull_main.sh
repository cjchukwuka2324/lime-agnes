#!/bin/sh
set -e
cd /Users/chukwudiebube/Downloads/RockOut-main

echo "=========================================="
echo "Step 1: Checking current git status"
echo "=========================================="
git status
echo ""

echo "=========================================="
echo "Step 2: Discarding uncommitted changes"
echo "=========================================="
git reset --hard HEAD
echo "Uncommitted changes in tracked files discarded."
git clean -fd || echo "No untracked files to clean."
echo ""

echo "=========================================="
echo "Step 3: Fetching latest changes from remote main"
echo "=========================================="
git fetch origin main
echo ""

echo "=========================================="
echo "Step 4: Attempting to merge remote main"
echo "=========================================="
if git pull origin main; then
    echo ""
    echo "=========================================="
    echo "Merge completed successfully!"
    echo "=========================================="
    git status
    git log --oneline -5
else
    echo ""
    echo "=========================================="
    echo "Merge conflicts detected!"
    echo "=========================================="
    echo ""
    echo "Step 5: Files with conflicts:"
    git status
    echo ""
    echo "Please resolve conflicts manually in the files listed above."
    echo "After resolving conflicts:"
    echo "  1. Edit each conflicted file and remove conflict markers"
    echo "  2. Run: git add <resolved-file> (for each file)"
    echo "  3. Run: git commit (to complete the merge)"
    exit 1
fi

