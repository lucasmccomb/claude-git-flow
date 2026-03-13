# claude-git-flow

A strict GitHub Issues workflow for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents. Enforces issue-first development with programmatic guardrails so that multiple engineers (and their agents) can work in the same repos with minimal conflicts.

```
Issue -> Branch -> Implement -> Commit -> PR -> Merge -> Return to main
```

## What It Enforces

- Every piece of work starts with a GitHub issue
- Branches named `{issue-number}-{description}`
- Commit messages formatted `{issue-number}: {description}`
- No commits directly on protected branches (must use feature branches)
- No pushes to protected branches (must use PRs)
- Squash merges, delete branch on merge
- No AI attribution in commits or PRs

### Protected Branches

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

## Quick Start

### Option A: Automated Setup (Recommended)

Clone the repo and run the setup script:

```bash
git clone https://github.com/lucasmccomb/claude-git-flow.git
cd claude-git-flow
bash setup.sh
```

The script will:
1. Detect conflicts with your existing config and ask how to resolve them
2. Show the default protected branches and prompt you to add more
3. Scan your existing Claude config for branch protection rules and suggest additions
4. Install hook scripts to `~/.claude/hooks/` (merging your customizations)
5. Install slash commands to `~/.claude/commands/`
6. Install the protocols reference to `~/.claude/`
7. Merge hook config into `~/.claude/settings.json` (non-destructive)
8. Print a full report of what was installed, resolved, and skipped

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

The agent will handle the entire setup, resolve any config conflicts, and give you a summary.

### Option C: Manual Setup

See [Manual Installation](#manual-installation) below.

---

## After Installation

### Replace placeholder username

```bash
# Replace <your-github-username> in the protocols file
sed -i'' -e 's/<your-github-username>/YOUR_GITHUB_USERNAME/g' ~/.claude/github-repo-protocols.md
```

### Add CLAUDE.md sections

The setup script installs hooks and commands, but you should also add the git workflow rules to your global `~/.claude/CLAUDE.md`. These are "soft rules" that help the agent understand the *why* behind the workflow.

Copy the contents of [`CLAUDE-git-sections.md`](CLAUDE-git-sections.md) into your `~/.claude/CLAUDE.md`.

### Verify it works

Start a Claude Code session in any git repo and try:

```
/gs
```

This should show your branch, working directory status, and open PRs.

---

## Available Commands

| Command | Description |
|---------|-------------|
| `/gs` | Show git status, current branch, open PRs |
| `/new-issue` | Create a GitHub issue with proper labels |
| `/commit` | Stage all changes + commit with `{issue}: {description}` format |
| `/pr` | Rebase on main + push + create PR that closes the issue |
| `/cpm` | One-shot: commit + PR + merge + close issue + return to main |
| `/sync` | Fetch origin + rebase current branch on main |

### Typical Workflow

```
/new-issue                              # Create issue #42
git checkout -b 42-add-login-page       # Create feature branch
... make changes ...
/cpm                                    # Commit, PR, merge, done
```

Or step by step:

```
/commit 42: Add login page              # Commit with issue number
/pr 42: Add login page                  # Push + create PR
gh pr merge --squash --delete-branch    # Merge
```

---

## How It Works

The system has four layers, each building on the last:

### Layer 1: CLAUDE.md (soft rules)

Instructions the agent reads and follows voluntarily. Covers conventions like "rebase by default", "check open PRs before branching", "no AI attribution in commits". Useful but not enforced - the agent can still ignore them.

### Layer 2: enforce-git-workflow.py (hard enforcement)

A [`PreToolUse` hook](https://docs.anthropic.com/en/docs/claude-code/hooks) that intercepts every `Bash` command. Blocks:

| Action | Result |
|--------|--------|
| `git commit` on any protected branch | **BLOCKED** - must use feature branch |
| `git commit -m "no issue number"` | **BLOCKED** - must use `{issue}: {desc}` format |
| `git push` to any protected branch | **BLOCKED** - must use PR workflow |

Protected branches: `main`, `master`, `production`, `prod`, `staging`, `stag`, `develop`, `dev`, `release`, `trunk` (plus any custom branches you add).

Emergency bypass: `ALLOW_MAIN_COMMIT=1 git commit ...`

### Layer 3: enforce-issue-workflow.py (the automation multiplier)

**This is where the real value is.** A `UserPromptSubmit` hook that fires before the agent even starts working. It detects work requests (verbs like "add", "fix", "implement", "build") and injects a workflow reminder directly into the agent's context:

```
STOP - Before making ANY code or file changes, you MUST:
1. CHECK: Does a GitHub issue exist for this work?
2. CREATE BRANCH: git checkout -b {issue-number}-{description}
3. IMPLEMENT: Make your changes
4. COMMIT & PR: git commit -m "{issue-number}: {description}"
```

**Why this matters**: Layers 1 and 2 catch mistakes *after* the agent tries to do something wrong. Layer 3 prevents them from happening in the first place by reshaping the agent's behavior *before it writes a single line of code*. Every work request, no matter how casually phrased ("fix the login bug", "add dark mode"), gets intercepted and turned into a structured workflow. The agent creates the issue, names the branch, implements, and follows through to PR - automatically, every time.

This is what makes the system work across multiple engineers. You don't need to train anyone on the workflow or review their process. The hook does it. Every agent, every session, every task follows the same flow.

Only active when `~/.claude/github-repo-protocols.md` exists. Delete that file to disable.

### Layer 4: Slash commands (automation)

The `/commit`, `/pr`, `/cpm`, `/gs`, `/sync`, and `/new-issue` commands automate the repetitive parts of the workflow so the agent doesn't have to remember the exact commands each time.

---

## Multi-Engineer Repos

When multiple engineers (each with their own Claude agents) work in the same repo:

1. **Each issue = one branch = one PR** - no overlap
2. **Squash merge** keeps main linear
3. **Pre-branch check** - agents check open PRs before creating branches to avoid dependency blindness
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
  setup.sh                              # Automated installer (interactive)
  CLAUDE-git-sections.md                # Git workflow rules for CLAUDE.md
  github-repo-protocols.md              # Full lifecycle reference
  hooks/
    enforce-git-workflow.py              # PreToolUse - blocks bad commits/pushes
    enforce-issue-workflow.py            # UserPromptSubmit - injects workflow reminder
  commands/
    commit.md                           # /commit
    pr.md                               # /pr
    cpm.md                              # /cpm
    gs.md                               # /gs
    sync.md                             # /sync
    new-issue.md                        # /new-issue

# Created during setup (in ~/.claude/):
  git-flow-protected-branches.json      # Custom branches beyond the defaults
```

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
| `enforce-git-workflow.py` | **Smart merge** - your `DIRECT_TO_MAIN_REPOS` entries are extracted and injected into the new version |
| `enforce-issue-workflow.py` | Interactive review or auto-replace with backup |
| Slash commands (`.md`) | Interactive review or auto-replace with backup |
| `github-repo-protocols.md` | Interactive review or auto-replace with backup |
| `settings.json` | **Always merges** - appends hook entries without touching your existing config |
| `CLAUDE.md` | **Never modified** - reports which sections are missing for you to add |
| Custom protected branches | **Always preserved** - stored in a separate JSON config file |

### Backups

All original files are backed up to `~/.claude/backups/git-flow-{timestamp}/` before any changes. You can restore them manually if needed.

### Non-interactive mode

For agent-driven installs, use `--non-interactive` to skip all prompts and auto-resolve everything:

```bash
bash setup.sh --non-interactive
```

---

## Customization

### Add custom protected branches

During `setup.sh`, you'll be prompted to add extra branches. You can also edit the config file directly:

```bash
# ~/.claude/git-flow-protected-branches.json
["qa", "uat", "hotfix", "demo"]
```

The hook reads this file at runtime and merges it with the built-in defaults. Changes take effect immediately (no reinstall needed).

Alternatively, edit `~/.claude/hooks/enforce-git-workflow.py` and modify the `PROTECTED_BRANCHES` list directly.

### Allow direct-to-main for specific repos

Edit `~/.claude/hooks/enforce-git-workflow.py`:

```python
DIRECT_TO_MAIN_REPOS = [
    "youruser/your-dotfiles",
]
```

### Disable the workflow reminder

Either:
- Remove the `UserPromptSubmit` section from `~/.claude/settings.json`
- Or delete `~/.claude/github-repo-protocols.md`

### Human-agent issues

Update the `--assignee` in `~/.claude/commands/new-issue.md` to your GitHub username.

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- [GitHub CLI (`gh`)](https://cli.github.com/) - authenticated with `gh auth login`
- `python3`
- `jq` (for setup script JSON merging) - `brew install jq` / `apt install jq`

---

## Manual Installation

If you prefer not to use the setup script:

### 1. Copy hook scripts

```bash
mkdir -p ~/.claude/hooks
cp hooks/enforce-git-workflow.py ~/.claude/hooks/
cp hooks/enforce-issue-workflow.py ~/.claude/hooks/
chmod +x ~/.claude/hooks/enforce-git-workflow.py
chmod +x ~/.claude/hooks/enforce-issue-workflow.py
```

### 2. Copy slash commands

```bash
mkdir -p ~/.claude/commands
cp commands/*.md ~/.claude/commands/
```

### 3. Copy protocols file

```bash
cp github-repo-protocols.md ~/.claude/github-repo-protocols.md
```

### 4. Add hooks to settings.json

Add to `~/.claude/settings.json` (create if it doesn't exist):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 $HOME/.claude/hooks/enforce-issue-workflow.py",
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
            "command": "$HOME/.claude/hooks/enforce-git-workflow.py",
            "timeout": 5000
          }
        ]
      }
    ]
  }
}
```

### 5. Add CLAUDE.md sections

Append the contents of `CLAUDE-git-sections.md` to your `~/.claude/CLAUDE.md`.

---

## License

MIT
