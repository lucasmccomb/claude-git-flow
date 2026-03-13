---
description: Fetch origin and rebase current branch on main
allowed-tools: Bash(git:*)
---

# Sync with Main

## Current State

- Current branch: !`git branch --show-current`
- Working directory: !`git status --short`
- Commits ahead: !`git rev-list --count origin/main..HEAD 2>/dev/null || echo "unknown"`
- Commits behind: !`git rev-list --count HEAD..origin/main 2>/dev/null || echo "unknown"`

## Your Task

1. **Check for uncommitted changes**
   - If dirty, ask user what to do:
     - Stash changes temporarily
     - Commit changes first
     - Abort sync

2. **Fetch latest from origin**
   ```bash
   git fetch origin
   ```

3. **Rebase on main**
   ```bash
   git rebase origin/main
   ```

4. **Handle conflicts if any**
   - If conflicts occur, list the conflicting files
   - Help user understand what needs to be resolved
   - After resolution: `git rebase --continue`

5. **Report result**
   - Show how many commits ahead/behind after sync
   - If stashed, remind user to `git stash pop`

## Notes

- This rebases your current branch on the latest main
- Your commits will be replayed on top of main
- Force push will be needed if branch was already pushed: `git push --force-with-lease`
