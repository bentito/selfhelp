import re
import sys
import json
import urllib.parse

def clean_html(text):
    return re.sub(r'<[^>]+>', ' ', text).strip()

def decode_url(url):
    if "google.com/url?q=" in url:
        parsed = urllib.parse.urlparse(url)
        qs = urllib.parse.parse_qs(parsed.query)
        return qs.get('q', [url])[0]
    return url

def main(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        html = f.read()

    # Find all date headings using the stricter h2 > span pattern
    date_pattern = r'<h2[^>]*>\s*<span[^>]*>\s*((?:👉|🚘)?\s*(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},\s+20\d{2})\s*</span>\s*</h2>'
    matches = list(re.finditer(date_pattern, html))

    if len(matches) < 2:
        print(json.dumps({"error": "Could not find at least two dates."}))
        return

    first_date = matches[0].group(1).strip()
    
    # We want the chunk of HTML between the first date and the second date
    start_idx = matches[0].end()
    end_idx = matches[1].start()
    chunk = html[start_idx:end_idx]

    # Extract tables in this chunk
    tables = []
    
    for table_html in re.findall(r'<table.*?>(.*?)</table>', chunk, re.DOTALL):
        rows = []
        for row_html in re.findall(r'<tr.*?>(.*?)</tr>', table_html, re.DOTALL):
            cells = []
            for cell_html in re.findall(r'<td.*?>(.*?)</td>', row_html, re.DOTALL):
                # Find the first link if any
                link_match = re.search(r'href="([^"]+)"', cell_html)
                href = decode_url(link_match.group(1)) if link_match else None
                
                text = clean_html(cell_html)
                # replace multiple spaces with single space
                text = re.sub(r'\s+', ' ', text)
                
                cells.append({
                    "text": text,
                    "href": href
                })
            if cells:
                rows.append(cells)
        if rows:
            tables.append(rows)

    print(json.dumps({
        "date": first_date,
        "tables": tables
    }, indent=2))

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(json.dumps({"error": "HTML filename required"}))
        sys.exit(1)
    main(sys.argv[1])