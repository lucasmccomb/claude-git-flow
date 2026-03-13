---
description: Stage all changes and commit with conventional format
allowed-tools: Bash(git:*), Bash(npm:*)
argument-hint: [issue_number]: [description]
---

# Git Commit

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Staged diff: !`git diff --cached --stat`
- Unstaged diff: !`git diff --stat`

## Your Task

1. **Verify changes are ready**
   - Review the status and diffs above
   - If there are no changes, inform the user and stop

2. **Run verification (if package.json exists)**
   ```bash
   # Try common verification commands, skip if they don't exist
   npm run lint 2>/dev/null || true
   npm run build 2>/dev/null || true
   ```
   - If lint or build fails, STOP and report the errors
   - Do NOT commit broken code

3. **Stage and commit**
   ```bash
   git add -A
   git commit -m "$ARGUMENTS"
   ```

4. **Report result**
   - Show the commit hash and message
   - Remind user to push when ready

## Commit Message Format

Expected: `{issue_number}: {brief description}`
- Example: `4: Add user authentication`
- Example: `12: Fix calendar alignment bug`

The message provided is: `$ARGUMENTS`

If no message provided, analyze the changes and suggest one following the format.
