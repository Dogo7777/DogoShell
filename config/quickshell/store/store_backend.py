#!/usr/bin/env python3
"""Backend da Loja de Flatpaks.
  store_backend.py get            -> Retorna instalados e mais populares
  store_backend.py search TERMO   -> Busca ordenada por relevância e popularidade
"""
import json, os, subprocess, sys, urllib.parse, urllib.request

ICON_DIRS = [
    os.path.expanduser("~/.local/share/flatpak/exports/share/icons/hicolor"),
    "/var/lib/flatpak/exports/share/icons/hicolor",
    "/usr/share/icons/hicolor",
    os.path.expanduser("~/.local/share/flatpak/appstream/flathub/x86_64/active/icons/128x128"),
    "/var/lib/flatpak/appstream/flathub/x86_64/active/icons/128x128",
    os.path.expanduser("~/.local/share/flatpak/appstream/flathub/x86_64/active/icons/64x64"),
    "/var/lib/flatpak/appstream/flathub/x86_64/active/icons/64x64",
]

THEME_KEYWORDS = ["gtk3theme", "gtk4theme", "icontheme", "kvantumtheme", "soundtheme", "theme", "gtk-theme"]
PLUGIN_KEYWORDS = [".plugin.", ".extension.", ".baseapp.", ".platform", ".sdk", ".codecs", ".addon", ".locale"]

FALLBACK_POPULAR = [
    {"name": "Spotify", "id": "com.spotify.Client", "summary": "Música e podcasts para todos"},
    {"name": "Discord", "id": "com.discordapp.Discord", "summary": "Chat de voz, vídeo e texto"},
    {"name": "Steam", "id": "com.valvesoftware.Steam", "summary": "Plataforma de jogos digitais"},
    {"name": "VS Code", "id": "com.visualstudio.code", "summary": "Editor de código poderoso"},
    {"name": "OBS Studio", "id": "com.obsproject.Studio", "summary": "Gravação de tela e transmissão"},
    {"name": "Heroic Games", "id": "com.heroicgameslauncher.hgl", "summary": "Launcher de jogos Epic e GOG"},
    {"name": "Firefox", "id": "org.mozilla.firefox", "summary": "Navegador Web rápido e privado"},
    {"name": "VLC", "id": "org.videolan.VLC", "summary": "Reprodutor de mídia universal"},
    {"name": "Blender", "id": "org.blender.Blender", "summary": "Suite de criação 3D"},
    {"name": "GIMP", "id": "org.gimp.GIMP", "summary": "Editor de imagens e fotografias"},
    {"name": "Lutris", "id": "net.lutris.Lutris", "summary": "Gerenciador de jogos para Linux"},
    {"name": "Telegram", "id": "org.telegram.desktop", "summary": "Mensageiro rápido e seguro"}
]

def classify_app(app_id, name=""):
    lid = app_id.lower()
    lname = name.lower()
    is_theme = any(kw in lid for kw in THEME_KEYWORDS) or "theme" in lname or lid.startswith("org.gtk.gtk3theme") or lid.startswith("org.gtk.gtk4theme")
    is_plugin = any(kw in lid for kw in PLUGIN_KEYWORDS) or lid.startswith("org.freedesktop.platform") or lid.startswith("org.freedesktop.sdk")
    return is_theme, is_plugin

def find_icon(app_id):
    sizes = ["128x128", "64x64", "scalable", "256x256"]
    extensions = [".png", ".svg"]
    for base in ICON_DIRS:
        if base.endswith("128x128") or base.endswith("64x64"):
            for ext in extensions:
                path = os.path.join(base, f"{app_id}{ext}")
                if os.path.isfile(path):
                    return f"file://{path}"
        else:
            for size in sizes:
                for ext in extensions:
                    path = os.path.join(base, size, "apps", f"{app_id}{ext}")
                    if os.path.isfile(path):
                        return f"file://{path}"
    return f"https://dl.flathub.org/repo/appstream/x86_64/icons/128x128/{app_id}.png"

def get_installed():
    apps = []
    try:
        res = subprocess.run(
            ["flatpak", "list", "--app", "--columns=name,application,version"],
            capture_output=True, text=True, check=True
        )
        for line in res.stdout.strip().split("\n"):
            if line and "\t" in line:
                parts = line.split("\t")
                name = parts[0].strip()
                app_id = parts[1].strip()
                is_theme, is_plugin = classify_app(app_id, name)
                apps.append({
                    "name": name,
                    "id": app_id,
                    "version": parts[2].strip() if len(parts) > 2 else "",
                    "icon": find_icon(app_id),
                    "installed": True,
                    "is_theme": is_theme,
                    "is_plugin": is_plugin
                })
    except Exception:
        pass
    return apps

def fetch_remote_popular():
    url = "https://flathub.org/api/v2/collection/popular"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            if resp.status == 200:
                data = json.loads(resp.read().decode('utf-8'))
                popular_list = []
                for item in data:
                    app_id = item.get("id") or item.get("app_id") or ""
                    if not app_id:
                        continue
                    name = item.get("name") or app_id
                    summary = item.get("summary") or item.get("subtitle") or app_id
                    icon = item.get("icon") or find_icon(app_id)
                    if icon and not icon.startswith("http") and not icon.startswith("file"):
                        icon = f"https://dl.flathub.org/repo/appstream/x86_64/icons/128x128/{app_id}.png"
                    popular_list.append({
                        "name": name,
                        "id": app_id,
                        "summary": summary,
                        "icon": icon or find_icon(app_id)
                    })
                if popular_list:
                    return popular_list
    except Exception:
        pass
    return FALLBACK_POPULAR

def search_flatpak(query):
    q = query.strip().lower()
    if not q:
        return []

    installed = get_installed()
    installed_ids = {a["id"] for a in installed}

    raw_popular = fetch_remote_popular()
    popular_rank = {p["id"]: idx for idx, p in enumerate(raw_popular)}

    results = []
    seen_ids = set()

    try:
        res = subprocess.run(
            ["flatpak", "search", "--columns=name,application,description", q],
            capture_output=True, text=True, timeout=5
        )
        for line in res.stdout.strip().split("\n"):
            if line and "\t" in line:
                parts = line.split("\t")
                if len(parts) >= 2:
                    name = parts[0].strip()
                    app_id = parts[1].strip()
                    if not app_id or app_id == "Application ID" or app_id in seen_ids:
                        continue

                    seen_ids.add(app_id)
                    is_theme, is_plugin = classify_app(app_id, name)

                    rank = popular_rank.get(app_id, 1000)
                    if app_id.lower() == q or name.lower() == q:
                        rank -= 5000
                    elif name.lower().startswith(q) or app_id.lower().startswith(q):
                        rank -= 2000

                    results.append({
                        "name": name,
                        "id": app_id,
                        "summary": parts[2].strip() if len(parts) > 2 else app_id,
                        "icon": find_icon(app_id),
                        "installed": app_id in installed_ids,
                        "is_theme": is_theme,
                        "is_plugin": is_plugin,
                        "_rank": rank
                    })
    except Exception:
        pass

    results.sort(key=lambda x: x["_rank"])
    for item in results:
        item.pop("_rank", None)

    return results[:60]

def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "get"

    if cmd == "search" and len(args) > 1:
        query = args[1]
        print(json.dumps(search_flatpak(query), ensure_ascii=False))
        return

    installed = get_installed()
    installed_ids = {a["id"] for a in installed}

    raw_popular = fetch_remote_popular()
    popular = []
    for p in raw_popular:
        app_id = p["id"]
        name = p["name"]
        is_theme, is_plugin = classify_app(app_id, name)
        popular.append({
            "name": name,
            "id": app_id,
            "summary": p.get("summary", ""),
            "icon": p.get("icon") or find_icon(app_id),
            "installed": app_id in installed_ids,
            "is_theme": is_theme,
            "is_plugin": is_plugin
        })

    out = {
        "installed": installed,
        "popular": popular
    }
    print(json.dumps(out, ensure_ascii=False))

if __name__ == "__main__":
    main()
