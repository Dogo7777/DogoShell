#!/usr/bin/env python3
"""Gera o tema de ícones "Wall": pastas do Papirus recoloridas com a cor do wallpaper.
Requer: papirus-icon-theme  (sudo dnf install papirus-icon-theme)
Lê ~/.config/quickshell/island/colors.json (escrito pelo wallcolors.py).
"""
import colorsys, glob, json, os, re, shutil, subprocess, sys

HOME = os.path.expanduser("~")
DEST = os.environ.get("WALL_ICON_DEST", HOME + "/.local/share/icons/Wall")
SRC_ROOTS = [os.environ.get("WALL_ICON_SRC", ""), "/usr/share/icons/Papirus-Dark", "/usr/share/icons/Papirus"]
NAMES = ("folder*.svg", "user-*.svg", "inode-directory.svg")

try:
    accent = json.load(open(HOME + "/.config/quickshell/island/colors.json"))["accent"].lstrip("#")
except Exception:
    sys.exit("colors.json não encontrado — rode o wallcolors.py primeiro")

ar, ag, ab = (int(accent[i:i + 2], 16) / 255 for i in (0, 2, 4))
AH, AL, AS = colorsys.rgb_to_hls(ar, ag, ab)

src = next((s for s in SRC_ROOTS if s and os.path.isdir(s)), None)
if not src:
    sys.exit("Papirus não encontrado: sudo dnf install papirus-icon-theme")

HEX = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")


def recolor(m):
    h = m.group(1)
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
    if ss < 0.12:                      # cinzas/sombras ficam como estão
        return m.group(0)
    ns = 0.0 if AS < 0.12 else min(1.0, ss * (0.55 + AS))
    nr, ng, nb = colorsys.hls_to_rgb(AH, ll, ns)
    return "#%02x%02x%02x" % (round(nr * 255), round(ng * 255), round(nb * 255))


shutil.rmtree(DEST, ignore_errors=True)
dirs = []
for pdir in sorted(glob.glob(src + "/*/places")):
    size = os.path.basename(os.path.dirname(pdir))
    m = re.match(r"(\d+)x\1$", size)
    if not m:
        continue
    out = os.path.join(DEST, size, "places")
    os.makedirs(out, exist_ok=True)
    n = 0
    for pat in NAMES:
        for f in glob.glob(os.path.join(pdir, pat)):
            try:
                svg = open(f, encoding="utf-8").read()   # segue symlinks
            except Exception:
                continue
            with open(os.path.join(out, os.path.basename(f)), "w", encoding="utf-8") as o:
                o.write(HEX.sub(recolor, svg))
            n += 1
    if n:
        dirs.append((size, int(m.group(1))))

with open(os.path.join(DEST, "index.theme"), "w") as f:
    f.write("[Icon Theme]\nName=Wall\nComment=Pastas na cor do wallpaper\n")
    f.write("Inherits=%s\n" % os.path.basename(src))
    f.write("Directories=" + ",".join(s + "/places" for s, _ in dirs) + "\n\n")
    for s, n in dirs:
        f.write("[%s/places]\nSize=%d\nContext=Places\nType=Fixed\n\n" % (s, n))

subprocess.run(["gtk-update-icon-cache", "-f", "-t", DEST], check=False,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "Wall"], check=False)
print("tema Wall atualizado: #" + accent)
