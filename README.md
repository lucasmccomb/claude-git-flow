# claude-git-flow

Enforced GitHub Issues workflow for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents. Hooks block bad behavior, commands automate the good behavior, logs coordinate multiple developers.

```
Issue -> Branch -> Implement -> Commit -> PR -> Merge -> Return to main
```

## Why This Exists

Agents ignore conventions without enforcement. When multiple developers (or agents) work in the same repo, you need:

- **Rules that can't be bypassed** (hooks that block bad commits/pushes)
- **Coordination that happens automatically** (injected context, not manual commands)
- **A record of who did what** (git-tracked logs)

CLAUDE.md instructions are suggestions. Hooks are laws. This system uses both.

## How It Works

### Layer 1: Hooks (hard enforcement)

**enforce-git-workflow.py** (PreToolUse) - Intercepts every `Bash` command. Blocks commits on protected branches. Requires `#42:` format in messages. Blocks pushes to protected branches. You can't accidentally skip the workflow.

**enforce-issue-workflow.py** (UserPromptSubmit) - Intercepts every prompt. Detects work requests ("add", "fix", "implement") and injects the full workflow: create issue, create branch, check coordination logs, then implement. This is the most powerful layer - it reshapes the agent's behavior before it writes a single line of code.

### Layer 2: Commands (automation)

Shortcuts for multi-step git operations with the right format:

| Command | What it does |
|---------|-------------|
| `/gs` | Show git status, current branch, open PRs |
| `/new-issue` | Create a GitHub issue with proper labels |
| `/commit` | Stage + commit with `#42: description` format |
| `/pr` | Rebase + push + create PR with `Closes #42` |
| `/cpm` | One-shot: commit + PR + merge (for solo repos) |

### Layer 3: Logging (coordination)

`.claude/logs/` in the project repo. Each agent writes a daily log. Other agents read these logs to detect file conflicts and understand context. Maintained automatically through CLAUDE.md instructions and hook-injected reminders - no explicit commands needed.

```
.claude/logs/
  YYYYMMDD/
    agent-0.md        # Each agent's session log
    agent-1.md
  learnings.md        # Persistent cross-developer knowledge
```

## Quick Start

### Option A: Automated Setup (Recommended)

```bash
git clone https://github.com/lucasmccomb/claude-git-flow.git
cd claude-git-flow
bash setup.sh
```

The script will:
1. Ask where to install: **project-level** (default, `.claude/` in your repo) or **global** (`~/.claude/`)
2. Detect conflicts with existing config and offer to resolve them
3. Show default protected branches and prompt you to add more
4. Install hook scripts and slash commands
5. Merge hook config into settings.json (non-destructive)
6. Create `.claude/logs/` directory (project-level only)
7. Print a full report of what was installed

**Global install** (all repos, single config):
```bash
bash setup.sh --global
```

**Preview first** (no changes made):
```bash
bash setup.sh --check
```

**Uninstall:**
```bash
bash setup.sh --uninstall
```

### Option B: Let Your Claude Agent Do It

Tell your Claude Code agent:

> Clone https://github.com/lucasmccomb/claude-git-flow.git and run `bash setup.sh --check` to preview, then `bash setup.sh` to install. Report back what was changed and any conflicts.

### Option C: Manual Installation

See [Manual Installation](#manual-installation) below.

---

## After Installation

### Add CLAUDE.md sections

The hooks enforce the rules, but adding workflow context to your CLAUDE.md helps agents understand the *why*. Copy this block into your project or global `CLAUDE.md`:

```markdown
# Git Workflow

## Commit Format
All commits use `#{issue_number}: {description}` format.
- Example: `#42: Fix login validation`
- Log/coordination commits use `sync: {description}` (no issue number)

## Branch Workflow
1. Every piece of work starts with a GitHub issue
2. Branch from origin/main: `git checkout -b {issue#}-{description} origin/main`
3. Commit with issue prefix: `git commit -m "#42: description"`
4. Create PR: `gh pr create --title "#42: description" --body "Closes #42"`
5. Squash merge, delete branch, return to main

## Protected Branches
Cannot commit or push directly to: main, master, production, prod,
staging, stag, develop, dev, release, trunk. Use feature branches + PRs.

## Coordination (multi-developer repos)
- Read `.claude/logs/` before starting work to check for conflicts
- Write your session log to `.claude/logs/YYYYMMDD/agent-N.md`
- Include: issue number, branch, files claimed, decisions, handoff notes

## No AI Attribution
Never add Co-Authored-By trailers, "Generated with Claude Code", or
any AI attribution to commits, PRs, or git metadata.
```

### Verify it works

Start a Claude Code session in any git repo and try:

```
/gs
```

This should show your branch, working directory status, and open PRs.

---

## Typical Workflow

```
/new-issue                              # Create issue #42
git checkout -b 42-add-login-page origin/main
... make changes ...
/cpm                                    # Commit, PR, merge, done
```

Or step by step:

```
/commit #42: Add login page             # Commit with issue number
/pr #42: Add login page                 # Push + create PR
gh pr merge --squash --delete-branch    # Merge
```

---

## Multi-Engineer Repos

When multiple engineers (each with their own Claude agents) work in the same repo:

1. **Each issue = one branch = one PR** - no overlap
2. **Squash merge** keeps main linear
3. **Coordination logs** in `.claude/logs/` - agents read other sessions before starting
4. **Rebase by default** - feature branches rebase on main, not merge

### Recommended repo settings

```bash
gh repo edit owner/repo \
  --enable-squash-merge \
  --enable-rebase-merge \
  --disable-merge-commit \
  --enable-auto-merge \
  --delete-branch-on-merge
```

---

## What's Included

```
claude-git-flow/
  README.md                             # This file
  setup.sh                              # Automated installer
  LICENSE                               # MIT
  hooks/
    enforce-git-workflow.py              # PreToolUse - blocks bad commits/pushes
    enforce-issue-workflow.py            # UserPromptSubmit - injects workflow reminder
  commands/
    commit.md                           # /commit
    pr.md                               # /pr
    cpm.md                              # /cpm (solo repos)
    gs.md                               # /gs
    new-issue.md                        # /new-issue
  templates/
    logs/
      agent.md                          # Session log template
      learnings.md                      # Shared learnings template
```

---

## Protected Branches

The following branches are blocked from direct commits and pushes by default:

| Branch | Common Use |
|--------|-----------|
| `main` | Primary branch (GitHub default) |
| `master` | Primary branch (legacy default) |
| `production` | Production deployment branch |
| `prod` | Short form of production |
| `staging` | Pre-production/QA environment |
| `stag` | Short form of staging |
| `develop` | Integration branch (git-flow) |
| `dev` | Short form of develop |
| `release` | Release preparation branch |
| `trunk` | Primary branch (SVN/some teams) |

**Custom branches** can be added during setup or later (see [Customization](#customization)).

---

## Customization

### Add custom protected branches

During `setup.sh`, you'll be prompted to add extra branches. You can also edit the config file directly:

```bash
# In your .claude/ directory (project or global)
# git-flow-protected-branches.json
["qa", "uat", "hotfix", "demo"]
```

The hook reads this file at runtime and merges it with the built-in defaults. Changes take effect immediately (no reinstall needed).

### Allow direct-to-main for specific repos

Edit the `enforce-git-workflow.py` hook:

```python
DIRECT_TO_MAIN_REPOS = [
    "youruser/your-dotfiles",
]
```

### Disable the workflow reminder

Remove the `UserPromptSubmit` section from your `settings.json`.

### Commit format

Regular commits: `#42: description` (GitHub auto-links `#42` to the issue)
Coordination commits: `sync: description` (for log updates, no issue needed)

---

## Conflict Resolution

If you already have Claude Code hooks, commands, or config, the setup script detects conflicts and resolves them without losing your customizations.

### Upfront mode selection

At the start of setup (if any conflicts are detected), you choose:

| Mode | Behavior |
|------|----------|
| **Interactive** (default) | Shows a diff for each conflict and lets you merge, overwrite, or skip |
| **Auto-resolve** | Merges your customizations into the new versions automatically, backups saved |

### What gets merged vs replaced

| File | Conflict behavior |
|------|-------------------|
| `enforce-git-workflow.py` | **Smart merge** - your `DIRECT_TO_MAIN_REPOS` entries are preserved |
| `enforce-issue-workflow.py` | Interactive review or auto-replace with backup |
| Slash commands (`.md`) | Interactive review or auto-replace with backup |
| `settings.json` | **Always merges** - appends hook entries without touching existing config |
| `CLAUDE.md` | **Never modified** - reports which sections may be missing |
| Custom protected branches | **Always preserved** - stored in a separate JSON config file |

### Backups

All original files are backed up to `.claude/backups/git-flow-{timestamp}/` before any changes. You can restore them manually if needed.

### Non-interactive mode

For agent-driven installs:

```bash
bash setup.sh --non-interactive
```

---

## Manual Installation

If you prefer not to use the setup script:

### 1. Copy hook scripts

```bash
# Project-level (recommended)
mkdir -p .claude/hooks
cp hooks/enforce-git-workflow.py .claude/hooks/
cp hooks/enforce-issue-workflow.py .claude/hooks/
chmod +x .claude/hooks/enforce-git-workflow.py
chmod +x .claude/hooks/enforce-issue-workflow.py

# OR global
mkdir -p ~/.claude/hooks
cp hooks/enforce-git-workflow.py ~/.claude/hooks/
cp hooks/enforce-issue-workflow.py ~/.claude/hooks/
chmod +x ~/.claude/hooks/enforce-git-workflow.py
chmod +x ~/.claude/hooks/enforce-issue-workflow.py
```

### 2. Copy slash commands

```bash
# Project-level
mkdir -p .claude/commands
cp commands/*.md .claude/commands/

# OR global
mkdir -p ~/.claude/commands
cp commands/*.md ~/.claude/commands/
```

### 3. Create logs directory (project-level only)

```bash
mkdir -p .claude/logs
cp templates/logs/learnings.md .claude/logs/
```

### 4. Add hooks to settings.json

Add to your `.claude/settings.json` (project) or `~/.claude/settings.json` (global):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 .claude/hooks/enforce-issue-workflow.py",
            "timeout": 5000
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/enforce-git-workflow.py",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

For global install, replace `.claude/` paths with `$HOME/.claude/`.

### 5. Add CLAUDE.md sections

Copy the "Copy to Your CLAUDE.md" block from above into your CLAUDE.md.

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub CLI (`gh`)](https://cli.github.com/) - authenticated with `gh auth login`
- `python3`
- `jq` (for setup script JSON merging) - `brew install jq` / `apt install jq`

---

## License

MIT
