#!/usr/bin/env python3
"""
UserPromptSubmit hook to enforce issue-first workflow.

This hook detects work requests and injects a reminder into Claude's context
to ensure the issue-first workflow is followed before making changes.
"""

import json
import os
import sys
import re


WORKFLOW_FILE = os.path.expanduser("~/.claude/github-repo-protocols.md")


def is_workflow_enabled() -> bool:
    """Check if the GitHub Issues workflow file is symlinked/present."""
    return os.path.isfile(WORKFLOW_FILE)


def is_work_request(prompt: str) -> bool:
    """Detect if the prompt is a work request vs a question or research task."""
    prompt_lower = prompt.lower()

    # Work action verbs that indicate implementation tasks
    work_patterns = [
        r"\b(update|fix|add|create|implement|build|change|modify|refactor)\b",
        r"\b(write|make|set up|setup|configure|migrate|convert|move)\b",
        r"\b(delete|remove|rename|replace|upgrade|downgrade)\b",
        r"\b(enable|disable|install|uninstall)\b",
    ]

    # Patterns that indicate it's NOT a work request (questions, research)
    question_patterns = [
        r"^(what|why|how|where|when|which|who|can you explain|tell me)\b",
        r"\?$",  # Ends with question mark
        r"\b(explain|describe|show me|list|find|search|look for|check)\b",
    ]

    # Check if it looks like a question first
    for pattern in question_patterns:
        if re.search(pattern, prompt_lower):
            return False

    # Check if it matches work patterns
    for pattern in work_patterns:
        if re.search(pattern, prompt_lower):
            return True

    return False


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)  # Silent failure, don't block

    prompt = input_data.get("prompt", "")

    if not is_workflow_enabled():
        sys.exit(0)  # Workflow not enabled, skip reminder

    if is_work_request(prompt):
        reminder = """
<workflow-reminder>
STOP - Before making ANY code or file changes, you MUST:

1. CHECK: Does a GitHub issue exist for this work?
   - If NO: Create one first with `gh issue create`
   - If YES: Note the issue number

2. CREATE BRANCH: `git checkout -b {issue-number}-{description}`

3. IMPLEMENT: Make your changes

4. COMMIT & PR:
   - `git commit -m "{issue-number}: {description}"`
   - `gh pr create --title "{issue-number}: ..." --body "Closes #{issue-number}"`

This applies to ALL changes including documentation, config, and "trivial" fixes.
Do NOT skip this workflow. The user has explicitly requested strict adherence.
</workflow-reminder>
"""
        print(reminder)

    sys.exit(0)


if __name__ == "__main__":
    main()
