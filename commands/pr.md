---
description: Push branch and create PR that closes an issue
allowed-tools: Bash(git:*), Bash(gh:*), Bash(npm:*)
argument-hint: #[issue_number]: [description]
---

# Create Pull Request

## Context

- Current branch: !`git branch --show-current`
- Commits ahead of main: !`git log --oneline origin/main..HEAD 2>/dev/null || git log --oneline main..HEAD 2>/dev/null || echo "Unable to compare"`
- Git status: !`git status --short`
- Remote tracking: !`git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "No upstream set"`

## Your Task

1. **Pre-flight checks**
   - Ensure working directory is clean (no uncommitted changes)
   - If there are uncommitted changes, ask user to commit first or run /commit

2. **Run verification (if package.json exists)**
   ```bash
   npm run lint 2>/dev/null || true
   npm run build 2>/dev/null || true
   ```
   - If checks fail, STOP and report errors

3. **Rebase on latest main**
   ```bash
   git fetch origin
   git rebase origin/main
   ```
   - If conflicts occur, help resolve them

4. **Push to origin**
   ```bash
   git push -u origin HEAD
   ```

5. **Check for PR template**
   - Look for a PR template in this order:
     1. `pull_request_template.md` or `PULL_REQUEST_TEMPLATE.md` in repo root
     2. `.github/PULL_REQUEST_TEMPLATE.md` or `.github/pull_request_template.md`
   - If found, use the template to structure the PR body (fill in sections, include `Closes #<issue_number>`)
   - If not found, use a simple body: `Closes #<issue_number>`

6. **Create PR**
   - Extract issue number from `$ARGUMENTS` (number after the `#`)
   - Create PR with:
     ```bash
     gh pr create --title "$ARGUMENTS" --body "<body from template or default>"
     ```

7. **Update issue labels**
   ```bash
   gh issue edit <issue_number> --remove-label "in-progress" --add-label "in-review"
   ```

8. **Report result**
   - Show PR URL
   - Confirm issue label updated

## Expected Format

PR title: `#{issue_number}: {brief description}`
Example: `#4: Add user authentication`

The argument provided is: `$ARGUMENTS`
