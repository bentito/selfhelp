---
name: assure-assigned
description: Synchronizes PR reviewer assignments from the bug scrub Google Doc to GitHub. Use when you need to ensure that the reviewers listed in the meeting notes are officially assigned to the corresponding PRs.
---

# Assure Assigned

This skill automates the synchronization of PR reviewer assignments from the team's bug scrub meeting notes to GitHub.

## Workflow

1.  **Read Name Mapping**:
    *   Read the team configuration directly from `~/.gemini/skills/team-report/config.json` using `run_shell_command` (`cat ~/.gemini/skills/team-report/config.json`).
    *   This file provides the mapping between human names and GitHub usernames.

2.  **Access Meeting Notes**:
    *   Export the content of the Bug Scrub Google Doc to an HTML file to preserve hyperlinks:
        ```bash
        gws drive files export --params '{"fileId": "178UlalXBSyrxViOzZUSqm9MHgjlcdY3W6ecIsA7yuC8", "mimeType": "text/html"}' -o /tmp/bug-scrub.html
        ```

3.  **Extract PR Assignments**:
    *   Use the bundled Python script to find the most recent date heading and extract the PR links and reviewers:
        ```bash
        python3 scripts/parse_table.py /tmp/bug-scrub.html
        ```
    *   This script will return a JSON object containing the date found and a list of `prs` (each with a `url` and a `reviewers` string).

4.  **Sync to GitHub**:
    *   For each PR returned in the JSON array:
        1.  Parse the repository `owner`, `repo` name, and `issue_number` from the GitHub URL.
        2.  Map the reviewer name(s) to GitHub username(s) using the `config.json` data. Make sure to handle multiple names in a single string (e.g., "Davide, Joao" or "Brett Tofel Davide Salerno").
        3.  Use the `mcp_github_issue_write` tool with `method: "update"` and the PR number as `issue_number` to set the `assignees` field.

## Implementation Details

*   **Config Source**: Always use `~/.gemini/skills/team-report/config.json` as the source of truth for mappings.
*   **Name Matching**: Matches should be case-insensitive and support both full names and common first names as defined in the config.
*   **Multiple Reviewers**: The parsing script might return multiple names separated by commas or spaces. Use regex or string splitting to separate and match them against the config.
*   **Dry Runs**: Always perform a dry run (listing the planned GitHub tool calls) when the user asks for one, rather than executing them.