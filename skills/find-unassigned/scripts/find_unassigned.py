import json
import subprocess
import os
import sys
import time

def load_json(filepath):
    try:
        with open(filepath, "r") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading {filepath}: {e}", file=sys.stderr)
        sys.exit(1)

def run_gh_search(query_args):
    cmd = ["gh", "search", "prs"] + query_args
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            if "rate limit" in result.stderr.lower() or "403" in result.stderr:
                # Secondary rate limit or rate limit hit, sleep and try once more
                print("Rate limit hit. Sleeping for 15 seconds...", file=sys.stderr)
                time.sleep(15)
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode != 0:
                    print(f"Error executing gh command: {result.stderr.strip()}", file=sys.stderr)
                    return []
            else:
                print(f"Error executing gh command: {result.stderr.strip()}", file=sys.stderr)
                return []
        if result.stdout:
            return json.loads(result.stdout)
    except Exception as e:
        print(f"Exception executing gh command: {e}", file=sys.stderr)
    return []

def is_wip_pr(pr):
    # Check if PR has "do-not-merge/work-in-progress" label
    labels = pr.get("labels", [])
    for label in labels:
        name = label.get("name", "").lower()
        if name == "do-not-merge/work-in-progress":
            return True
    return False

def main():
    # Paths to configuration files
    script_dir = os.path.dirname(os.path.abspath(__file__))
    skill_dir = os.path.dirname(script_dir)
    
    repo_list_path = os.path.join(skill_dir, "references", "team-repo-list.json")
    owners_path = os.path.join(skill_dir, "references", "owners.json")
    
    repo_config = load_json(repo_list_path)
    owners_config = load_json(owners_path)
    
    cat1_repos = repo_config.get("category_1_core", [])
    cat2_repos = repo_config.get("category_2_shared", [])
    team_members = [m["github"] for m in owners_config.get("team_members", [])]
    
    # Clean up team members lower
    team_members_lower = [t.lower() for t in team_members if t]
    
    unassigned_cat1_team = []
    unassigned_cat1_external = []
    unassigned_cat2 = []
    
    # Track unique PR URLs to avoid duplicates
    seen_pr_urls = set()
    
    print("Searching Category 1 (NE Owned) repositories for all unassigned PRs (excluding WIP label)...", flush=True)
    for repo in cat1_repos:
        print(f" - {repo}...", flush=True)
        # Search unassigned PRs in NE Owned repos with author, repository and labels information
        args = ["--repo", repo, "--state", "open", "no:assignee", "--json", "number,title,url,updatedAt,repository,author,labels", "--limit", "50", "--", "-label:do-not-merge/work-in-progress"]
        prs = run_gh_search(args)
        for pr in prs:
            if pr["url"] in seen_pr_urls:
                continue
            
            # Filter out WIP labeled PRs
            if is_wip_pr(pr):
                continue
                
            seen_pr_urls.add(pr["url"])
            
            author_login = pr.get("author", {}).get("login", "Unknown") if pr.get("author") else "Unknown"
            pr["author_login"] = author_login
            pr["category"] = "Category 1 (NE Owned)"
            
            if author_login.lower() in team_members_lower:
                unassigned_cat1_team.append(pr)
            else:
                unassigned_cat1_external.append(pr)
                
        # Politeness delay to avoid hitting secondary rate limits
        time.sleep(1.5)
        
    print("\nSearching Category 2 (Shared) repositories for unassigned PRs authored by team members (excluding WIP label)...", flush=True)
    for author in team_members:
        print(f" - Author: {author}...", flush=True)
        # Search unassigned PRs authored by team members globally
        args = ["--state", "open", f"author:{author}", "no:assignee", "--json", "number,title,url,updatedAt,repository,author,labels", "--limit", "50", "--", "-label:do-not-merge/work-in-progress"]
        prs = run_gh_search(args)
        for pr in prs:
            # Filter out WIP labeled PRs
            if is_wip_pr(pr):
                continue
                
            repo_name = pr.get("repository", {}).get("nameWithOwner")
            author_login = pr.get("author", {}).get("login", author) if pr.get("author") else author
            pr["author_login"] = author_login
            
            if repo_name in cat2_repos:
                if pr["url"] in seen_pr_urls:
                    continue
                seen_pr_urls.add(pr["url"])
                pr["category"] = "Category 2 (Shared)"
                unassigned_cat2.append(pr)
            elif repo_name in cat1_repos:
                # If we find an unassigned NE Owned PR during author search, ensure it gets filed under Category 1 NE Owned Team
                if pr["url"] not in seen_pr_urls:
                    seen_pr_urls.add(pr["url"])
                    pr["category"] = "Category 1 (NE Owned)"
                    unassigned_cat1_team.append(pr)
                    
        # Politeness delay to avoid hitting secondary rate limits
        time.sleep(1.5)
        
    # Sort all lists by updatedAt descending (newest first)
    unassigned_cat1_team.sort(key=lambda x: x.get("updatedAt", ""), reverse=True)
    unassigned_cat1_external.sort(key=lambda x: x.get("updatedAt", ""), reverse=True)
    unassigned_cat2.sort(key=lambda x: x.get("updatedAt", ""), reverse=True)
    
    # Generate Output Report
    report = []
    report.append("# Unassigned Pull Requests Report")
    report.append(f"Generated on: {time.strftime('%Y-%m-%d %H:%M:%S')} (WIP Labeled Excluded)\n")
    
    report.append("## 🔴 NE Owned Repositories (Category 1) — Unassigned PRs")
    report.append("These are open, unassigned pull requests in the NE Owned Network Edge repositories, split by Team and External authors.\n")
    
    # Subsection 1: Team-Authored NE Owned PRs
    report.append("### 👥 Team-Authored NE Owned PRs")
    report.append("Open unassigned NE Owned PRs authored by team members:\n")
    if unassigned_cat1_team:
        report.append("| Repository | PR | Author | Title | Updated | Link |")
        report.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
        for pr in unassigned_cat1_team:
            repo = pr["repository"]["nameWithOwner"]
            num = pr["number"]
            author = pr["author_login"]
            title = pr["title"]
            updated = pr["updatedAt"][:10]  # YYYY-MM-DD
            url = pr["url"]
            short_title = title[:80] + "..." if len(title) > 83 else title
            short_title = short_title.replace("|", "\\|")
            report.append(f"| {repo} | #{num} | {author} | {short_title} | {updated} | [View]({url}) |")
    else:
        report.append("No unassigned team-authored PRs found in Category 1 repositories.")
        
    report.append("\n")
    
    # Subsection 2: Non-Team/External NE Owned PRs
    report.append("### 🌐 External/Community-Authored NE Owned PRs")
    report.append("Open unassigned NE Owned PRs authored by external developers or automated bots:\n")
    if unassigned_cat1_external:
        report.append("| Repository | PR | Author | Title | Updated | Link |")
        report.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
        for pr in unassigned_cat1_external:
            repo = pr["repository"]["nameWithOwner"]
            num = pr["number"]
            author = pr["author_login"]
            title = pr["title"]
            updated = pr["updatedAt"][:10]  # YYYY-MM-DD
            url = pr["url"]
            short_title = title[:80] + "..." if len(title) > 83 else title
            short_title = short_title.replace("|", "\\|")
            report.append(f"| {repo} | #{num} | {author} | {short_title} | {updated} | [View]({url}) |")
    else:
        report.append("No unassigned external-authored PRs found in Category 1 repositories.")
        
    report.append("\n" + "---" + "\n")
    
    report.append("## 🟠 Shared Repositories (Category 2) — Unassigned Team PRs")
    report.append("These are open, unassigned pull requests in shared/integration repositories authored by team members.\n")
    
    if unassigned_cat2:
        report.append("| Repository | PR | Author | Title | Updated | Link |")
        report.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
        for pr in unassigned_cat2:
            repo = pr["repository"]["nameWithOwner"]
            num = pr["number"]
            author = pr["author_login"]
            title = pr["title"]
            updated = pr["updatedAt"][:10]  # YYYY-MM-DD
            url = pr["url"]
            short_title = title[:80] + "..." if len(title) > 83 else title
            short_title = short_title.replace("|", "\\|")
            report.append(f"| {repo} | #{num} | {author} | {short_title} | {updated} | [View]({url}) |")
    else:
        report.append("No unassigned team PRs found in Category 2 repositories.")
        
    # Write report to global skill directory
    global_report_path = os.path.join(skill_dir, "unassigned_report.md")
    with open(global_report_path, "w") as f:
        f.write("\n".join(report))
        
    # Write report locally to workspace
    local_report_path = os.path.join(os.getcwd(), "unassigned_report.md")
    try:
        with open(local_report_path, "w") as f:
            f.write("\n".join(report))
        print(f"\nLocal report successfully written to: {local_report_path}")
    except Exception as e:
        print(f"Warning: Could not write local report to workspace: {e}", file=sys.stderr)
        
    print(f"Global report successfully written to: {global_report_path}")
    print("\n".join(report))

if __name__ == "__main__":
    main()
