---
name: gh-cli-expert
description: Expert guidance for the `gh` (GitHub) CLI tool. Use this to perform GitHub operations (PR creation, issue management, code reviews) efficiently without triggering interactive prompts or wasting time on subcommand discovery.
---

# GitHub CLI (gh) Expert

Use the `gh` CLI tool for GitHub operations (PRs, issues, repo management). To use `gh` successfully in a non-interactive agent environment, you **must** provide the necessary flags to bypass interactive prompts.

## Core Commands & Non-Interactive Flags

### Pull Requests (`gh pr`)

- **Create PR:** You must provide `--title` and `--body`, or use `--fill` to auto-fill from commits.
  - *Example (explicit):* `gh pr create --title "Fix login bug" --body "Detailed description..."`
  - *Example (auto-fill):* `gh pr create --fill`
  - *Draft PR:* Add the `--draft` flag.
  - *Specify Base:* `gh pr create --base main --fill`
- **Review PR:**
  - *Approve:* `gh pr review <number> --approve -b "Looks good!"`
  - *Request Changes:* `gh pr review <number> --request-changes -b "Please fix X."`
  - *Comment:* `gh pr review <number> --comment -b "Just a note..."`
- **Merge PR:** Use `--auto`, `--squash`, `--merge`, or `--rebase`.
  - *Example:* `gh pr merge <number> --squash`
- **List PRs:** `gh pr list --state open --author "@me"`
- **View PR Details/Diff:** `gh pr view <number>` or `gh pr diff <number>`

### Issues (`gh issue`)

- **Create Issue:** Must provide `--title` and `--body`.
  - *Example:* `gh issue create --title "Bug: Crash on load" --body "Steps to reproduce..."`
  - *Add Label/Assignee:* `gh issue create --title "..." --body "..." --label bug --assignee "@me"`
- **List Issues:** `gh issue list --state open`
- **Comment on Issue:** `gh issue comment <number> --body "My comment text"`
- **Close Issue:** `gh issue close <number>`

### General Best Practices

- **Avoid Interactive Prompts:** If a `gh` command hangs, it is likely waiting for user input. Always use `--title`, `--body`, or `-b`/`-F` flags for text inputs. 
- **Piping Body Text:** You can pipe text into commands using `-F -` (File: Standard Input).
  - *Example:* `echo "My long body text" | gh issue create --title "Summary" -F -`
- **Cross-Repo Operations:** Use `-R <owner>/<repo>` if you are executing a command outside of the repository's local checkout directory.
- **JSON Output:** For programmatic parsing, many commands support `--json <fields>` (e.g., `gh pr list --json number,title,url`).

## Discovery Prevention
Do not run `gh --help` or `gh <command> --help` unless a specific flag is unknown. Use the patterns above as the primary source of truth.
