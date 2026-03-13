# claude-git-flow

A strict GitHub Issues workflow for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents. Enforces issue-first development with programmatic guardrails so that multiple engineers (and their agents) can work in the same repos with minimal conflicts.

```
Issue -> Branch -> Implement -> Commit -> PR -> Merge -> Return to main
```

## What It Enforces

- Every piece of work starts with a GitHub issue
- Branches named `{issue-number}-{description}`
- Commit messages formatted `{issue-number}: {description}`
- No commits directly on `main` (must use feature branches)
- No pushes to `main` (must use PRs)
- Squash merges, delete branch on merge
- No AI attribution in commits or PRs

## Quick Start

### Option A: Automated Setup (Recommended)

Clone the repo and run the setup script:

```bash
git clone https://github.com/lucasmccomb/claude-git-flow.git
cd claude-git-flow
bash setup.sh
```

The script will:
1. Copy hook scripts to `~/.claude/hooks/`
2. Copy slash commands to `~/.claude/commands/`
3. Copy the protocols reference to `~/.claude/`
4. Merge hook config into `~/.claude/settings.json`
5. Detect conflicts with your existing config and back up before overwriting
6. Print a full report of what was added/changed

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

The system has four layers:

### Layer 1: CLAUDE.md (soft rules)

Instructions the agent reads and follows. Covers conventions like "rebase by default", "check open PRs before branching", "no AI attribution in commits".

### Layer 2: enforce-git-workflow.py (hard enforcement)

A [`PreToolUse` hook](https://docs.anthropic.com/en/docs/claude-code/hooks) that intercepts every `Bash` command. Blocks:

| Action | Result |
|--------|--------|
| `git commit` on `main` | **BLOCKED** - must use feature branch |
| `git commit -m "no issue number"` | **BLOCKED** - must use `{issue}: {desc}` format |
| `git push` to `main` | **BLOCKED** - must use PR workflow |

Emergency bypass: `ALLOW_MAIN_COMMIT=1 git commit ...`

### Layer 3: enforce-issue-workflow.py (context injection)

A `UserPromptSubmit` hook that detects work requests (verbs like "add", "fix", "implement") and injects a reminder: "STOP - create an issue first."

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
  setup.sh                              # Automated installer
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
```

---

## Customization

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
