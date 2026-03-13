---
description: Show git status and project info (branch, PRs, issues)
allowed-tools: Bash(git:*), Bash(gh:*)
---

# Git Status & Project Info

## Branch Status

- **Current branch**: !`git branch --show-current`
- **Remote tracking**: !`git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "no upstream"`

## Working Directory

!`git status --short 2>/dev/null || echo "Not a git repository"`

## Sync Status

- Commits ahead of origin: !`git rev-list --count @{u}..HEAD 2>/dev/null || echo "unknown"`
- Commits behind origin: !`git rev-list --count HEAD..@{u} 2>/dev/null || echo "unknown"`

## Recent Commits (last 5)

!`git log --oneline -5 2>/dev/null || echo "No commits"`

## Open PRs (this repo)

!`gh pr list --limit 10 2>/dev/null || echo "Could not fetch PRs (not a GitHub repo or gh not authenticated)"`

## Your Task

Summarize the git and project status concisely:
1. Report the current branch and whether the working directory is clean or dirty
2. Note if the branch is ahead/behind the remote
3. List any open PRs with their numbers and titles
4. If there are uncommitted changes, briefly describe what files are modified/staged/untracked
5. Recommend next action if applicable (push, pull, rebase, etc.)

Keep the summary brief and actionable.
