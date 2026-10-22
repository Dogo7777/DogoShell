#!/usr/bin/env python3
"""Backend para listagem, leitura, busca de ícones e escrita de ficheiros .desktop."""
import sys, json, os, glob

USER_APPS = os.path.expanduser("~/.local/share/applications")
SYSTEM_APPS = "/usr/share/applications"

def parse_desktop_file(filepath):
    """Lê um ficheiro .desktop de forma robusta linha a linha."""
    data = {
        "name": "", "exec": "", "icon": "application-x-executable", 
        "comment": "", "terminal": False, 
        "categories": "Utility;", "nodisplay": False
    }
    in_desktop_entry = False
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if line.startswith('['):
                    in_desktop_entry = (line == '[Desktop Entry]')
                    continue
                if in_desktop_entry and '=' in line:
                    key, val = line.split('=', 1)
                    key = key.strip()
                    val = val.strip()
                    if key == 'Name' and not data["name"]:
                        data["name"] = val
                    elif key == 'Exec' and not data["exec"]:
                        data["exec"] = val
                    elif key == 'Icon' and not data["icon"]:
                        data["icon"] = val
                    elif key == 'Comment' and not data["comment"]:
                        data["comment"] = val
                    elif key == 'Categories' and not data["categories"]:
                        data["categories"] = val
                    elif key == 'Terminal':
                        data["terminal"] = (val.lower() == 'true')
                    elif key == 'NoDisplay':
                        data["nodisplay"] = (val.lower() == 'true')
    except Exception:
        pass
    return data

def list_desktops():
    apps = []
    paths = []
    
    if os.path.exists(USER_APPS):
        paths.extend(glob.glob(os.path.join(USER_APPS, "*.desktop")))
    
    if os.path.exists(SYSTEM_APPS):
        paths.extend(glob.glob(os.path.join(SYSTEM_APPS, "*.desktop")))

    seen_names = set()
    for p in paths:
        fname = os.path.basename(p)
        if fname in seen_names:
            continue
        seen_names.add(fname)

        parsed = parse_desktop_file(p)
        if parsed.get("nodisplay"):
            continue

        apps.append({
            "name": parsed.get("name") or fname.replace(".desktop", ""),
            "icon": parsed.get("icon") or "application-x-executable",
            "path": p,
            "filename": fname,
            "is_user": p.startswith(USER_APPS)
        })

    apps.sort(key=lambda x: x["name"].lower())
    return apps

def list_system_icons():
    icons = set()
    for app in list_desktops():
        if app.get("icon"):
            icons.add(app["icon"])

    search_dirs = [
        "/usr/share/pixmaps",
        "/usr/share/icons/hicolor/48x48/apps",
        "/usr/share/icons/hicolor/scalable/apps",
        os.path.expanduser("~/.local/share/icons")
    ]
    
    for d in search_dirs:
        if os.path.exists(d):
            try:
                for f in os.listdir(d):
                    if f.endswith(('.png', '.svg', '.xpm')):
                        icons.add(os.path.splitext(f)[0])
            except Exception:
                pass

    return sorted(list(icons))

def load_desktop(filepath):
    filepath = os.path.expanduser(filepath)
    if not os.path.exists(filepath):
        return {
            "name": "", "exec": "", "icon": "", 
            "comment": "", "terminal": False, 
            "categories": "Utility;", "path": filepath, "exists": False
        }
    parsed = parse_desktop_file(filepath)
    parsed["path"] = filepath
    parsed["exists"] = True
    return parsed

def save_desktop(filepath, data):
    filepath = os.path.expanduser(filepath)
    
    if filepath.startswith(SYSTEM_APPS):
        fname = os.path.basename(filepath)
        filepath = os.path.join(USER_APPS, fname)

    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    
    lines = ["[Desktop Entry]", "Type=Application"]
    lines.append(f"Name={data.get('name', '')}")
    lines.append(f"Exec={data.get('exec', '')}")
    lines.append(f"Icon={data.get('icon', '')}")
    lines.append(f"Comment={data.get('comment', '')}")
    lines.append(f"Categories={data.get('categories', 'Utility;')}")
    lines.append(f"Terminal={'true' if data.get('terminal') else 'false'}")

    try:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write("\n".join(lines) + "\n")
        return {"success": True, "path": filepath}
    except Exception as e:
        return {"success": False, "error": str(e)}

def main():
    args = sys.argv[1:]
    if not args:
        print(json.dumps({"error": "Nenhum comando especificado"}))
        return

    cmd = args[0]
    if cmd == "list":
        print(json.dumps(list_desktops(), ensure_ascii=False))
    elif cmd == "icons":
        print(json.dumps(list_system_icons(), ensure_ascii=False))
    elif cmd == "load" and len(args) > 1:
        print(json.dumps(load_desktop(args[1]), ensure_ascii=False))
    elif cmd == "save" and len(args) > 2:
        try:
            data = json.loads(args[2])
            print(json.dumps(save_desktop(args[1], data), ensure_ascii=False))
        except Exception as e:
            print(json.dumps({"success": False, "error": str(e)}))

if __name__ == "__main__":
    main()
