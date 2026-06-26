---
name: find-unassigned
description: Find all unassigned Pull Requests across Network Edge team repositories. Use when the user wants to identify unassigned PRs in core or shared repositories, check on untriaged team contributions, or do a daily unassigned PR scrub.
---

# Find Unassigned Pull Requests

This skill automates the discovery of open, unassigned pull requests across core and shared repositories for the Network Edge team. It runs a optimized, rate-limit-friendly workflow to scan Category 1 (Core) and Category 2 (Shared) repositories using GitHub queries.

## Workflow

1.  **Run the Report Script**:
    Run the bundled Python script directly in the skill directory to perform the search safely with politeness delays and exponential rate-limit backoffs:
    ```bash
    python3 scripts/find_unassigned.py
    ```

2.  **Display the Report**:
    The script generates a Markdown report saved to `unassigned_report.md` in the skill's root directory, and prints the same report directly to standard output. 
    Present this report directly to the user.

## Repository Categorization Logic

The skill uses two local artifacts to perform its logic:
- `references/team-repo-list.json`: Lists the core (Category 1) and shared (Category 2) repositories.
- `references/owners.json`: Lists the team members (from the `cluster-ingress-operator` OWNERS file).

### Category 1 (Core Repositories)
*   **Logic**: Scans for **all** open, unassigned pull requests, regardless of who authored them.
*   **Purpose**: Ensures that no incoming community or team contributions to core components are left untriaged or unassigned.

### Category 2 (Shared Repositories)
*   **Logic**: Scans for open, unassigned pull requests **authored specifically by team members**.
*   **Purpose**: Tracks active team contributions in shared monorepos and platform integration repositories (e.g., `openshift/release`, `openshift/api`, `openshift/origin`) that need review assignment.
*   **Optimization**: Searches are executed by-author (globally) and filtered in-memory rather than querying each massive repository individually. This prevents hitting secondary GitHub rate limits.
