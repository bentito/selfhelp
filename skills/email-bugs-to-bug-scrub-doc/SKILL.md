---
name: email-bugs-to-bug-scrub-doc
description: Automates triaging "New: OCPBUGS-" emails and writing them to the team bug scrub Google Doc with Jira hyperlinks. Use when the user needs to process incoming bug notifications from aos-network-edge-staff@redhat.com.
---

# Email Bugs to Bug Scrub Doc

This skill automates the workflow of fetching, grouping, and recording new OpenShift bugs into the team's bug scrub agenda, while ensuring bug IDs are hyperlinked.

## Prerequisites

1. **Active Account Check**: Verify you are using the correct corporate account (e.g., `btofel@redhat.com`).
   - Run `gcloud config list` or `gcloud auth list`.
2. **API Access**: The Google Docs API (`docs.googleapis.com`) must be enabled on the target project (e.g., `btofel-gemini-dev`). If you encounter permission errors appending directly, use the "Temp Doc Strategy" below.
3. **Document ID**: The target Google Doc ID is `12lNZa0pNcCek5B18X685PBhKB7WDID7e-55O5Y4WN78`.

## Workflow

### 1. Fetch Unread Bugs
Search for unread OCPBUGS emails from the Network Edge notifier:
```bash
gws gmail +triage --query "from:aos-network-edge-staff@redhat.com subject:\"New: OCPBUGS-\" label:unread label:inbox" --max 100
```

### 2. Grouping and Summarization
For each new bug identified:
1. **Read Content**: Fetch details using `gws gmail +read --id <ID>`.
2. **Extract Metadata**: Identify the CVE (if any), Component, and OpenShift Version.
3. **Selection**:
   - Group bugs sharing the same CVE or root cause.
   - Choose the bug targeting the **latest OCP version** (e.g., 4.22) or the latest operator version (e.g., `ext-dns-optr-1-2`) as the primary entry.
   - Note the number of other related bugs in the summary.
4. **Deduplication**: Check the "New tickets" section of the target document to ensure the bug isn't already listed.

### 3. Generate HTML Content
To preserve hyperlinks (e.g., to Jira), construct the output as HTML:
```html
<ul>
  <li><a href="https://redhat.atlassian.net/browse/OCPBUGS-XXXXX">OCPBUGS-XXXXX</a>: Summary...
    <ul>
      <li>Summary note: There are X other related bugs...</li>
    </ul>
  </li>
</ul>
```

### 4. Update Document
Identify the latest date section (typically a Tuesday or Thursday).

**Direct Write Strategy (If API is enabled):**
You can attempt to patch the document via Drive API:
```bash
echo "<ul><li>...</li></ul>" > update.html
gws drive files update --params '{"fileId": "TARGET_DOC_ID"}' --upload update.html --upload-content-type text/html
```

**Temp Doc Strategy (Fallback if direct edit fails or overwrites):**
1. Create a temp document: `gws drive files create --json '{"name": "Temp Bug Scrub - YYYY-MM-DD", "mimeType": "application/vnd.google-apps.document"}'`
2. Update the temp doc with the HTML string using the method above.
3. Provide the temp doc URL to the user to copy/paste, then offer to delete the temp doc.

### 5. Mark Emails as Read
Remove the `UNREAD` label to prevent double-processing:
```bash
gws gmail users messages modify --params '{"userId": "me", "id": "<ID>"}' --json '{"removeLabelIds": ["UNREAD"]}'
```
**Important**: Process in small batches or sequentially to avoid rate limiting (`429 Too many concurrent requests`).

## Best Practices
- **Dry Run**: Always perform a dry run to show the user which bugs will be added and which emails will be marked as read before committing changes.
- **Embargoed Issues**: Pay close attention to "EMBARGOED" flags in CVE summaries; handle these according to team security policies.
- **Ship-help-jira**: Note if bugs were created by automated tools like `ship-help-jira`.
