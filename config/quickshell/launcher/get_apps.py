#!/usr/bin/env python3
import os, json, re, sys, time

CONFIG_PATH = os.path.expanduser("~/.config/quickshell/launcher/user_config.json")
USAGE_PATH = os.path.expanduser("~/.cache/launcher-usage.json")
DEFAULT_GROUPS = ["Internet", "Jogos", "Desenvolvimento", "Mídia", "Sistema", "Escritório", "Outros"]


def load(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)


cfg = load(CONFIG_PATH, {"groups": DEFAULT_GROUPS, "app_data": {}})
cfg.setdefault("groups", DEFAULT_GROUPS)
cfg.setdefault("app_data", {})

# ---- ações chamadas pelo QML ----
if len(sys.argv) > 1:
    cmd, a = sys.argv[1], sys.argv[2:]
    if cmd == "fav" and a:
        d = cfg["app_data"].setdefault(a[0], {})
        d["favorite"] = not d.get("favorite", False)
        save(CONFIG_PATH, cfg)
    elif cmd == "group" and len(a) > 1:
        cfg["app_data"].setdefault(a[0], {})["group"] = a[1]
        save(CONFIG_PATH, cfg)
    elif cmd == "new_group" and a:
        if a[0] not in cfg["groups"]:
            cfg["groups"].append(a[0])
        save(CONFIG_PATH, cfg)
    elif cmd == "used" and a:
        u = load(USAGE_PATH, {})
        u[a[0]] = u.get(a[0], 0) + 1
        save(USAGE_PATH, u)
    sys.exit(0)

# ---- leitura ----
usage = load(USAGE_PATH, {})
dirs = [
    "/usr/share/applications",
    "/usr/local/share/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
    os.path.expanduser("~/.local/share/applications"),
]


def parse(path):
    d, in_entry = {}, False
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if line.startswith("["):
                in_entry = line == "[Desktop Entry]"
                continue
            if in_entry and "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                d.setdefault(k.strip(), v.strip())
    return d


def category(cats):
    c = cats.lower()
    if "game" in c: return "Jogos"
    if "network" in c or "web" in c: return "Internet"
    if "development" in c or "ide" in c: return "Desenvolvimento"
    if "audio" in c or "video" in c or "multimedia" in c: return "Mídia"
    if "office" in c: return "Escritório"
    if "system" in c or "settings" in c or "utility" in c: return "Sistema"
    return "Outros"


apps = {}
for base in dirs:
    if not os.path.isdir(base):
        continue
    for fn in os.listdir(base):
        if not fn.endswith(".desktop"):
            continue
        try:
            e = parse(os.path.join(base, fn))
        except Exception:
            continue
        if e.get("Type", "Application") != "Application": continue
        if e.get("NoDisplay", "").lower() == "true" or e.get("Hidden", "").lower() == "true": continue
        name = e.get("Name[pt_BR]") or e.get("Name")
        ex = e.get("Exec")
        if not name or not ex: continue
        ex = re.sub(r"\s*%[a-zA-Z%]", "", ex).strip()
        if e.get("Terminal", "").lower() == "true":
            ex = "kitty -e " + ex
        ud = cfg["app_data"].get(name, {})
        apps[name] = {
            "name": name,
            "exec": ex,
            "icon": e.get("Icon", "application-x-executable"),
            "category": ud.get("group", category(e.get("Categories", ""))),
            "favorite": ud.get("favorite", False),
            "uses": usage.get(name, 0),
        }

print(json.dumps({
    "groups": cfg["groups"],
    "apps": sorted(apps.values(), key=lambda x: x["name"].lower()),
}, ensure_ascii=False))
