# /cpm — Commit, PR, Merge

One-shot workflow: commit all changes, create a PR, merge it, close the issue, and rebase on main.

## Usage

```
/cpm
```

No arguments needed. Derives the issue number from the current branch name (expects `{issue-number}-{description}` format).

## Instructions

Execute the following steps sequentially. Do NOT skip steps or proceed if a step fails.

### Phase 1: Pre-flight

1. Run `git status` to confirm there are changes to commit.
2. Run `git diff --stat` to see what changed.
3. Extract the issue number from the current branch name (the leading digits before the first `-`).
4. Run `git log --oneline -5` to check recent commit style.

If there are no changes and no unpushed commits, stop and report "Nothing to commit or push."

### Phase 2: Commit

1. Stage all changed files with `git add` (prefer specific files over `git add -A`; never stage `.env` or credential files).
2. Create a commit with message format: `{issue-number}: {concise description of changes}`
3. Do NOT add any Co-Authored-By trailers or AI attribution.

### Phase 3: Push & Create PR

1. Push the branch: `git push -u origin HEAD`
2. Check for a PR template at `.github/PULL_REQUEST_TEMPLATE.md` or `pull_request_template.md` in the repo root.
3. Create the PR using `gh pr create`:
   - Title: `{issue-number}: {concise description}`
   - Body: Use the PR template if found, otherwise use Summary + Test Plan format
   - Include `Closes #{issue-number}` in the body
4. Capture the PR URL.

### Phase 4: Merge

1. Merge the PR: `gh pr merge --squash --delete-branch`
2. Confirm the merge succeeded.

### Phase 5: Close Issue

1. The issue should auto-close from "Closes #N" in the PR body.
2. Verify with `gh issue view {issue-number} --json state`.
3. If still open, close it manually: `gh issue close {issue-number}`

### Phase 6: Rebase on Main

1. `git checkout main`
2. `git fetch origin`
3. `git reset --hard origin/main` (if blocked by hooks, use `git pull origin main` instead)
4. Confirm clean state with `git status`.

### Phase 7: Report

Output a summary in this format:

```
## Completed

- **Issue**: #{issue-number} — {issue title}
- **PR**: {PR URL} (merged)
- **Commit**: {short SHA} — {commit message}
- **Branch**: Deleted `{branch-name}`, now on `main`
- **Status**: Clean, up to date with origin/main
```

## Error Handling

- If `gh pr merge` fails (e.g., checks pending), report the failure and the PR URL. Do not force merge.
- If `git reset --hard` is blocked, fall back to `git pull origin main`.
- If any step fails, stop and report what succeeded and what failed.
