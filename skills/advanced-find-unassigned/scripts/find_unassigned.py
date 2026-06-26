import json
import subprocess
import os
import sys
import time
import re

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

def fetch_pr_scrub_doc_urls():
    print("Fetching PR Scrub Google Doc...", flush=True)
    try:
        cmd = ["gws", "drive", "files", "export", "--params", '{"fileId": "178UlalXBSyrxViOzZUSqm9MHgjlcdY3W6ecIsA7yuC8", "mimeType": "text/plain"}']
        subprocess.run(cmd, capture_output=True, text=True, check=True)
        if os.path.exists("download.txt"):
            with open("download.txt", "r") as f:
                content = f.read()
            os.remove("download.txt")
            pattern = re.compile(r"https://github\.com/[a-zA-Z0-9\-_]+/[a-zA-Z0-9\-_]+/pull/\d+")
            urls = set(pattern.findall(content))
            print(f"Found {len(urls)} PR URLs in PR Scrub doc.", flush=True)
            return urls
    except Exception as e:
        print(f"Error fetching PR scrub doc: {e}", file=sys.stderr)
    return set()

def triage_pr(pr, team_members_lower, scrubbed_urls):
    author = pr.get("author", {}).get("login", "Unknown") if pr.get("author") else "Unknown"
    author_lower = author.lower()
    
    title = pr.get("title", "")
    body = pr.get("body", "")
    url = pr.get("url", "")
    labels = [l.get("name", "").lower() for l in pr.get("labels", [])]
    
    # 1. Mentioned in PR Scrub?
    mentioned_in_scrub = url in scrubbed_urls
    
    # 2. Author Category
    bot_list = ["openshift-bot", "openshift-ci-robot", "red-hat-konflux-kflux-prd-rh03[bot]"]
    is_bot = author_lower in bot_list or author_lower.endswith("[bot]")
    is_sustaining = author_lower == "ocp-sustaining-admins"
    is_team = author_lower in team_members_lower
    is_external = not is_bot and not is_sustaining and not is_team
    
    # 3. Jira tracking?
    has_jira_title = bool(re.search(r"(OCPBUGS|NE|OCPSTRAT|RFE)-\d+", title.upper()))
    has_jira_label = any("jira/valid-bug" in l or "jira/valid-reference" in l for l in labels)
    has_jira = has_jira_title or has_jira_label
    
    # 4. PR Description complete?
    is_desc_complete = len(body.strip()) > 50
    
    # Generate notes
    notes = []
    if mentioned_in_scrub:
        notes.append("✅ In PR Scrub")
    else:
        notes.append("❌ Not in PR Scrub")
        
    if is_external:
        notes.append("🌍 External Contributor")
    if is_bot:
        notes.append("🤖 Bot")
    if is_sustaining:
        notes.append("🛡️ Sustaining")
        
    if has_jira:
        notes.append("✅ Tracked")
    else:
        notes.append("⚠️ Untracked")
        
    if not is_desc_complete:
        notes.append("⚠️ Short/Empty Desc")
        
    pr["triage_notes"] = " • ".join(notes)
    pr["is_bot"] = is_bot
    pr["is_sustaining"] = is_sustaining
    pr["is_team"] = is_team
    pr["is_external"] = is_external

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    skill_dir = os.path.dirname(script_dir)
    
    repo_list_path = os.path.join(skill_dir, "references", "team-repo-list.json")
    owners_path = os.path.join(skill_dir, "references", "owners.json")
    
    repo_config = load_json(repo_list_path)
    owners_config = load_json(owners_path)
    
    cat1_repos = repo_config.get("category_1_core", [])
    cat2_repos = repo_config.get("category_2_shared", [])
    team_members = [m["github"] for m in owners_config.get("team_members", [])]
    team_members_lower = [t.lower() for t in team_members if t]
    
    scrubbed_urls = fetch_pr_scrub_doc_urls()
    
    unassigned_prs = []
    seen_pr_urls = set()
    
    print("Searching Category 1 (NE Owned) repositories for all unassigned PRs (excluding WIP label and Drafts)...", flush=True)
    for repo in cat1_repos:
        print(f" - {repo}...", flush=True)
        args = ["--repo", repo, "--state", "open", "no:assignee", "--draft=false", "--json", "number,title,url,updatedAt,repository,author,labels,body", "--limit", "50", "--", "-label:do-not-merge/work-in-progress"]
        prs = run_gh_search(args)
        for pr in prs:
            if pr["url"] in seen_pr_urls: continue
            seen_pr_urls.add(pr["url"])
            triage_pr(pr, team_members_lower, scrubbed_urls)
            pr["category"] = "Category 1 (NE Owned)"
            unassigned_prs.append(pr)
        time.sleep(1.5)
        
    print("\nSearching Category 2 (Shared) repositories for unassigned PRs authored by team members (excluding WIP label and Drafts)...", flush=True)
    for author in team_members:
        print(f" - Author: {author}...", flush=True)
        args = ["--state", "open", f"author:{author}", "no:assignee", "--draft=false", "--json", "number,title,url,updatedAt,repository,author,labels,body", "--limit", "50", "--", "-label:do-not-merge/work-in-progress"]
        prs = run_gh_search(args)
        for pr in prs:
            repo_name = pr.get("repository", {}).get("nameWithOwner")
            if repo_name in cat2_repos:
                if pr["url"] in seen_pr_urls: continue
                seen_pr_urls.add(pr["url"])
                triage_pr(pr, team_members_lower, scrubbed_urls)
                pr["category"] = "Category 2 (Shared)"
                unassigned_prs.append(pr)
            elif repo_name in cat1_repos:
                if pr["url"] not in seen_pr_urls:
                    seen_pr_urls.add(pr["url"])
                    triage_pr(pr, team_members_lower, scrubbed_urls)
                    pr["category"] = "Category 1 (NE Owned)"
                    unassigned_prs.append(pr)
        time.sleep(1.5)
        
    # Sort PRs
    unassigned_prs.sort(key=lambda x: x.get("updatedAt", ""), reverse=True)
    
    # Group PRs
    groups = {
        "Team (NE Owned)": [p for p in unassigned_prs if p["category"] == "Category 1 (NE Owned)" and p["is_team"]],
        "External (NE Owned)": [p for p in unassigned_prs if p["category"] == "Category 1 (NE Owned)" and p["is_external"]],
        "Sustaining (NE Owned)": [p for p in unassigned_prs if p["category"] == "Category 1 (NE Owned)" and p["is_sustaining"]],
        "Bots (NE Owned)": [p for p in unassigned_prs if p["category"] == "Category 1 (NE Owned)" and p["is_bot"]],
        "Team (Shared)": [p for p in unassigned_prs if p["category"] == "Category 2 (Shared)" and p["is_team"]]
    }
    
    report = []
    report.append("# Advanced Triage: Unassigned Pull Requests")
    report.append(f"Generated on: {time.strftime('%Y-%m-%d %H:%M:%S')} (Drafts/WIP Excluded)\n")
    report.append("This report deeply triages open, unassigned, non-draft/WIP PRs across your NE Owned and shared repositories, cross-referencing with the PR Scrub doc.\n")
    
    for group_name, pr_list in groups.items():
        if not pr_list: continue
        report.append(f"## {group_name}")
        report.append("| Repository | PR | Author | Title | Updated | Link |")
        report.append("| :--- | :--- | :--- | :--- | :--- | :--- |")
        for pr in pr_list:
            repo = pr["repository"]["nameWithOwner"]
            num = pr["number"]
            author = pr.get("author", {}).get("login", "Unknown") if pr.get("author") else "Unknown"
            title = pr["title"]
            updated = pr["updatedAt"][:10]
            url = pr["url"]
            
            # Format Title column to contain both Title and Triage notes under it
            short_title = title[:80] + "..." if len(title) > 83 else title
            short_title = short_title.replace("|", "\\|")
            triage_notes = pr["triage_notes"]
            
            # Combine Title and Triage Analysis
            title_cell = f"**{short_title}**<br>_Triage: {triage_notes}_"
            
            report.append(f"| {repo} | #{num} | {author} | {title_cell} | {updated} | [View]({url}) |")
        report.append("\n")
        
    # Save globally (within the skill directory)
    global_report_path = os.path.join(skill_dir, "advanced_triage_report.md")
    with open(global_report_path, "w") as f:
        f.write("\n".join(report))
        
    # Save locally (within the user's active workspace directory)
    local_report_path = os.path.join(os.getcwd(), "advanced_triage_report.md")
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
