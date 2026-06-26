---
name: advanced-find-unassigned
description: Performs an advanced, deep triage of unassigned Pull Requests. Evaluates PRs for WIP status, Jira links, external/bot contributors, and cross-references them against the PR Scrub Google Doc.
---

# Advanced Find Unassigned Pull Requests

This skill performs a deeply analytical triage of open, unassigned pull requests across core and shared repositories. It runs a highly optimized Python script that evaluates PRs and groups them intelligently to help the team focus on what actually needs assignment.

## Workflow

1.  **Run the Advanced Triage Script**:
    Run the bundled Python script to fetch the latest PRs and cross-reference them against the live PR Scrub Google Doc:
    ```bash
    python3 scripts/find_unassigned.py
    ```

2.  **Display the Report**:
    The script generates a Markdown report saved to `advanced_triage_report.md` in the skill's root directory, and prints the same report directly to standard output. 
    Present this report directly to the user.

## Deep Triage Logic

The script dynamically performs the following evaluations on every unassigned PR:
*   **WIP/Draft Analysis**: Determines if a PR is genuinely ready for review or if it lacks the proper `do-not-merge/work-in-progress` label despite having "WIP" in its title.
*   **PR Scrub Cross-Referencing**: Uses the Google Workspace CLI to fetch the team's PR Scrub Google Doc and checks if the PR has already been mentioned/logged there.
*   **Contributor Classification**: Intelligently groups PRs by author type:
    *   **Team**: Core team members.
    *   **External**: Community or cross-team contributors.
    *   **Bots**: Automated PRs (e.g., Konflux, Dependabot).
    *   **Sustaining**: `ocp-sustaining-admins`.
*   **Jira/Tracking Validation**: Scans titles and labels to ensure the PR is properly linked to an approved Epic, RFE, or Bug.
*   **Description Quality**: Performs a heuristic check on the PR body length to flag empty or overly sparse descriptions.
