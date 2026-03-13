#!/usr/bin/env python3
"""
PreToolUse:Bash hook to enforce GitHub Issues workflow.

BLOCKS:
1. Commits on main branch (must use feature branch)
2. Commit messages without issue number prefix (^\d+:)
3. Direct pushes to main branch (must use PR workflow)

ESCAPE HATCHES:
- ALLOW_MAIN_COMMIT=1 env var for emergencies
- Merge commits and --amend without -m skip validation
- Not in a git repo → allow all
"""

import json
import os
import re
import subprocess
import sys

# Repos that use direct-to-main workflow (no feature branches, no issue numbers).
# Matched against the git remote URL — any repo whose origin contains one of these
# strings will skip all main-branch and commit-message checks.
# Add repos that use direct-to-main workflow (no feature branches, no issue numbers).
# Matched against the git remote URL. Example: "yourorg/your-dotfiles-repo"
DIRECT_TO_MAIN_REPOS = [
    # "youruser/your-dotfiles",
]


def is_direct_to_main_repo():
    """Check if the current repo is allowlisted for direct-to-main workflow."""
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=2,
        )
        if result.returncode == 0:
            remote = result.stdout.strip()
            return any(repo in remote for repo in DIRECT_TO_MAIN_REPOS)
    except Exception:
        pass
    return False


def get_current_branch():
    """Get current git branch. Returns None if not in a git repo."""
    try:
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except Exception:
        return None


def extract_commit_message(command):
    """Extract commit message from git commit -m '...' or --message '...'."""
    # Heredoc patterns (e.g. -m "$(cat <<'EOF' ... EOF)") can't be reliably
    # parsed from the raw command string — skip validation and let git handle it.
    # This check MUST come before the regex patterns, which would otherwise
    # match the outer quotes and capture the raw heredoc syntax as the "message".
    if "-m" in command and "<<" in command:
        return None

    # Try quoted patterns first (single or double quotes)
    patterns = [
        r"""-m\s+"([^"]+)" """,
        r"""-m\s+'([^']+)' """,
        r'''--message\s+"([^"]+)"''',
        r"""--message\s+'([^']+)'""",
        # Unquoted (grab until next flag or end)
        r"""-m\s+(\S+)""",
    ]
    # Append a space to command to make patterns match at end of string
    cmd = command + " "
    for pattern in patterns:
        match = re.search(pattern, cmd)
        if match:
            return match.group(1)

    return None


def is_commit_command(command):
    """Check if this is a git commit command."""
    # Match: git commit, git commit -m, git commit --amend, etc.
    # But NOT: git commit-graph, git commit-tree
    return bool(re.match(r"git\s+commit(\s|$)", command))


def is_push_command(command):
    """Check if this is a git push command."""
    return bool(re.match(r"(SKIP_CHECKS=\S+\s+)?git\s+push(\s|$)", command))


def is_merge_commit(command):
    """Check if this is a merge commit (auto-generated message)."""
    return "Merge branch" in command or "Merge pull request" in command


def is_amend_without_message(command):
    """Check if this is --amend that preserves existing message."""
    return "--amend" in command and "-m" not in command and "--message" not in command


def validate_commit_message_format(message):
    """Check if commit message starts with issue number: '123: description'."""
    if not message:
        return True  # No message to validate (e.g., heredoc), skip
    return bool(re.match(r"^\d+:", message))


def deny(reason):
    """Return a deny decision."""
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }
    print(json.dumps(output))
    sys.exit(0)


def check_commit(command, branch):
    """Validate git commit commands against workflow rules."""
    # Direct-to-main repos skip all checks
    if is_direct_to_main_repo():
        return

    # Emergency bypass
    if os.environ.get("ALLOW_MAIN_COMMIT") == "1":
        return

    # Rule 1: No commits on main
    if branch == "main":
        deny(
            "Cannot commit on main branch. Create a feature branch first:\n"
            "  1. gh issue create  (if no issue exists)\n"
            "  2. git checkout -b {issue-number}-{description}\n"
            "  3. Then commit\n\n"
            "Emergency bypass: ALLOW_MAIN_COMMIT=1 git commit ..."
        )

    # Skip message validation for merge commits and amends without new message
    if is_merge_commit(command) or is_amend_without_message(command):
        return

    # Rule 2: Commit message must have issue number prefix
    message = extract_commit_message(command)
    if message and not validate_commit_message_format(message):
        deny(
            f'Commit message must start with issue number.\n'
            f'  Required format: "{{issue_number}}: {{description}}"\n'
            f'  Example: "123: Fix the login bug"\n'
            f'  Your message: "{message}"'
        )


def check_push(command, branch):
    """Validate git push commands against workflow rules."""
    # Direct-to-main repos skip all checks
    if is_direct_to_main_repo():
        return

    # Emergency bypass
    if os.environ.get("ALLOW_MAIN_COMMIT") == "1":
        return

    # Only block pushes when on main
    if branch != "main":
        return

    # Parse what's being pushed to determine if it's actually pushing main
    # Allow: git push origin feature-branch (explicitly pushing a different branch)
    parts = command.split()

    # Find the refspec (what's being pushed)
    # git push origin branch-name → pushing branch-name
    # git push -u origin HEAD → pushing current branch (main)
    # git push → pushing current branch (main)
    push_target = None
    skip_next = False
    found_remote = False

    for i, part in enumerate(parts):
        if skip_next:
            skip_next = False
            continue
        if part in ("-u", "--set-upstream", "--force", "-f", "--no-verify",
                     "--force-with-lease", "--delete", "-d"):
            if part in ("-u", "--set-upstream"):
                skip_next = False  # -u takes no argument by itself
            continue
        if part.startswith("-"):
            continue
        if part in ("git", "push"):
            continue
        # Skip env var prefix like SKIP_CHECKS=1
        if "=" in part:
            continue
        if not found_remote:
            found_remote = True  # First non-flag arg is the remote
            continue
        # Second non-flag arg is the refspec
        push_target = part
        break

    # HEAD means current branch (main), explicit branch name could differ
    if push_target == "HEAD" or push_target == "main":
        push_target = "main"
    elif push_target is None:
        # No explicit target → defaults to current branch (main)
        push_target = "main"
    elif push_target != "main":
        return  # Pushing a specific non-main branch, allow

    deny(
        "Cannot push to main. Use the feature branch + PR workflow:\n"
        "  1. git checkout -b {issue-number}-{description}\n"
        "  2. Make changes and commit\n"
        "  3. git push -u origin HEAD\n"
        "  4. gh pr create\n"
        "  5. gh pr merge --squash --delete-branch\n\n"
        "Emergency bypass: ALLOW_MAIN_COMMIT=1 git push ..."
    )


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    if tool_name != "Bash":
        sys.exit(0)

    command = tool_input.get("command", "").strip()
    if not command:
        sys.exit(0)

    # Only check git commit and git push commands
    if not (is_commit_command(command) or is_push_command(command)):
        sys.exit(0)

    # Get current branch (None if not in git repo)
    branch = get_current_branch()
    if not branch:
        sys.exit(0)  # Not in git repo, allow

    if is_commit_command(command):
        check_commit(command, branch)
    elif is_push_command(command):
        check_push(command, branch)

    # No deny → exit silently, let other hooks handle allow/deny
    sys.exit(0)


if __name__ == "__main__":
    main()
