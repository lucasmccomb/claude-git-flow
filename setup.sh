#!/usr/bin/env bash
#
# claude-git-flow setup script
#
# Installs the git flow enforcement system for Claude Code.
# Can be run by a human OR by a Claude Code agent.
#
# Usage:
#   bash setup.sh                # Install to current repo's .claude/ (project-level)
#   bash setup.sh --global       # Install to ~/.claude/ (global, all repos)
#   bash setup.sh --check        # Dry run - show what would change
#   bash setup.sh --uninstall    # Remove all installed components
#
# What it does:
#   1. Asks how to handle conflicts (interactive review or auto-resolve)
#   2. Copies hook scripts to target hooks directory (merges customizations)
#   3. Copies slash commands to target commands directory
#   4. Merges hook config into target settings.json
#   5. Creates .claude/logs/ directory (project-level only)
#   6. Reports what was added/changed/resolved
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

# ─── State tracking ──────────────────────────────────────────────────
CHANGES_MADE=()
CONFLICTS=()
SKIPPED=()
DRY_RUN=false
UNINSTALL=false
NON_INTERACTIVE=false
CONFLICT_MODE=""  # "interactive" or "auto" - set during setup
INSTALL_MODE=""   # "project" or "global" - set during setup

# ─── Parse args ───────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --check|--dry-run) DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
    --global) INSTALL_MODE="global" ;;
    --non-interactive|-y) NON_INTERACTIVE=true ;;
    --help|-h)
      echo "Usage: bash setup.sh [OPTIONS]"
      echo ""
      echo "  --check             Dry run - show what would change without modifying anything"
      echo "  --global            Install to ~/.claude/ (global, works for all repos)"
      echo "  --uninstall         Remove all installed components"
      echo "  --non-interactive   Skip prompts, use defaults (for agent-driven installs)"
      echo "  --help              Show this help message"
      echo ""
      echo "Default: Install to current repo's .claude/ (project-level, git-tracked)"
      exit 0
      ;;
  esac
done

# ─── Derived paths (set after install mode is determined) ─────────────
CLAUDE_DIR=""
HOOKS_DIR=""
COMMANDS_DIR=""
SETTINGS_FILE=""
BACKUP_DIR=""
CUSTOM_BRANCHES_FILE=""
LOGS_DIR=""

set_paths() {
  if [ "$INSTALL_MODE" = "global" ]; then
    CLAUDE_DIR="$HOME/.claude"
  else
    CLAUDE_DIR="$(pwd)/.claude"
  fi
  HOOKS_DIR="$CLAUDE_DIR/hooks"
  COMMANDS_DIR="$CLAUDE_DIR/commands"
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  BACKUP_DIR="$CLAUDE_DIR/backups/git-flow-$(date +%Y%m%d-%H%M%S)"
  CUSTOM_BRANCHES_FILE="$CLAUDE_DIR/git-flow-protected-branches.json"
  LOGS_DIR="$CLAUDE_DIR/logs"
}

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

# ─── Conflict resolution helpers ────────────────────────────────────

# Ask user upfront how they want conflicts handled.
choose_conflict_mode() {
  if $DRY_RUN || $NON_INTERACTIVE; then
    CONFLICT_MODE="auto"
    return
  fi

  # Check if any conflicts actually exist before asking
  local has_conflicts=false
  for hook in enforce-git-workflow.py enforce-issue-workflow.py; do
    if [ -f "$HOOKS_DIR/$hook" ] && files_differ "$SCRIPT_DIR/hooks/$hook" "$HOOKS_DIR/$hook"; then
      has_conflicts=true; break
    fi
  done
  if ! $has_conflicts; then
    for cmd in commit.md pr.md cpm.md gs.md new-issue.md; do
      if [ -f "$COMMANDS_DIR/$cmd" ] && files_differ "$SCRIPT_DIR/commands/$cmd" "$COMMANDS_DIR/$cmd"; then
        has_conflicts=true; break
      fi
    done
  fi

  if ! $has_conflicts; then
    CONFLICT_MODE="auto"  # No conflicts, doesn't matter
    return
  fi

  echo -e "${BOLD}Conflict Resolution${NC}"
  echo "───────────────────────────────────────────"
  echo ""
  echo "  Some existing files differ from the versions being installed."
  echo "  How would you like to handle conflicts?"
  echo ""
  echo "    1) ${BOLD}Interactive${NC} - Review each conflict with a diff and"
  echo "       choose to merge, overwrite, or skip"
  echo ""
  echo "    2) ${BOLD}Auto-resolve${NC} - Automatically merge your customizations"
  echo "       into the new versions (backups saved for all changes)"
  echo ""
  read -r -p "  Choose [1/2] (default: 1): " mode_choice
  case "$mode_choice" in
    2) CONFLICT_MODE="auto" ;;
    *) CONFLICT_MODE="interactive" ;;
  esac
  echo ""
}

# Extract user customizations from an existing enforce-git-workflow.py.
# Outputs the DIRECT_TO_MAIN_REPOS entries (one per line, without quotes/commas).
extract_direct_to_main_repos() {
  local file="$1"
  # Extract lines between DIRECT_TO_MAIN_REPOS = [ and ], grab quoted strings
  python3 -c "
import re, sys
content = open('$file').read()
m = re.search(r'DIRECT_TO_MAIN_REPOS\s*=\s*\[(.*?)\]', content, re.DOTALL)
if m:
    for entry in re.findall(r'\"([^\"]+)\"', m.group(1)):
        print(entry)
" 2>/dev/null || true
}

# Merge user customizations into the new hook file.
# Takes the new file path and injects DIRECT_TO_MAIN_REPOS entries.
apply_direct_to_main_repos() {
  local file="$1"
  shift
  local repos=("$@")

  if [ ${#repos[@]} -eq 0 ]; then
    return
  fi

  # Build the Python list entries
  local entries=""
  for repo in "${repos[@]}"; do
    entries="${entries}    \"${repo}\",\n"
  done

  # Replace the empty/placeholder DIRECT_TO_MAIN_REPOS block
  python3 -c "
import re
content = open('$file').read()
# Match the DIRECT_TO_MAIN_REPOS block (with optional comments inside)
pattern = r'(DIRECT_TO_MAIN_REPOS\s*=\s*\[)[^\]]*(\])'
replacement = r'\1\n${entries}\2'
content = re.sub(pattern, replacement, content, flags=re.DOTALL)
open('$file', 'w').write(content)
" 2>/dev/null
}

# Resolve a file conflict. Handles interactive review or auto-merge.
# For hooks: attempts smart merge of customizations.
# For other files: interactive diff review or auto-overwrite with backup.
# Returns 0 if file was updated, 1 if skipped.
resolve_conflict() {
  local label="$1"
  local src="$2"
  local dst="$3"
  local file_type="$4"  # "hook" or "file"

  if [ "$CONFLICT_MODE" = "interactive" ]; then
    echo ""
    echo -e "  ${YELLOW}CONFLICT: $label${NC}"
    echo "  Your existing file differs from the version being installed."
    echo ""

    # For hooks, detect and show customizations
    local custom_repos=()
    if [ "$file_type" = "hook" ] && [[ "$dst" == *"enforce-git-workflow.py" ]]; then
      while IFS= read -r repo; do
        [ -n "$repo" ] && custom_repos+=("$repo")
      done < <(extract_direct_to_main_repos "$dst")
      if [ ${#custom_repos[@]} -gt 0 ]; then
        echo -e "  ${CYAN}Detected your customizations:${NC}"
        echo "    DIRECT_TO_MAIN_REPOS:"
        for repo in "${custom_repos[@]}"; do
          echo "      - $repo"
        done
        echo ""
      fi
    fi

    echo "  Diff (your version vs new version):"
    echo ""
    diff --color=auto -u "$dst" "$src" | head -50 || true
    echo ""

    if [ ${#custom_repos[@]} -gt 0 ]; then
      echo "  Options:"
      echo "    m) Merge - install new version and preserve your customizations"
      echo "    o) Overwrite - install new version (discard customizations)"
      echo "    s) Skip - keep your existing version"
      echo ""
      read -r -p "  Choose [m/o/s] (default: m): " answer
      case "${answer,,}" in
        o)
          backup_file "$dst"
          cp "$src" "$dst"
          return 0
          ;;
        s) return 1 ;;
        *)
          # Merge: install new version, then re-apply customizations
          backup_file "$dst"
          cp "$src" "$dst"
          apply_direct_to_main_repos "$dst" "${custom_repos[@]}"
          return 0
          ;;
      esac
    else
      echo "  Options:"
      echo "    o) Overwrite - install new version (backup saved)"
      echo "    s) Skip - keep your existing version"
      echo ""
      read -r -p "  Choose [o/s] (default: o): " answer
      case "${answer,,}" in
        s) return 1 ;;
        *)
          backup_file "$dst"
          cp "$src" "$dst"
          return 0
          ;;
      esac
    fi

  else
    # Auto-resolve mode
    backup_file "$dst"

    # For hooks, try smart merge
    if [ "$file_type" = "hook" ] && [[ "$dst" == *"enforce-git-workflow.py" ]]; then
      local custom_repos=()
      while IFS= read -r repo; do
        [ -n "$repo" ] && custom_repos+=("$repo")
      done < <(extract_direct_to_main_repos "$dst")

      cp "$src" "$dst"

      if [ ${#custom_repos[@]} -gt 0 ]; then
        apply_direct_to_main_repos "$dst" "${custom_repos[@]}"
        log_info "Merged your DIRECT_TO_MAIN_REPOS entries: ${custom_repos[*]}"
      fi
    else
      cp "$src" "$dst"
    fi
    return 0
  fi
}

# ─── Install mode selection ──────────────────────────────────────────
choose_install_mode() {
  if [ -n "$INSTALL_MODE" ]; then
    return  # Already set via --global flag
  fi

  if $NON_INTERACTIVE; then
    INSTALL_MODE="project"
    return
  fi

  # Check if we're in a git repo
  if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    log_warn "Not in a git repository. Defaulting to global install."
    INSTALL_MODE="global"
    return
  fi

  echo -e "${BOLD}Installation Mode${NC}"
  echo "───────────────────────────────────────────"
  echo ""
  echo "  1) ${BOLD}Project-level${NC} (default) - Install to .claude/ in this repo"
  echo "     Git-tracked, travels with the repo, per-project config"
  echo ""
  echo "  2) ${BOLD}Global${NC} - Install to ~/.claude/"
  echo "     Works for all repos, single configuration"
  echo ""
  read -r -p "  Choose [1/2] (default: 1): " mode_choice
  case "$mode_choice" in
    2) INSTALL_MODE="global" ;;
    *) INSTALL_MODE="project" ;;
  esac
  echo ""
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

  if $DRY_RUN; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    echo ""
  fi
}

# ─── Ensure target directories exist ─────────────────────────────────
ensure_directories() {
  if [ ! -d "$CLAUDE_DIR" ]; then
    if $DRY_RUN; then
      log_info "Would create $CLAUDE_DIR"
    else
      mkdir -p "$CLAUDE_DIR"
      log_info "Created $CLAUDE_DIR"
    fi
  fi
}

# ─── Uninstall ────────────────────────────────────────────────────────
do_uninstall() {
  echo ""
  echo -e "${BOLD}Uninstalling Claude Code Git Flow${NC}"
  echo "═══════════════════════════════════════════"
  echo ""

  # Determine where to uninstall from
  if [ "$INSTALL_MODE" != "global" ]; then
    # Try project-level first, fall back to global
    if [ -d "$(pwd)/.claude/hooks" ] && [ -f "$(pwd)/.claude/hooks/enforce-git-workflow.py" ]; then
      CLAUDE_DIR="$(pwd)/.claude"
    else
      CLAUDE_DIR="$HOME/.claude"
    fi
  else
    CLAUDE_DIR="$HOME/.claude"
  fi

  local removed=()

  # Remove hook scripts
  for hook in enforce-git-workflow.py enforce-issue-workflow.py; do
    if [ -f "$CLAUDE_DIR/hooks/$hook" ]; then
      rm "$CLAUDE_DIR/hooks/$hook"
      removed+=("hooks/$hook")
    fi
  done

  # Remove commands
  for cmd in commit.md pr.md cpm.md gs.md sync.md new-issue.md; do
    if [ -f "$CLAUDE_DIR/commands/$cmd" ]; then
      rm "$CLAUDE_DIR/commands/$cmd"
      removed+=("commands/$cmd")
    fi
  done

  # Remove legacy protocols file (from older versions)
  if [ -f "$CLAUDE_DIR/github-repo-protocols.md" ]; then
    rm "$CLAUDE_DIR/github-repo-protocols.md"
    removed+=("github-repo-protocols.md (legacy)")
  fi

  # Remove custom branches config
  if [ -f "$CLAUDE_DIR/git-flow-protected-branches.json" ]; then
    rm "$CLAUDE_DIR/git-flow-protected-branches.json"
    removed+=("git-flow-protected-branches.json")
  fi

  # Note: We don't remove settings.json hooks entries automatically
  # because the user may have other hooks configured

  echo ""
  if [ ${#removed[@]} -gt 0 ]; then
    echo -e "${GREEN}Removed:${NC}"
    for item in "${removed[@]}"; do
      echo "  - $CLAUDE_DIR/$item"
    done
    echo ""
    log_warn "Hook entries in $CLAUDE_DIR/settings.json were NOT removed automatically."
    log_warn "Manually remove the UserPromptSubmit and PreToolUse entries for enforce-*-workflow.py"
  else
    log_info "Nothing to remove - git flow was not installed."
  fi
  echo ""
  exit 0
}

# ─── Configure protected branches ────────────────────────────────────
configure_protected_branches() {
  echo -e "${BOLD}1. Protected Branch Configuration${NC}"
  echo "───────────────────────────────────────────"
  echo ""
  echo "  The following branches are protected by default (commits and"
  echo "  pushes are blocked, forcing the feature-branch + PR workflow):"
  echo ""
  echo "    main, master, production, prod, staging, stag,"
  echo "    develop, dev, release, trunk"
  echo ""

  # Scan existing Claude configs for branch protection hints
  local detected_branches=()

  # Check CLAUDE.md for branch references (check both global and project)
  for claude_md in "$HOME/.claude/CLAUDE.md" "$(pwd)/CLAUDE.md" "$(pwd)/.claude/CLAUDE.md"; do
    if [ -f "$claude_md" ]; then
      local found
      found=$(grep -oiE '(deploy|push|merge)\s+(to|from|into)\s+["`'\'']*([a-zA-Z0-9._/-]+)["`'\'']*' "$claude_md" 2>/dev/null | \
        grep -oiE '[a-zA-Z0-9._/-]+$' | sort -u || true)
      if [ -n "$found" ]; then
        while IFS= read -r b; do
          local is_default=false
          for d in main master production prod staging stag develop dev release trunk; do
            if [ "${b,,}" = "$d" ]; then is_default=true; break; fi
          done
          if ! $is_default && [ -n "$b" ]; then
            local already=false
            for existing in "${detected_branches[@]+"${detected_branches[@]}"}"; do
              if [ "${existing,,}" = "${b,,}" ]; then already=true; break; fi
            done
            if ! $already; then
              detected_branches+=("$b")
            fi
          fi
        done <<< "$found"
      fi
    fi
  done

  # Check existing git-flow config for previously saved custom branches
  if [ -f "$CUSTOM_BRANCHES_FILE" ]; then
    local existing_custom
    existing_custom=$(jq -r '.[]' "$CUSTOM_BRANCHES_FILE" 2>/dev/null || true)
    if [ -n "$existing_custom" ]; then
      while IFS= read -r b; do
        local already=false
        for existing in "${detected_branches[@]+"${detected_branches[@]}"}"; do
          if [ "${existing,,}" = "${b,,}" ]; then already=true; break; fi
        done
        if ! $already && [ -n "$b" ]; then
          detected_branches+=("$b")
        fi
      done <<< "$existing_custom"
    fi
  fi

  # Report detected branches
  if [ ${#detected_branches[@]} -gt 0 ]; then
    echo -e "  ${CYAN}Detected from your existing Claude config:${NC}"
    for db in "${detected_branches[@]}"; do
      echo "    + $db"
    done
    echo ""
  fi

  # Ask user for additional branches
  if ! $DRY_RUN && ! $NON_INTERACTIVE; then
    echo "  Enter additional branch names to protect (comma-separated),"
    echo "  or press Enter to skip:"
    echo ""
    read -r -p "  Additional branches: " user_input

    local all_custom=("${detected_branches[@]+"${detected_branches[@]}"}")

    if [ -n "$user_input" ]; then
      IFS=',' read -ra user_branches <<< "$user_input"
      for ub in "${user_branches[@]}"; do
        ub=$(echo "$ub" | xargs)  # trim
        if [ -n "$ub" ]; then
          local is_default=false
          for d in main master production prod staging stag develop dev release trunk; do
            if [ "${ub,,}" = "$d" ]; then is_default=true; break; fi
          done
          if $is_default; then
            log_skip "'$ub' is already in the default protected list"
          else
            local already=false
            for existing in "${all_custom[@]+"${all_custom[@]}"}"; do
              if [ "${existing,,}" = "${ub,,}" ]; then already=true; break; fi
            done
            if ! $already; then
              all_custom+=("$ub")
            fi
          fi
        fi
      done
    fi

    # Write custom branches to config file
    if [ ${#all_custom[@]} -gt 0 ]; then
      printf '%s\n' "${all_custom[@]}" | jq -R . | jq -s . > "$CUSTOM_BRANCHES_FILE"
      CHANGES_MADE+=("git-flow-protected-branches.json - SAVED ${#all_custom[@]} custom branch(es): ${all_custom[*]}")
      echo ""
      log_success "Saved ${#all_custom[@]} custom protected branch(es): ${all_custom[*]}"
    else
      log_skip "No custom branches added (using defaults only)"
    fi
  elif $DRY_RUN; then
    if [ ${#detected_branches[@]} -gt 0 ]; then
      log_info "Would prompt to confirm detected branches: ${detected_branches[*]}"
    else
      log_info "Would prompt for additional protected branches"
    fi
  else
    # Non-interactive mode - save detected branches if any
    if [ ${#detected_branches[@]} -gt 0 ]; then
      printf '%s\n' "${detected_branches[@]}" | jq -R . | jq -s . > "$CUSTOM_BRANCHES_FILE"
      CHANGES_MADE+=("git-flow-protected-branches.json - AUTO-SAVED ${#detected_branches[@]} detected branch(es): ${detected_branches[*]}")
      log_success "Auto-saved ${#detected_branches[@]} detected protected branch(es): ${detected_branches[*]}"
    else
      log_skip "No custom branches detected (using defaults only)"
    fi
  fi
  echo ""
}

# ─── Install hooks ───────────────────────────────────────────────────
install_hooks() {
  echo -e "${BOLD}2. Hook Scripts${NC}"
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
          echo "    Action:   Would backup and resolve (merge customizations)"
        elif resolve_conflict "hooks/$hook" "$src" "$dst" "hook"; then
          chmod +x "$dst"
          CHANGES_MADE+=("hooks/$hook - RESOLVED (backup saved)")
          log_success "Resolved $hook (backup saved)"
        else
          SKIPPED+=("hooks/$hook - user chose to keep existing")
          log_skip "$hook kept as-is (user declined)"
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
  echo -e "${BOLD}3. Slash Commands${NC}"
  echo "───────────────────────────────────────────"

  mkdir -p "$COMMANDS_DIR"

  for cmd in commit.md pr.md cpm.md gs.md new-issue.md; do
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
          echo "    Action: Would backup and resolve"
        elif resolve_conflict "commands/$cmd (/$name)" "$src" "$dst" "file"; then
          CHANGES_MADE+=("commands/$cmd (/$name) - RESOLVED (backup saved)")
          log_success "Resolved /$name (backup saved)"
        else
          SKIPPED+=("commands/$cmd (/$name) - user chose to keep existing")
          log_skip "/$name kept as-is (user declined)"
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

# ─── Merge settings.json hooks ───────────────────────────────────────
install_settings_hooks() {
  echo -e "${BOLD}4. Settings.json Hook Configuration${NC}"
  echo "───────────────────────────────────────────"

  # Determine the hook command paths based on install mode
  local hook_prefix
  if [ "$INSTALL_MODE" = "global" ]; then
    hook_prefix="\$HOME/.claude"
  else
    hook_prefix=".claude"
  fi

  if [ ! -f "$SETTINGS_FILE" ]; then
    # No settings.json exists - create one with just hooks
    if $DRY_RUN; then
      log_info "Would create settings.json with hook configuration"
    else
      cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${hook_prefix}/hooks/enforce-issue-workflow.py",
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
            "command": "${hook_prefix}/hooks/enforce-git-workflow.py",
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
          local ups_command="python3 ${hook_prefix}/hooks/enforce-issue-workflow.py"
          if jq -e '.hooks.UserPromptSubmit' "$tmp_file" > /dev/null 2>&1; then
            jq --arg cmd "$ups_command" '.hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
          else
            jq --arg cmd "$ups_command" '.hooks.UserPromptSubmit = [{"hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
          fi
          CHANGES_MADE+=("settings.json - Added UserPromptSubmit hook")
          log_success "Added UserPromptSubmit hook (enforce-issue-workflow.py)"
        fi

        # Add PreToolUse if missing
        if ! $has_pre_tool; then
          local ptu_command="${hook_prefix}/hooks/enforce-git-workflow.py"
          if jq -e '.hooks.PreToolUse' "$tmp_file" > /dev/null 2>&1; then
            jq --arg cmd "$ptu_command" '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
          else
            jq --arg cmd "$ptu_command" '.hooks.PreToolUse = [{"matcher":"Bash","hooks":[{"type":"command","command":$cmd,"timeout":5000}]}]' "$tmp_file" > "${tmp_file}.new" && mv "${tmp_file}.new" "$tmp_file"
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

# ─── Set up coordination logs (project-level only) ──────────────────
setup_logs() {
  if [ "$INSTALL_MODE" = "global" ]; then
    log_skip "Logs directory is per-project only (skipped for global install)"
    echo ""
    return
  fi

  echo -e "${BOLD}5. Coordination Logs${NC}"
  echo "───────────────────────────────────────────"

  if [ -d "$LOGS_DIR" ]; then
    SKIPPED+=(".claude/logs/ - already exists")
    log_skip ".claude/logs/ already exists"
  else
    if $DRY_RUN; then
      log_info "Would create .claude/logs/ directory"
      log_info "Would copy learnings.md template"
    else
      mkdir -p "$LOGS_DIR"
      cp "$SCRIPT_DIR/templates/logs/learnings.md" "$LOGS_DIR/learnings.md"
      CHANGES_MADE+=(".claude/logs/ - CREATED with learnings.md template")
      log_success "Created .claude/logs/ with learnings.md template"
    fi
  fi

  # Add .claude/logs/ to .gitignore if not already there
  local gitignore="$(pwd)/.gitignore"
  if [ -f "$gitignore" ]; then
    if ! grep -q '\.claude/logs/' "$gitignore" 2>/dev/null; then
      if $DRY_RUN; then
        log_info "Would add .claude/logs/ tracking note"
      fi
    fi
  fi

  echo ""
}

# ─── Check CLAUDE.md ─────────────────────────────────────────────────
check_claude_md() {
  echo -e "${BOLD}6. CLAUDE.md Git Flow Sections${NC}"
  echo "───────────────────────────────────────────"

  # Determine which CLAUDE.md to check
  local claude_md
  if [ "$INSTALL_MODE" = "global" ]; then
    claude_md="$HOME/.claude/CLAUDE.md"
  else
    # Check project-level first, then repo root
    if [ -f "$(pwd)/.claude/CLAUDE.md" ]; then
      claude_md="$(pwd)/.claude/CLAUDE.md"
    elif [ -f "$(pwd)/CLAUDE.md" ]; then
      claude_md="$(pwd)/CLAUDE.md"
    else
      claude_md=""
    fi
  fi

  if [ -z "$claude_md" ] || [ ! -f "$claude_md" ]; then
    if $DRY_RUN; then
      log_info "No CLAUDE.md found."
      log_info "Would note: You should add the git flow sections from the README."
    else
      log_warn "No CLAUDE.md found."
      log_warn "Add the 'Copy to Your CLAUDE.md' block from the README."
    fi
  else
    # Check if key sections already exist
    local has_commit_format
    has_commit_format=$(grep -c '#.*: description' "$claude_md" 2>/dev/null || true)
    local has_branch_workflow
    has_branch_workflow=$(grep -c 'feature.branch\|issue.*branch\|branch.*issue' "$claude_md" 2>/dev/null || true)

    if [ "$has_commit_format" -gt 0 ] && [ "$has_branch_workflow" -gt 0 ]; then
      log_skip "CLAUDE.md appears to have git flow sections already"
    else
      log_warn "CLAUDE.md may be missing git flow sections."
      log_warn "Add the 'Copy to Your CLAUDE.md' block from the README."
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

  echo -e "  Install mode: ${BOLD}${INSTALL_MODE}${NC} ($CLAUDE_DIR)"
  echo ""

  if [ ${#CHANGES_MADE[@]} -gt 0 ]; then
    echo -e "${GREEN}Changes Made:${NC}"
    for change in "${CHANGES_MADE[@]}"; do
      echo "  + $change"
    done
    echo ""
  fi

  if [ ${#CONFLICTS[@]} -gt 0 ]; then
    if $DRY_RUN; then
      echo -e "${YELLOW}Conflicts Detected (would be resolved during install):${NC}"
    else
      echo -e "${YELLOW}Conflicts Resolved:${NC}"
    fi
    for conflict in "${CONFLICTS[@]}"; do
      echo "  ! $conflict"
    done
    echo ""
    if ! $DRY_RUN && [ -d "$BACKUP_DIR" ]; then
      echo "  Original versions saved to: $BACKUP_DIR"
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
    echo "  /commit     Stage + commit (format: #42: description)"
    echo "  /pr         Push + create PR that closes the issue"
    echo "  /cpm        One-shot: commit + PR + merge + cleanup"
    echo ""
    echo "───────────────────────────────────────────"
    echo -e "${BOLD}Workflow:${NC}"
    echo ""
    echo "  1. /new-issue  (or gh issue create)"
    echo "  2. git checkout -b {issue#}-{description} origin/main"
    echo "  3. Make changes"
    echo "  4. /cpm  (or /commit then /pr then merge)"
    echo ""
    echo "  The hooks will block you if you try to:"
    echo "    - Commit on a protected branch"
    echo "    - Commit without #issue_number: prefix"
    echo "    - Push directly to a protected branch"
    echo ""
    echo "  Protected branches: main, master, production, prod, staging,"
    echo "  stag, develop, dev, release, trunk (+ any custom branches)"
    echo ""
  fi

  if [ ${#CHANGES_MADE[@]} -eq 0 ] && [ ${#CONFLICTS[@]} -eq 0 ]; then
    echo -e "${GREEN}Everything is already installed! No changes needed.${NC}"
    echo ""
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────
main() {
  preflight

  if $UNINSTALL; then
    choose_install_mode
    set_paths
    do_uninstall
    exit 0
  fi

  choose_install_mode
  set_paths
  ensure_directories
  choose_conflict_mode
  configure_protected_branches
  install_hooks
  install_commands
  install_settings_hooks
  setup_logs
  check_claude_md
  print_report
}

main
