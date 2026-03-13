# GitHub Repo Protocols

This file defines the full GitHub repository lifecycle: setup, planning, implementation, and conventions. It is optional — if not symlinked into `~/.claude/`, the workflow is not enforced.

---

## 1. Repository Setup

### A. Create GitHub Repo

```bash
gh repo create <your-github-username>/{repo-name} --private
```

- **Always private** unless explicitly told otherwise
- For **single-agent repos**: add `--clone` to clone directly into `~/code/{repo-name}`
- For **multi-agent repos**: skip `--clone` — use multi-clone setup (section D below)

### B. Repo Settings

Apply immediately after creation:

```bash
gh repo edit <your-github-username>/{repo-name} \
  --enable-squash-merge \
  --enable-rebase-merge \
  --disable-merge-commit \
  --enable-auto-merge \
  --delete-branch-on-merge \
  --no-enable-wiki
```

### C. Standard Labels

Delete all GitHub default labels, then create the standard set:

```bash
# Delete GitHub defaults
for label in "bug" "documentation" "duplicate" "enhancement" "good first issue" \
  "help wanted" "invalid" "question" "wontfix"; do
  gh label delete "$label" --yes 2>/dev/null
done

# Status labels
gh label create "in-progress" --color "0e8a16" --description "Currently being worked on"
gh label create "in-review" --color "1d76db" --description "PR open, awaiting review"
gh label create "on-hold" --color "d93f0b" --description "Paused, waiting on external factor"
gh label create "blocked" --color "b60205" --description "Cannot proceed, dependency issue"

# Priority labels
gh label create "p0-critical" --color "b60205" --description "Drop everything"
gh label create "p1-high" --color "d93f0b" --description "Do next"
gh label create "p2-medium" --color "fbca04" --description "Normal priority"
gh label create "p3-low" --color "0e8a16" --description "Nice to have"

# Type labels
gh label create "bug" --color "d73a4a" --description "Something isn't working"
gh label create "enhancement" --color "a2eeef" --description "New feature or improvement"
gh label create "documentation" --color "0075ca" --description "Documentation changes"
gh label create "chore" --color "e4e669" --description "Maintenance, dependencies, config"

# Meta labels
gh label create "epic" --color "3e4b9e" --description "Tracking issue for a group of sub-issues"
gh label create "human-agent" --color "f9d0c4" --description "Requires manual human action"
```

**Agent labels** (multi-agent repos only):

Create one label per agent clone. The default setup uses 4 agents (0-3), but more can be added at any time with `add-agent`:

```bash
# Color palette for agent labels (cycles for agents beyond 7)
AGENT_COLORS=("0075ca" "1d76db" "5319e7" "0e8a16" "d93f0b" "e4e669" "006b75" "b60205")

# Create labels for initial agents (adjust range as needed)
for i in 0 1 2 3; do
  gh label create "agent-${i}" --color "${AGENT_COLORS[$i]}" --description "Being worked on by agent-${i}"
done
```

To add a label for a new agent later: `gh label create "agent-N" --color "HEX" --description "Being worked on by agent-N"`

Total: 14 base labels + 1 agent label per clone.

**Project-specific labels** (add as needed, NOT part of the standard set):
- Domain labels (`frontend`, `backend`, `database`, etc.) — when tech stack is clear
- Phase labels (`phase-1`, `phase-2`, etc.) — when project has a phased plan
- Quality labels (`security`, `performance`, `accessibility`) — for mature projects

### D. Clone Setup (Multi-Agent Repos)

See `~/.claude/multi-agent-system.md` for the full coordination guide. Quick setup:

```bash
REPO="my-repo"
AGENT_COUNT=4  # Adjust as needed (default: 4 agents, numbered 0-3)
mkdir -p ~/code/${REPO}-repos
for i in $(seq 0 $((AGENT_COUNT - 1))); do
  git clone git@github.com:<your-github-username>/${REPO}.git ~/code/${REPO}-repos/${REPO}-${i}
  git -C ~/code/${REPO}-repos/${REPO}-${i} checkout -b agent-${i} origin/main
done
```

After cloning:
- Copy `.env` / `.env.local` to each clone (if applicable)
- Run `npm install` (or `pnpm install`) in each clone (if applicable)
- Create agent labels (see above)

**Adding a clone later**: See `~/.claude/multi-agent-system.md` § "Adding an Agent to an Existing Repo".

### E. Initial Files

Create in the repo root (or clone-0 for multi-agent repos):

**README.md** — Generate from the initial plan/discussion:
```markdown
# {project-name}

{1-2 sentence description from the plan}

## Tech Stack

{List technologies from the plan}

## Getting Started

{Basic setup instructions}

## Development

{Development commands}
```

**CLAUDE.md** — Project-specific instructions:
```markdown
# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

> **Note**: This file contains only **project-specific** instructions.
> For general workflow conventions, see the global `~/.claude/CLAUDE.md`.

## Project Overview

{Description from plan}

## Development Commands

{Fill in based on project toolchain}

## Architecture Overview

{Fill in based on project structure}
```

For multi-agent repos, add to CLAUDE.md:
```markdown
## Multi-Agent Coordination

This repo uses independent clones. New agents can be added at any time.

See `~/.claude/multi-agent-system.md` for the full coordination protocol.

### Agent Labels
Each clone has a corresponding `agent-N` GitHub label for issue claiming.
```

**.gitignore** — Standard template (adapt per project):
```
node_modules/
dist/
build/
.env
.env.local
.env.*.local
*.log
.DS_Store
coverage/
.cache/
```

**.claudeignore** — Context filtering for Claude Code:
```
# Dependencies
node_modules/
.pnp.*

# Build outputs
dist/
build/
.next/
out/

# Cache
.cache/
.parcel-cache/
.turbo/

# Test coverage
coverage/
.nyc_output/

# Lock files (large, not useful for context)
package-lock.json
yarn.lock
pnpm-lock.yaml

# IDE
.idea/
.vscode/
*.swp

# Logs
*.log

# Environment
.env*

# Binary / media
*.png
*.jpg
*.jpeg
*.gif
*.ico
*.svg
*.woff
*.woff2
*.ttf
*.eot
*.mp4
*.webm
```

**.github/PULL_REQUEST_TEMPLATE.md**:
```markdown
## Summary

<!-- What does this PR do? -->

## Changes

<!-- Key changes made -->

## Test Plan

<!-- How was this tested? -->

## Issue

Closes #
```

### F. Optional: Husky Hooks

For TypeScript/Node projects with a build/lint toolchain:

```bash
npm install --save-dev husky lint-staged
npx husky init
```

Pre-commit (`.husky/pre-commit`):
```bash
#!/bin/sh
npx lint-staged
```

Pre-push (`.husky/pre-push`):
```bash
#!/bin/sh
npm run lint && npm run type-check && npm run test:run && npm run build
```

---

## 2. Planning & Issue Creation

**Every piece of work must have a GitHub issue** before starting. For non-trivial work, planning comes first.

### Workflow Overview

```
1. Assess Scope → 2. Plan (if needed) → 3. Create Issue(s) → 4. Implement
```

### Assess Scope

| Requires Planning | Direct Implementation |
|-------------------|----------------------|
| Multi-step features | Typo fixes |
| Architectural changes | Single-line changes |
| Unclear requirements | User provides exact implementation |
| Work spanning multiple issues | Follow-up on existing plan |
| New patterns/approaches | Bug with obvious fix |

### Enter Plan Mode (Non-Trivial Work)

1. **Use `EnterPlanMode` tool** to enter planning state
2. **Explore the codebase** to understand existing patterns and affected areas
3. **Design the approach** - identify files, risks, dependencies
4. **Write a clear plan** with numbered implementation steps
5. **Identify issue structure** - single issue or epic with sub-issues
6. **Identify human-agent tasks** - manual configuration, credentials, or dashboard work
7. **Exit plan mode** to get user approval before proceeding

**Plan contents should include:**
- Summary of the approach
- Files to be created/modified
- Key implementation decisions
- Testing strategy
- Potential risks or edge cases
- **Issue breakdown** - single issue vs epic with sub-issues
- **Human-agent tasks** - any work requiring manual human action

### CRITICAL: Plan Mode → Issue Creation → Implementation

```
⚠️  DO NOT start coding after exiting plan mode!

    Plan Mode Exit → Create GitHub Issue(s) → THEN Implement

    The plan is the "what". Issues are "how we track it".
```

**After user approves the plan**, your next action must be creating GitHub issues, NOT writing code. This applies even when continuing from a previous session with an existing plan.

### Create Issue(s) from Plan

#### Determining Issue Structure

| Criteria | Single Issue | Epic + Sub-Issues |
|----------|--------------|-------------------|
| PRs needed | 1 | 2+ |
| Distinct components | Tightly coupled | Can be developed/reviewed independently |
| Risk of large PR | Low | High (>500 lines changed) |
| Human-agent tasks | None | Any manual configuration needed |

**When in doubt, prefer epic structure.** Smaller PRs are easier to review and safer to roll back.

#### Single Issue

If completable in one PR with no human-agent follow-up:

```bash
gh issue create --title "Title" --body "$(cat <<'EOF'
## Summary
[From plan]

## Implementation Steps
[Numbered steps from plan]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
EOF
)"
```

#### Epic with Sub-Issues

If work spans multiple PRs OR requires human-agent tasks:

**Create the epic issue:**
```bash
gh issue create --title "[Epic] Feature Name" --label "epic" --body "$(cat <<'EOF'
## Overview
[High-level description from plan]

## Sub-Issues
<!-- Will be updated as sub-issues are created -->
- [ ] TBD - Database migration
- [ ] TBD - Backend implementation
- [ ] TBD - Frontend implementation
- [ ] TBD - Configuration (human-agent)

## Acceptance Criteria
- [ ] All sub-issues completed
- [ ] End-to-end flow verified
EOF
)"
```

**Create atomic sub-issues** (one PR each):
```bash
gh issue create --title "Add weekly_batches table migration" --body "Part of #<epic-number>

## Scope
- Create migration file
- Apply to production

Closes part of #<epic-number>"
```

**Create human-agent issues** for manual tasks:
```bash
gh issue create --title "Set environment variables in Render dashboard" \
  --label "human-agent" \
  --assignee "<your-github-username>" \
  --body "$(cat <<'EOF'
## Context
Part of #<epic-number>

## Required Actions
- [ ] Set `VAR_NAME` in Render dashboard
- [ ] Verify deployment succeeds

## Instructions
[Step-by-step guide for the human]
EOF
)"
```

**Update epic** with sub-issue links after creating all sub-issues.

#### Human-Agent Issue Checklist

Create a `human-agent` issue whenever the plan requires:
- [ ] Setting environment variables or secrets
- [ ] Configuring external services (Render, Stripe, etc.)
- [ ] Creating accounts or API keys
- [ ] Manual testing that requires human judgment
- [ ] Any action Claude cannot perform programmatically

#### Trigger Phrases

Start the plan-first workflow when the user:
- **Points out a bug** - "I found a bug where X doesn't work"
- **Suggests a change** - "Can you change the email subject to Y?"
- **Requests an implementation** - "Add a feature that does Z"
- **Asks to plan something** - "Let's plan out the authentication system"

#### Quick Tasks (Skip Planning)

For trivial changes, skip plan mode and go straight to issue creation:
- Typo fixes, config changes, simple style tweaks
- Changes where the user specifies exactly what to do

> "This is a straightforward change. Let me create an issue and implement it directly."

---

## 3. Implementation Workflow

Complete step-by-step workflow for implementing a GitHub issue.

### 1. Find and Understand the Issue

- Locate the issue by number or search
- Read the full description and acceptance criteria
- **Ask clarifying questions** if anything is unclear
- Update the issue description with any clarifications

### 2. Claim the Issue

```bash
gh issue edit <number> --add-label "in-progress"

# Multi-agent repos: also add your agent label
gh issue edit <number> --add-label "agent-N"
```

- **UPDATE SESSION LOG** - Log that work is starting

### 3. Create Feature Branch

```bash
# Standard repos:
git checkout main && git pull origin main
git checkout -b {issue-number}-{brief-description}

# Multi-clone repos (preferred — always starts from latest):
git fetch origin
git checkout -b {issue-number}-{brief-description} origin/main
```

### 4. Implement

- Write code to complete the issue
- **Write tests** for all work — features, bug fixes, anything testable
- Run verification suite (lint, type-check, test, build)
- **For UI changes**: verify in browser using Chrome automation
- Fix any errors before proceeding

### 5. Commit

- **Squash** all work into a single commit
- **Format**: `{issue_number}: {brief description}` (e.g., `4: Add user authentication`)
- **No AI attribution** — no "Co-Authored-By", no "Generated with Claude"
- **UPDATE SESSION LOG** before committing

### 6. Push and Create PR

```bash
git push -u origin {your-branch}
gh pr create --title "{issue_number}: {description}" --body "Closes #{issue_number}"
```

- **UPDATE SESSION LOG** - Log PR number, mark `#in-review`
- Update issue labels:
  ```bash
  gh issue view <number> --json state --jq '.state' | grep -q OPEN && \
    gh issue edit <number> --remove-label "in-progress" --add-label "in-review"
  ```

### 7. Merge PR

**Merge immediately** unless major architectural changes require human review:

```bash
gh pr merge --squash --delete-branch
```

- **UPDATE SESSION LOG** - Log merge

### 8. Post-Merge

**Migrations** (if applicable):
```bash
# Use Supabase MCP: apply_migration
# Then regenerate TypeScript types
```

**Return to clean state:**
```bash
# Standard repos:
git checkout main && git pull origin main

# Multi-clone repos:
git fetch origin && git checkout agent-{N} && git reset --hard origin/main
```

**Dependencies**: If package files changed upstream, run `npm install`.

### 9. Close Issue and Cleanup

```bash
gh issue close <number> --comment "Completed: <summary>"
gh issue edit <number> --remove-label "in-progress"

# Multi-agent repos:
gh issue edit <number> --remove-label "agent-N"
```

- **UPDATE SESSION LOG** - Mark `#completed`

### 10. Continue or Ask

- If given a queue of issues, move to the next one
- For epics, work through sub-issues sequentially (each as a separate PR)
- Otherwise, ask what to do next

```
Epic Implementation Flow:
┌─────────────────────────────────────────────────────┐
│  Epic #100                                          │
│  ├── Sub-issue #101 (migration) ──► PR #105 ──► ✓  │
│  ├── Sub-issue #102 (backend)   ──► PR #106 ──► ✓  │
│  ├── Sub-issue #103 (frontend)  ──► PR #107 ──► ✓  │
│  └── Sub-issue #104 (human-agent) ──► Human ──► ✓  │
│  All done? Close epic #100                          │
└─────────────────────────────────────────────────────┘
```

---

## 4. Conventions

### One Issue = One Branch = One PR

- Each GitHub issue gets its own dedicated branch and PR
- **Branch naming**: `{issue-number}-{brief-description}` (e.g., `4-add-user-auth`)
- **PR title**: `{issue_number}: {brief description}`
- **PR body**: Must include `Closes #{issue_number}` to auto-close on merge
- **Exception**: Only bundle issues if explicitly instructed or issues are inseparable

### PR Requirements

- PR title matches commit format
- All checks passing (lint, types, tests, build)
- No merge conflicts with main
- Uses repo's PR template if one exists

### Dependency Management After Git Operations

After any operation that pulls in changes (`git pull`, `git rebase`, `git merge`, `git checkout`):

```bash
# Check if package files changed
git diff HEAD@{1} --name-only | grep -E "package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml"

# If yes, run install
npm install  # Safe to run even if nothing changed
```

### Issue Selection Rules

When choosing issues to work on:
- **Skip** issues labeled `human-agent` (require manual human action)
- **Skip** issues labeled `in-progress` unless explicitly directed
- **Skip** issues labeled `in-review` unless explicitly directed

**Multi-agent repos only:**
- **Skip** issues with a different agent's label (e.g., agent-1 skips issues labeled `agent-2`)
- Do NOT check for agent labels in single-agent repos

### Discovering New Work

While working on an issue, if you discover:
- **Human-agent work required**: Create a new issue with `human-agent` label
- **Related follow-up work**: Create a new issue with appropriate labels
- **Blocking dependency**: Note it in your PR and link the blocking issue

---

## 5. Reference

### Human Agent

The human agent is the engineer supervising this project. All `human-agent` labeled issues are assigned to them. When creating issues that require human action (account setup, credentials, manual configuration), assign to the repo owner with the `human-agent` label.

**IMPORTANT**: Update the `--assignee` in human-agent issue creation commands to your own GitHub username.
