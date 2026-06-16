#!/usr/bin/env python3
import os
import sys
import json
import time
import urllib.request

HOME = os.path.expanduser("~")
VIDE_DIR = os.path.join(HOME, ".local", "share", "vide")
DB_PATH = os.path.join(VIDE_DIR, "store_db.json")
USER_PLUGINS_PATH = os.path.join(VIDE_DIR, "user_plugins.json")

def download_db():
    os.makedirs(VIDE_DIR, exist_ok=True)
    url = "https://github.com/alex-popov-tech/store.nvim.crawler/releases/latest/download/db_minified.json"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=10.0) as response:
            data = response.read()
            with open(DB_PATH, "wb") as f:
                f.write(data)
        return True
    except Exception as e:
        sys.stderr.write(f"Error downloading database: {e}\n")
        return False

def check_cache():
    if not os.path.exists(DB_PATH):
        return download_db()
    # If older than 24 hours, update
    st = os.stat(DB_PATH)
    if time.time() - st.st_mtime > 86400:
        return download_db()
    return True

def search(query, category=None):
    if not check_cache():
        print(json.dumps([]))
        return

    try:
        with open(DB_PATH, "r", encoding="utf-8") as f:
            db = json.load(f)
    except Exception as e:
        sys.stderr.write(f"Error reading DB: {e}\n")
        print(json.dumps([]))
        return

    items = db.get("items", [])

    # Load installed user plugins to filter/mark them
    installed = set()
    if os.path.exists(USER_PLUGINS_PATH):
        try:
            with open(USER_PLUGINS_PATH, "r") as f:
                installed = set(json.load(f))
        except:
            pass

    # Filter by category if specified and not 'all'
    if category and category != "all":
        if category == "installed":
            items = [item for item in items if item.get("full_name", "") in installed]
        else:
            category_tags = {
                "colorscheme": ["colorscheme", "theme", "color-scheme"],
                "lsp": ["lsp"],
                "git": ["git"],
                "ai": ["ai", "llm"],
                "treesitter": ["treesitter", "tree-sitter"],
                "telescope": ["telescope", "telescope-extension"],
            }
            target_tags = category_tags.get(category, [category])
            items = [item for item in items if any(t.lower() in target_tags for t in item.get("tags", []))]

    if not query:
        # Return top 50 plugins by stars
        results = sorted(items, key=lambda x: x.get("stars", {}).get("curr", 0), reverse=True)[:50]
    else:
        query = query.lower()
        matches = []
        for item in items:
            name = item.get("name", "").lower()
            full_name = item.get("full_name", "").lower()
            desc = item.get("description", "") or ""
            desc = desc.lower()
            tags = [t.lower() for t in item.get("tags", [])]
            
            if (query in name or 
                query in full_name or 
                query in desc or 
                any(query in t for t in tags)):
                matches.append(item)
        results = sorted(matches, key=lambda x: x.get("stars", {}).get("curr", 0), reverse=True)[:50]

    out = []
    for item in results:
        repo = item.get("full_name", "")
        out.append({
            "name": item.get("name", ""),
            "full_name": repo,
            "stars": item.get("stars", {}).get("curr", 0),
            "description": item.get("description", "") or "",
            "installed": repo in installed
        })
    print(json.dumps(out))

def add_plugin(repo):
    os.makedirs(VIDE_DIR, exist_ok=True)
    plugins = []
    if os.path.exists(USER_PLUGINS_PATH):
        try:
            with open(USER_PLUGINS_PATH, "r") as f:
                plugins = json.load(f)
        except Exception:
            plugins = []
    
    if repo not in plugins:
        plugins.append(repo)
        try:
            with open(USER_PLUGINS_PATH, "w") as f:
                json.dump(plugins, f, indent=2)
            print(json.dumps({"success": True, "message": f"Added plugin {repo}"}))
        except Exception as e:
            print(json.dumps({"success": False, "message": str(e)}))
    else:
        print(json.dumps({"success": True, "message": "Already installed"}))

def remove_plugin(repo):
    if not os.path.exists(USER_PLUGINS_PATH):
        print(json.dumps({"success": False, "message": "No plugins installed"}))
        return

    try:
        with open(USER_PLUGINS_PATH, "r") as f:
            plugins = json.load(f)
    except Exception:
        print(json.dumps({"success": False, "message": "Failed to read installed plugins"}))
        return

    if repo in plugins:
        plugins.remove(repo)
        try:
            with open(USER_PLUGINS_PATH, "w") as f:
                json.dump(plugins, f, indent=2)
            print(json.dumps({"success": True, "message": f"Removed plugin {repo}"}))
        except Exception as e:
            print(json.dumps({"success": False, "message": str(e)}))
    else:
        print(json.dumps({"success": False, "message": "Plugin not installed"}))

def main():
    if len(sys.argv) < 2:
        print("Usage: store_search.py <search|add|remove|download> [args...]")
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "search":
        query = sys.argv[2] if len(sys.argv) > 2 else ""
        category = sys.argv[3] if len(sys.argv) > 3 else "all"
        search(query, category)
    elif cmd == "add":
        if len(sys.argv) < 3:
            print(json.dumps({"success": False, "message": "Missing repo name"}))
            sys.exit(1)
        add_plugin(sys.argv[2])
    elif cmd == "remove":
        if len(sys.argv) < 3:
            print(json.dumps({"success": False, "message": "Missing repo name"}))
            sys.exit(1)
        remove_plugin(sys.argv[2])
    elif cmd == "download":
        success = download_db()
        print(json.dumps({"success": success}))

if __name__ == "__main__":
    main()
