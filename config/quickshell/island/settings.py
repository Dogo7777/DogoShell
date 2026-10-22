#!/usr/bin/env python3
"""Backend das configurações do Hyprland e Quickshell."""
import copy, json, os, re, subprocess, sys

HOME = os.environ.get("HOME", os.path.expanduser("~"))
STORE = HOME + "/.config/hypr/settings.json"
LUA = HOME + "/.config/hypr/settings.lua"
STYLE = HOME + "/.config/quickshell/style.json"

DEFAULTS = {
    "shape": "round",
    "blur": True, "blur_size": 6, "blur_passes": 2,
    "shell_blur": True,
    "shadow": False,
    "opacity_active": 1.0, "opacity_inactive": 1.0,
    "gaps_in": 5, "gaps_out": 10, "gaps_top": 45, "border": 2,
    "anim_scale": 1.0, "border_spin": False,
    "layout": "dwindle",
    "sensitivity": 0.0,
    "natural_scroll": False,
    "cursor_size": 24,
    "focus_mouse": True,
    # Configurações de Barra e Ilha
    "bar_mode": "island",        # "island" ou "bar"
    "bar_position": "top",       # "top" ou "bottom"
    "bar_full_width": False,     # True = 100% largura
    "bar_floating": True,        # True = com margem e cantos suaves
    "bar_margin": 6,             # Margem em pixels da borda
    "bar_opacity": 0.55,         # Opacidade do fundo (0.10 a 1.0)
    "show_clock_date": False,    # Exibe data (dd/MM) junto ao relógio
    "binds": {
        "terminal": "SUPER + Q",
        "filemanager": "SUPER + E",
        "launcher": "SUPER + R",
        "launcher2": "SUPER + SPACE",
        "wallpaper": "SUPER + W",
        "power": "SUPER + M",
        "lock": "SUPER + L",
        "settings": "SUPER + comma",
        "close": "SUPER + C",
        "float": "SUPER + V",
    },
}
SHAPES = {"round": (12, 1.0), "soft": (6, 0.5), "square": (0, 0.0)}


def load():
    cur = copy.deepcopy(DEFAULTS)
    try:
        with open(STORE, encoding="utf-8") as f:
            saved = json.load(f)
        for k, v in saved.items():
            if k == "binds" and isinstance(v, dict):
                cur["binds"].update({a: b for a, b in v.items() if a in cur["binds"]})
            elif k in cur:
                cur[k] = v
    except Exception:
        pass
    return cur


def lua(o, ind=0):
    pad = "    " * (ind + 1)
    if isinstance(o, bool):
        return "true" if o else "false"
    if isinstance(o, (int, float)):
        return repr(o)
    if isinstance(o, str):
        return json.dumps(o, ensure_ascii=False)
    if isinstance(o, dict):
        rows = []
        for k, v in o.items():
            key = k if re.match(r"^[A-Za-z_]\w*$", k) else "[%s]" % json.dumps(k)
            rows.append("%s%s = %s," % (pad, key, lua(v, ind + 1)))
        return "{\n" + "\n".join(rows) + "\n" + "    " * ind + "}"
    raise TypeError(type(o))


def write_all(s):
    rounding, scale = SHAPES.get(s["shape"], SHAPES["round"])
    out = {
        "rounding": rounding,
        "border": int(s["border"]),
        "gaps_in": int(s["gaps_in"]),
        "gaps_out": {"top": int(s["gaps_top"]), "right": int(s["gaps_out"]),
                     "bottom": int(s["gaps_out"]), "left": int(s["gaps_out"])},
        "blur": bool(s["blur"]),
        "blur_size": int(s["blur_size"]),
        "blur_passes": int(s["blur_passes"]),
        "shell_blur": bool(s["shell_blur"]),
        "shadow": bool(s["shadow"]),
        "opacity_active": float(s["opacity_active"]),
        "opacity_inactive": float(s["opacity_inactive"]),
        "anim_scale": float(s["anim_scale"]),
        "border_spin": bool(s["border_spin"]),
        "layout": str(s["layout"]),
        "sensitivity": float(s["sensitivity"]),
        "natural_scroll": bool(s["natural_scroll"]),
        "cursor_size": int(s["cursor_size"]),
        "focus_mouse": bool(s["focus_mouse"]),
        "binds": s["binds"],
    }
    style_out = {
        "scale": scale,
        "bar_mode": str(s.get("bar_mode", "island")),
        "bar_position": str(s.get("bar_position", "top")),
        "bar_full_width": bool(s.get("bar_full_width", False)),
        "bar_floating": bool(s.get("bar_floating", True)),
        "bar_margin": int(s.get("bar_margin", 6)),
        "bar_opacity": float(s.get("bar_opacity", 0.55)),
        "show_clock_date": bool(s.get("show_clock_date", False)),
    }
    for path in (STORE, LUA, STYLE):
        os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(STORE, "w", encoding="utf-8") as f:
        json.dump(s, f, indent=2, ensure_ascii=False)
    with open(LUA, "w", encoding="utf-8") as f:
        f.write("-- gerado por settings.py\nreturn " + lua(out) + "\n")
    with open(STYLE, "w", encoding="utf-8") as f:
        json.dump(style_out, f, indent=2)


def reload_hypr():
    try:
        subprocess.run(["hyprctl", "reload"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "get"
    s = load()
    if cmd == "get":
        print(json.dumps(s, ensure_ascii=False))
        return
    
    if (cmd == "set" or cmd == "apply") and len(a) >= 3:
        k, v = a[1], json.loads(a[2])
        if k == "binds" and isinstance(v, dict):
            s["binds"].update({x: y for x, y in v.items() if x in s["binds"]})
        elif k in s and k != "binds":
            want = type(DEFAULTS[k])
            if want is float:
                v = float(v)
            elif want is int:
                v = int(round(float(v)))
            elif want is bool:
                v = bool(v)
            elif want is str:
                v = str(v)
            s[k] = v
        else:
            sys.exit("chave desconhecida: " + k)
    elif cmd == "reset":
        s = copy.deepcopy(DEFAULTS)
    elif cmd != "apply":
        sys.exit(__doc__)
        
    write_all(s)
    if cmd == "set":
        reload_hypr()


if __name__ == "__main__":
    main()
