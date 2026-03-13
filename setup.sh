#!/usr/bin/env bash
#
# claude-git-flow setup script
#
# This script installs the git flow enforcement system for Claude Code.
# It can be run by a human OR by a Claude Code agent.
#
# Usage:
#   bash setup.sh                # Interactive setup
#   bash setup.sh --check        # Dry run - show what would change
#   bash setup.sh --uninstall    # Remove all installed components
#
# What it does:
#   1. Copies hook scripts to ~/.claude/hooks/
#   2. Copies slash commands to ~/.claude/commands/
#   3. Copies github-repo-protocols.md to ~/.claude/
#   4. Merges hook config into ~/.claude/settings.json
#   5. Reports what was added/changed
#
# Requires: python3, jq (for JSON merging)

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ─── Paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
PROTOCOLS_FILE="$CLAUDE_DIR/github-repo-protocols.md"
BACKUP_DIR="$CLAUDE_DIR/backups/git-flow-$(date +%Y%m%d-%H%M%S)"

# ─── State tracking ──────────────────────────────────────────────────
CHANGES_MADE=()
CONFLICTS=()
SKIPPED=()
DRY_RUN=false
UNINSTALL=false

# ─── Parse args ───────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --check|--dry-run) DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
    --help|-h)
      echo "Usage: bash setup.sh [--check|--uninstall|--help]"
      echo ""
      echo "  --check      Dry run - show what would change without modifying anything"
      echo "  --uninstall  Remove all installed components"
      echo "  --help       Show this help message"
      exit 0
      ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_skip()    { echo -e "${CYAN}[SKIP]${NC} $1"; }

# Check if a file differs from the source
files_differ() {
  local src="$1" dst="$2"
  if [ ! -f "$dst" ]; then
    return 0  # Destination doesn't exist = they differ
  fi
  ! diff -q "$src" "$dst" > /dev/null 2>&1
}

backup_file() {
  local file="$1"
  if [ -f "$file" ]; then
    mkdir -p "$BACKUP_DIR"
    cp "$file" "$BACKUP_DIR/$(basename "$file")"
    log_info "Backed up $(basename "$file") to $BACKUP_DIR/"
  fi
}

# ─── Preflight checks ────────────────────────────────────────────────
preflight() {
  echo ""
  echo -e "${BOLD}Claude Code Git Flow Setup${NC}"
  echo "═══════════════════════════════════════════"
  echo ""

  # Check python3
  if ! command -v python3 &> /dev/null; then
    log_error "python3 is required but not found. Install it first."
    exit 1
  fi

  # Check jq (needed for settings.json merging)
  if ! command -v jq &> /dev/null; then
    log_error "jq is required for JSON merging but not found."
    echo "  Install: brew install jq  (macOS) or apt install jq (Linux)"
    exit 1
  fi

  # Check gh CLI
  if ! command -v gh &> /dev/null; then
    log_warn "gh (GitHub CLI) not found. The workflow requires it for issue/PR operations."
    log_warn "Install: https://cli.github.com/"
  elif ! gh auth status &> /dev/null; then
    log_warn "gh CLI is not authenticated. Run: gh auth login"
  fi

  # Check Claude dir exists
  if [ ! -d "$CLAUDE_DIR" ]; then
    if $DRY_RUN; then
      log_info "Would create $CLAUDE_DIR"
    else
      mkdir -p "$CLAUDE_DIR"
      log_info "Created $CLAUDE_DIR"
    fi
  fi

  if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    echo ""
  fi
}

# ─── Uninstall ────────────────────────────────────────────────────────
do_uninstall() {
  echo ""
  echo -e "${BOLD}Uninstalling Claude Code Git Flow${NC}"
  echo "═══════════════════════════════════════════"
  echo ""

  local removed=()

  # Remove hook scripts
  for hook in enforce-git-workflow.py enforce-issue-workflow.py; do
    if [ -f "$HOOKS_DIR/$hook" ]; then
      rm "$HOOKS_DIR/$hook"
      removed+=("hooks/$hook")
    fi
  done

  # Remove commands
  for cmd in commit.md pr.md cpm.md gs.md sync.md new-issue.md; do
    if [ -f "$COMMANDS_DIR/$cmd" ]; then
      rm "$COMMANDS_DIR/$cmd"
      removed+=("commands/$cmd")
    fi
  done

  # Remove protocols file
  if [ -f "$PROTOCOLS_FILE" ]; then
    rm "$PROTOCOLS_FILE"
    removed+=("github-repo-protocols.md")
  fi

  # Note: We don't remove settings.json hooks entries automatically
  # because the user may have other hooks configured

  echo ""
  if [ ${#removed[@]} -gt 0 ]; then
    echo -e "${GREEN}Removed:${NC}"
    for item in "${removed[@]}"; do
      echo "  - ~/.claude/$item"
    done
    echo ""
    log_warn "Hook entries in ~/.claude/settings.json were NOT removed automatically."
    log_warn "Manually remove the UserPromptSubmit and PreToolUse entries for enforce-*-workflow.py"
  else
    log_info "Nothing to remove - git flow was not installed."
  fi
  echo ""
  exit 0
}

# ─── Install hooks ───────────────────────────────────────────────────
install_hooks() {
  echo -e "${BOLD}1. Hook Scripts${NC}"
  echo "───────────────────────────────────────────"

  mkdir -p "$HOOKS_DIR"

  for hook in enforce-git-workflow.py enforce-issue-workflow.py; do
    local src="$SCRIPT_DIR/hooks/$hook"
    local dst="$HOOKS_DIR/$hook"

    if [ ! -f "$src" ]; then
      log_error "Source file not found: $src"
      continue
    fi

    if [ -f "$dst" ]; then
      if files_differ "$src" "$dst"; then
        CONFLICTS+=("hooks/$hook - EXISTS and DIFFERS from source")
        if $DRY_RUN; then
          log_warn "CONFLICT: $hook already exists and differs"
          echo "    Existing: $dst"
          echo "    Source:   $src"
          echo "    Action:   Would backup existing and overwrite"
        else
          backup_file "$dst"
          cp "$src" "$dst"
          chmod +x "$dst"
          CHANGES_MADE+=("hooks/$hook - UPDATED (backup saved)")
          log_success "Updated $hook (backup saved)"
        fi
      else
        SKIPPED+=("hooks/$hook - already identical")
        log_skip "$hook already installed and identical"
      fi
    else
      if $DRY_RUN; then
        log_info "Would install: $hook"
      else
        cp "$src" "$dst"
        chmod +x "$dst"
        CHANGES_MADE+=("hooks/$hook - INSTALLED")
        log_success "Installed $hook"
      fi
    fi
  done
  echo ""
}

# ─── Install commands ────────────────────────────────────────────────
install_commands() {
  echo -e "${BOLD}2. Slash Commands${NC}"
  echo "───────────────────────────────────────────"

  mkdir -p "$COMMANDS_DIR"

  for cmd in commit.md pr.md cpm.md gs.md sync.md new-issue.md; do
    local src="$SCRIPT_DIR/commands/$cmd"
    local dst="$COMMANDS_DIR/$cmd"
    local name="${cmd%.md}"

    if [ ! -f "$src" ]; then
      log_error "Source file not found: $src"
      continue
    fi

    if [ -f "$dst" ]; then
      if files_differ "$src" "$dst"; then
        CONFLICTS+=("commands/$cmd (/$name) - EXISTS and DIFFERS")
        if $DRY_RUN; then
          log_warn "CONFLICT: /$name command already exists and differs"
          echo "    Action: Would backup existing and overwrite"
        else
          backup_file "$dst"
          cp "$src" "$dst"
          CHANGES_MADE+=("commands/$cmd (/$name) - UPDATED (backup saved)")
          log_success "Updated /$name (backup saved)"
        fi
      else
        SKIPPED+=("commands/$cmd (/$name) - already identical")
        log_skip "/$name already installed and identical"
      fi
    else
      if $DRY_RUN; then
        log_info "Would install: /$name"
      else
        cp "$src" "$dst"
        CHANGES_MADE+=("commands/$cmd (/$name) - INSTALLED")
        log_success "Installed /$name"
      fi
    fi
  done
  echo ""
}

# ─── Install protocols file ─────────────────────────────────────────
install_protocols() {
  echo -e "${BOLD}3. GitHub Repo Protocols${NC}"
  echo "───────────────────────────────────────────"

  local src="$SCRIPT_DIR/github-repo-protocols.md"
  local dst="$PROTOCOLS_FILE"

  if [ -f "$dst" ]; then
    if files_differ "$src" "$dst"; then
      CONFLICTS+=("github-repo-protocols.md - EXISTS and DIFFERS")
      if $DRY_RUN; then
        log_warn "CONFLICT: github-repo-protocols.md already exists and differs"
        echo "    Action: Would backup existing and overwrite"
      else
        backup_file "$dst"
        cp "$src" "$dst"
        CHANGES_MADE+=("github-repo-protocols.md - UPDATED (backup saved)")
        log_success "Updated github-repo-protocols.md (backup saved)"
      fi
    else
      SKIPPED+=("github-repo-protocols.md - already identical")
      log_skip "github-repo-protocols.md already installed and identical"
    fi
  else
    if $DRY_RUN; then
      log_info "Would install: github-repo-protocols.md"
    else
      cp "$src" "$dst"
      CHANGES_MADE+=("github-repo-protocols.md - INSTALLED")
      log_success "Installed github-repo-protocols.md"
    fi
  fi

  # Check for placeholder username
  if [ -f "$dst" ] && grep -q "<your-github-username>" "$dst" 2>/dev/null; then
    log_warn "github-repo-protocols.md contains '<your-github-username>' placeholders."
    log_warn "Replace with your actual GitHub username:"
    echo "    sed -i'' -e 's/<your-github-username>/YOUR_USERNAME/g' $dst"
  fi
  echo ""
}

# ─── Merge settings.json hooks ───────────────────────────────────────
install_settings_hooks() {
  echo -e "${BOLD}4. Settings.json Hook Configuration${NC}"
  echo "───────────────────────────────────────────"

  # Define the hooks we need to add
  local user_prompt_hook='{"hooks":[{"type":"command","command":"python3 $HOME/.claude/hooks/enforce-issue-workflow.py","timeout":5000}]}'
  local pre_tool_hook='{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/enforce-git-workflow.py","timeout":5000}]}'

  if [ ! -f "$SETTINGS_FILE" ]; then
    # No settings.json exists - create one with just hooks
    if $DRY_RUN; then
      log_info "Would create settings.json with hook configuration"
    else
      cat > "$SETTINGS_FILE" << 'SETTINGS_EOF'
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
SETTINGS_EOF
      CHANGES_MADE+=("settings.json - CREATED with hook configuration")
      log_success "Created settings.json with hook configuration"
    fi
  else
    # settings.json exists - need to merge hooks
    backup_file "$SETTINGS_FILE"

    # Check what's already there
    local has_user_prompt=false
    local has_pre_tool=false

    if jq -e '.hooks.UserPromptSubmit' "$SETTINGS_FILE" > /dev/null 2>&1; then
      # Check if our specific hook is already there
      if jq -e '.hooks.UserPromptSubmit[]?.hooks[]? | select(.command | contains("enforce-issue-workflow"))' "$SETTINGS_FILE" > /dev/null 2>&1; then
        has_user_prompt=true
      fi
    fi

    if jq -e '.hooks.PreToolUse' "$SETTINGS_FILE" > /dev/null 2>&1; then
      if jq -e '.hooks.PreToolUse[]? | select(.hooks[]?.command | contains("enforce-git-workflow"))' "$SETTINGS_FILE" > /dev/null 2>&1; then
        has_pre_tool=true
      fi
    fi

    if $has_user_prompt && $has_pre_tool; then
      SKIPPED+=("settings.json hooks - already configured")
      log_skip "Both hooks already configured in settings.json"
    else
      if $DRY_RUN; then
        if ! $has_user_prompt; then
          log_info "Would add UserPromptSubmit hook (enforce-issue-workflow.py)"
        fi
        if ! $has_pre_tool; then
          log_info "Would add PreToolUse hook (enforce-git-workflow.py)"
        fi
        if jq -e '.hooks' "$SETTINGS_FILE" > /dev/null 2>&1; then
          CONFLICTS+=("settings.json - has existing hooks config that will be extended")
        fi
      else
        local tmp_file
        tmp_file=$(mktemp)

        # Start with current settings
        cp "$SETTINGS_FILE" "$tmp_file"

        # Ensure hooks object exists
        if ! jq -e '.hooks' "$tmp_file" > /dev/null 2>&1; then
          jq '. + {"hooks":{}}' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
        fi

        # Add UserPromptSubmit if missing
        if ! $has_user_prompt; then
          if jq -e '.hooks.UserPromptSubmit' "$tmp_file" > /dev/null 2>&1; then
            # Array exists, append our hook
            jq '.hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":"python3 $HOME/.claude/hooks/enforce-issue-workflow.py","timeout":5000}]}]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
          else
            # Create the array
            jq '.hooks.UserPromptSubmit = [{"hooks":[{"type":"command","command":"python3 $HOME/.claude/hooks/enforce-issue-workflow.py","timeout":5000}]}]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
          fi
          CHANGES_MADE+=("settings.json - Added UserPromptSubmit hook")
          log_success "Added UserPromptSubmit hook (enforce-issue-workflow.py)"
        fi

        # Add PreToolUse if missing
        if ! $has_pre_tool; then
          if jq -e '.hooks.PreToolUse' "$tmp_file" > /dev/null 2>&1; then
            # Array exists, append our hook
            jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/enforce-git-workflow.py","timeout":5000}]}]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
          else
            # Create the array
            jq '.hooks.PreToolUse = [{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/enforce-git-workflow.py","timeout":5000}]}]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
          fi
          CHANGES_MADE+=("settings.json - Added PreToolUse hook")
          log_success "Added PreToolUse hook (enforce-git-workflow.py)"
        fi

        # Write back
        mv "$tmp_file" "$SETTINGS_FILE"
        log_info "Backup saved before changes"
      fi
    fi
  fi
  echo ""
}

# ─── Check CLAUDE.md ─────────────────────────────────────────────────
check_claude_md() {
  echo -e "${BOLD}5. CLAUDE.md Git Flow Sections${NC}"
  echo "───────────────────────────────────────────"

  local claude_md="$CLAUDE_DIR/CLAUDE.md"
  local sections_file="$SCRIPT_DIR/CLAUDE-git-sections.md"

  if [ ! -f "$claude_md" ]; then
    if $DRY_RUN; then
      log_info "No ~/.claude/CLAUDE.md found."
      log_info "Would note: You should create one and add the git flow sections."
    else
      log_warn "No ~/.claude/CLAUDE.md found."
      log_warn "You should create ~/.claude/CLAUDE.md and add the contents of:"
      echo "    $sections_file"
      CHANGES_MADE+=("CLAUDE.md - ACTION REQUIRED: Add git flow sections manually")
    fi
  else
    # Check if key sections already exist
    local has_no_ai=$(grep -c "No AI Attribution in Commits" "$claude_md" 2>/dev/null || true)
    local has_pr_template=$(grep -c "Use PR Templates When Creating Pull Requests" "$claude_md" 2>/dev/null || true)
    local has_rebase=$(grep -c "Branch Updates: Rebase by Default" "$claude_md" 2>/dev/null || true)
    local has_post_merge=$(grep -c "Post-Merge: Return to Main" "$claude_md" 2>/dev/null || true)
    local has_sync=$(grep -c "Sync Before Any Git History Changes" "$claude_md" 2>/dev/null || true)

    local missing=0
    local present=0

    for check in "$has_no_ai" "$has_pr_template" "$has_rebase" "$has_post_merge" "$has_sync"; do
      if [ "$check" -gt 0 ]; then
        ((present++))
      else
        ((missing++))
      fi
    done

    if [ "$missing" -eq 0 ]; then
      SKIPPED+=("CLAUDE.md - all git flow sections already present")
      log_skip "All key git flow sections already present in CLAUDE.md"
    elif [ "$present" -gt 0 ]; then
      CONFLICTS+=("CLAUDE.md - has $present of 5 git flow sections; $missing missing")
      log_warn "CLAUDE.md has some git flow sections ($present/5 found, $missing missing)"
      log_warn "Review and add missing sections from:"
      echo "    $sections_file"
      echo ""
      echo "    Missing sections:"
      [ "$has_no_ai" -eq 0 ] && echo "      - No AI Attribution in Commits"
      [ "$has_pr_template" -eq 0 ] && echo "      - Use PR Templates When Creating Pull Requests"
      [ "$has_sync" -eq 0 ] && echo "      - Sync Before Any Git History Changes"
      [ "$has_rebase" -eq 0 ] && echo "      - Branch Updates: Rebase by Default"
      [ "$has_post_merge" -eq 0 ] && echo "      - Post-Merge: Return to Main"
    else
      log_warn "CLAUDE.md exists but has none of the git flow sections."
      log_warn "Add the contents of this file to your CLAUDE.md:"
      echo "    $sections_file"
      CHANGES_MADE+=("CLAUDE.md - ACTION REQUIRED: Add git flow sections")
    fi
  fi
  echo ""
}

# ─── Summary report ──────────────────────────────────────────────────
print_report() {
  echo ""
  echo "═══════════════════════════════════════════"
  if $DRY_RUN; then
    echo -e "${BOLD}DRY RUN REPORT${NC}"
  else
    echo -e "${BOLD}INSTALLATION REPORT${NC}"
  fi
  echo "═══════════════════════════════════════════"
  echo ""

  if [ ${#CHANGES_MADE[@]} -gt 0 ]; then
    echo -e "${GREEN}Changes Made:${NC}"
    for change in "${CHANGES_MADE[@]}"; do
      echo "  + $change"
    done
    echo ""
  fi

  if [ ${#CONFLICTS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Conflicts / Manual Review Needed:${NC}"
    for conflict in "${CONFLICTS[@]}"; do
      echo "  ! $conflict"
    done
    echo ""
    if ! $DRY_RUN; then
      echo "  Backups saved to: $BACKUP_DIR"
      echo ""
    fi
  fi

  if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${CYAN}Skipped (already installed):${NC}"
    for skip in "${SKIPPED[@]}"; do
      echo "  - $skip"
    done
    echo ""
  fi

  if ! $DRY_RUN && [ ${#CHANGES_MADE[@]} -gt 0 ]; then
    echo "───────────────────────────────────────────"
    echo -e "${BOLD}Quick Reference - Available Commands:${NC}"
    echo ""
    echo "  /gs         Show git status, branch, open PRs"
    echo "  /new-issue  Create a GitHub issue with labels"
    echo "  /commit     Stage + commit (format: {issue}: {description})"
    echo "  /pr         Push + create PR that closes the issue"
    echo "  /cpm        One-shot: commit + PR + merge + cleanup"
    echo "  /sync       Fetch origin + rebase on main"
    echo ""
    echo "───────────────────────────────────────────"
    echo -e "${BOLD}Workflow:${NC}"
    echo ""
    echo "  1. /new-issue  (or gh issue create)"
    echo "  2. git checkout -b {issue-number}-{description}"
    echo "  3. Make changes"
    echo "  4. /cpm  (or /commit then /pr then merge)"
    echo ""
    echo "  The hooks will block you if you try to:"
    echo "    - Commit on main"
    echo "    - Commit without issue number prefix"
    echo "    - Push directly to main"
    echo ""
  fi

  if [ ${#CHANGES_MADE[@]} -eq 0 ] && [ ${#CONFLICTS[@]} -eq 0 ]; then
    echo -e "${GREEN}Everything is already installed! No changes needed.${NC}"
    echo ""
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────
main() {
  if $UNINSTALL; then
    do_uninstall
    exit 0
  fi

  preflight
  install_hooks
  install_commands
  install_protocols
  install_settings_hooks
  check_claude_md
  print_report
}

main
