---
description: Create a new GitHub issue with proper labels
allowed-tools: Bash(gh:*), AskUserQuestion
---

# Create GitHub Issue

## Repository Info

- Current repo: !`gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "Not in a GitHub repo"`
- Existing labels: !`gh label list --limit 20 2>/dev/null || echo "Unable to fetch labels"`

## Your Task

If `$ARGUMENTS` is provided, use it as the issue title. Otherwise, ask for details.

1. **Gather issue details**

   Ask the user (if not provided):
   - Title: Brief description of the issue
   - Type: feature, bug, refactor, or human-agent
   - Description: More details about what needs to be done

2. **Determine labels**

   Based on issue type:
   - `feature` → `enhancement`
   - `bug` → `bug`
   - `refactor` → `refactor` (create if doesn't exist)
   - `human-agent` → `human-agent` (assign to the repo owner)

   Also consider adding:
   - `web` or `ios` based on affected platform
   - `priority:high` if urgent

3. **Create the issue**

   ```bash
   gh issue create --title "<title>" --body "<description>" --label "<labels>"
   ```

   If human-agent:
   ```bash
   gh issue create --title "<title>" --body "<description>" --label "human-agent" --assignee "<repo-owner>"
   ```

4. **Report result**
   - Show issue number and URL
   - Suggest next steps (e.g., "Run /commit to start working on it")

## Issue Title Format

Good titles:
- "Add user authentication flow"
- "Fix calendar grid alignment on mobile"
- "Refactor habit service for better error handling"
- "[Human Agent] Set up Render deployment"

Provided argument: `$ARGUMENTS`
