---
name: jira-cli-expert
description: Expert guidance for the `jira` CLI tool (ankitpokhrel/jira-cli). Use this to perform Jira operations (issue creation, movement, commenting, sprint management) efficiently without manual subcommand discovery.
---

# Jira CLI Expert

Use the `jira` CLI tool for all Jira write operations (create, move, comment, sprint management). Favor this tool over MCP tools for mutations as per global project memory.

## Core Commands

### Issues
- **List:** `jira issue list -q "assignee = currentUser()"` (use JQL in `-q`)
- **View:** `jira issue view <KEY>` (Note: uses `--raw` for JSON, **not** `--json`)
- **Create:** `jira issue create -t<TYPE> -s"<SUMMARY>" -b"<BODY>" --no-input`
  - *Example:* `jira issue create -tBug -s"Fix login" -b"Steps to reproduce..." --no-input`
- **Move/Transition:** `jira issue move <KEY> "<STATE>"`
  - *Example:* `jira issue move ISSUE-123 "In Progress"`
- **Comment:** `jira issue comment add <KEY> "<TEXT>"`
- **Assign:** `jira issue assign <KEY> <USER>`
- **Link:** `jira issue link <ISSUE-1> <ISSUE-2> <TYPE>`

### Sprints
- **List:** `jira sprint list --board <BOARD-ID>`
- **Add to Sprint:** `jira sprint add <SPRINT-ID> <ISSUE-KEY>`

### Epics
- **List Epics:** `jira epic list`
- **Create Epic:** `jira epic create -s"<SUMMARY>" -b"<BODY>"`

## Best Practices
- **Non-Interactive:** Always use `--no-input` when creating issues to avoid prompts.
- **Project Context:** The CLI usually defaults to a project from config, but you can override with `-p <PROJECT-KEY>`.
- **JSON Output:** Use `--raw` for machine-readable output if you need to parse the results programmatically. **WARNING: The `--json` flag does NOT exist and will cause an error.**
- **Pagination & Limits:** The `--limit` flag does NOT exist. Use `--paginate <limit>` or `--paginate <offset>:<limit>` (e.g., `--paginate 50` or `--paginate 0:100`) to control the number of results returned. Max 100 per page.
- **Piping:** You can pipe descriptions: `echo "My body" | jira issue create -s"Summary" -tTask`.

## Discovery Prevention
Do not run `jira --help` or `jira <command> --help` unless a specific flag is unknown. Use the patterns above as the primary source of truth.
