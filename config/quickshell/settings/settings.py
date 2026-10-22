#!/usr/bin/env python3
"""Backend de configurações do Hyprland e Quickshell com telemetria resiliente."""
import copy, json, os, re, subprocess, sys, platform, socket, getpass

HOME = os.environ.get("HOME", os.path.expanduser("~"))
STORE = os.path.join(HOME, ".config/hypr/settings.json")
LUA = os.path.join(HOME, ".config/hypr/settings.lua")
STYLE = os.path.join(HOME, ".config/quickshell/style.json")

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
    "bar_mode": "island",
    "bar_position": "top",
    "bar_full_width": False,
    "bar_floating": True,
    "bar_margin": 6,
    "bar_opacity": 0.55,
    "show_clock_date": False,
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
        if os.path.exists(STORE):
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

def reload_services(s, key_changed):
    rounding, _ = SHAPES.get(s.get("shape", "round"), SHAPES["round"])
    border_sz = int(s.get("border", 2))
    gaps_in = int(s.get("gaps_in", 5))
    gaps_out = int(s.get("gaps_out", 10))
    gaps_top = int(s.get("gaps_top", 45))

    kw_map = {
        "shape": [["decoration:rounding", str(rounding)]],
        "border": [["general:border_size", str(border_sz)]],
        "gaps_in": [["general:gaps_in", str(gaps_in)]],
        "gaps_out": [["general:gaps_out", f"{gaps_top} {gaps_out} {gaps_out} {gaps_out}"]],
        "gaps_top": [["general:gaps_out", f"{gaps_top} {gaps_out} {gaps_out} {gaps_out}"]],
        "blur": [["decoration:blur:enabled", "1" if s.get("blur") else "0"]],
        "blur_size": [["decoration:blur:size", str(int(s.get("blur_size", 6)))]],
        "blur_passes": [["decoration:blur:passes", str(int(s.get("blur_passes", 2)))]],
        "shadow": [
            ["decoration:shadow:enabled", "1" if s.get("shadow") else "0"],
            ["decoration:drop_shadow", "1" if s.get("shadow") else "0"]
        ],
        "opacity_active": [["decoration:active_opacity", str(float(s.get("opacity_active", 1.0)))]],
        "opacity_inactive": [["decoration:inactive_opacity", str(float(s.get("opacity_inactive", 1.0)))]],
        "layout": [["general:layout", str(s.get("layout", "dwindle"))]],
        "sensitivity": [["input:sensitivity", str(float(s.get("sensitivity", 0.0)))]],
        "natural_scroll": [["input:touchpad:natural_scroll", "1" if s.get("natural_scroll") else "0"]],
        "focus_mouse": [["input:follow_mouse", "1" if s.get("focus_mouse", True) else "0"]],
    }

    if key_changed in kw_map:
        for cmd_args in kw_map[key_changed]:
            try:
                subprocess.run(["hyprctl", "keyword"] + cmd_args, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception:
                pass

    if key_changed in set(kw_map.keys()):
        try:
            subprocess.run(["hyprctl", "reload"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

    if key_changed.startswith("bar_") or key_changed in ("show_clock_date", "shape"):
        try:
            cmd = "ps aux | grep -E 'quickshell.*island|qs.*island' | grep -v grep | grep -v settings | awk '{print $2}'"
            pids = subprocess.check_output(cmd, shell=True, text=True).strip().split()
            for pid in pids:
                if pid:
                    subprocess.run(["kill", "-9", pid], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.Popen(["qs", "-c", "island"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        except Exception:
            pass

def get_cpu():
    try:
        if os.path.exists("/proc/cpuinfo"):
            with open("/proc/cpuinfo", "r") as f:
                for line in f:
                    if "model name" in line:
                        name = line.split(":")[1].strip()
                        return re.sub(r"\s+", " ", name)
    except Exception:
        pass
    try:
        out = subprocess.check_output("lscpu", text=True)
        for line in out.splitlines():
            if "Model name:" in line:
                return line.split(":")[1].strip()
    except Exception:
        pass
    return platform.processor() or "Intel / AMD Processor"

def get_gpu():
    try:
        out = subprocess.check_output("lspci | grep -E 'VGA|3D|Display'", shell=True, text=True)
        lines = [l.strip() for l in out.strip().split("\n") if l.strip()]
        if lines:
            gpu_str = lines[0].split(":", 2)[-1].strip()
            gpu_str = re.sub(r"^(VGA compatible controller|3D controller):\s*", "", gpu_str)
            return re.sub(r"\[.*?\]", "", gpu_str).strip() or gpu_str
    except Exception:
        pass
    return "AMD / NVIDIA / Intel GPU"

def get_ram():
    try:
        with open("/proc/meminfo", "r") as f:
            mem = {line.split(":")[0].strip(): line.split(":")[1].strip() for line in f if ":" in line}
        total_kb = int(mem.get("MemTotal", "0 kB").split()[0])
        avail_kb = int(mem.get("MemAvailable", "0 kB").split()[0])
        used_kb = total_kb - avail_kb
        total_gb = total_kb / (1024 * 1024)
        used_gb = used_kb / (1024 * 1024)
        pct = (used_kb / total_kb) * 100 if total_kb > 0 else 0
        return f"{used_gb:.1f} GB / {total_gb:.1f} GB ({pct:.0f}%)"
    except Exception:
        return "16 GB RAM"

def get_uptime():
    try:
        if os.path.exists("/proc/uptime"):
            with open("/proc/uptime", "r") as f:
                seconds = float(f.readline().split()[0])
                hours = int(seconds // 3600)
                minutes = int((seconds % 3600) // 60)
                if hours > 0:
                    return f"{hours}h {minutes}m"
                return f"{minutes} min"
    except Exception:
        pass
    return "Ativo"

def get_distro():
    try:
        if os.path.exists("/etc/os-release"):
            with open("/etc/os-release", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("PRETTY_NAME="):
                        return line.split("=")[1].strip().strip('"')
    except Exception:
        pass
    return "Linux"

def get_hypr_ver():
    try:
        out = subprocess.check_output(["hyprctl", "version"], text=True)
        for line in out.splitlines():
            if "Tag:" in line:
                return line.replace("Tag:", "").strip()
            if "version:" in line:
                return line.replace("version:", "").strip()
        return out.strip().splitlines()[0]
    except Exception:
        return "Hyprland"

def get_qs_ver():
    try:
        return subprocess.check_output(["qs", "--version"], text=True).strip()
    except Exception:
        try:
            return subprocess.check_output(["quickshell", "--version"], text=True).strip()
        except Exception:
            return "Quickshell"

def get_avatar():
    for p in [os.path.join(HOME, ".face"), os.path.join(HOME, ".face.icon"), os.path.join(HOME, ".config/face.png")]:
        if os.path.exists(p):
            return "file://" + p
    return ""

def get_sysinfo():
    user = getpass.getuser() if hasattr(getpass, 'getuser') else "luis"
    hostname = socket.gethostname() if hasattr(socket, 'gethostname') else "fedora"

    return {
        "user": user,
        "hostname": hostname,
        "distro": get_distro(),
        "kernel": platform.release(),
        "uptime": get_uptime(),
        "hypr_ver": get_hypr_ver(),
        "qs_ver": get_qs_ver(),
        "cpu": get_cpu(),
        "gpu": get_gpu(),
        "ram": get_ram(),
        "avatar": get_avatar(),
        "dotfiles_ver": "v2.0 (HyprAtomic)",
    }

def run_action(act):
    if act == "check_updates":
        cmd = "echo '=== Verificando Atualizações ==='; sudo dnf check-update || true; flatpak update; read -p 'Pressione Enter para fechar...'"
        terms = ["ptyxis", "foot", "kitty", "ghostty", "alacritty", "wezterm", "gnome-terminal"]
        term_cmd = None
        for t in terms:
            if subprocess.call(["which", t], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
                term_cmd = t
                break
        if term_cmd:
            subprocess.Popen([term_cmd, "-e", "bash", "-c", cmd])
        else:
            subprocess.Popen(["xdg-terminal-exec", "bash", "-c", cmd])
    elif act == "open_repo":
        subprocess.Popen(["xdg-open", "https://github.com/dogo7777"])
    elif act == "reload_all":
        subprocess.run(["hyprctl", "reload"], check=False)
        try:
            cmd = "ps aux | grep -E 'quickshell.*island|qs.*island' | grep -v grep | grep -v settings | awk '{print $2}'"
            pids = subprocess.check_output(cmd, shell=True, text=True).strip().split()
            for pid in pids:
                if pid:
                    subprocess.run(["kill", "-9", pid], check=False)
            subprocess.Popen(["qs", "-c", "island"], start_new_session=True)
        except Exception:
            pass

def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "get"
    
    if cmd == "sysinfo":
        print(json.dumps(get_sysinfo(), ensure_ascii=False))
        return
    if cmd == "action" and len(a) >= 2:
        run_action(a[1])
        return

    s = load()
    if cmd == "get":
        print(json.dumps(s, ensure_ascii=False))
        return
    
    k = ""
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
    elif cmd == "reset":
        s = copy.deepcopy(DEFAULTS)
        
    write_all(s)
    if cmd in ("set", "apply") and k:
        reload_services(s, k)

if __name__ == "__main__":
    main()
