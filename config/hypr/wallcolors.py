#!/usr/bin/env python3
"""Gera as cores de borda do Hyprland a partir do wallpaper.

Uso:  wallcolors.py /caminho/do/wallpaper.png [--no-reload]
Saída: ~/.config/hypr/wallpaper-colors.lua  (e roda `hyprctl reload`)
Requer: python3-pillow
"""
import colorsys
import os
import subprocess
import sys

from PIL import Image

OUT = os.path.expanduser("~/.config/hypr/wallpaper-colors.lua")


def vivid_colors(path):
    img = Image.open(path).convert("RGB")
    img.thumbnail((200, 200))
    q = img.quantize(colors=16, method=Image.Quantize.MEDIANCUT)
    pal = q.getpalette()
    cands = []
    for count, idx in q.getcolors():
        r, g, b = pal[idx * 3: idx * 3 + 3]
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.25 or v < 0.30:          # ignora cinzas e tons muito escuros
            continue
        cands.append((count ** 0.5 * s * v, h, s, v))
    cands.sort(reverse=True)
    return cands


def boost(h, s, v):
    """Deixa a cor viva o bastante para destacar uma borda fina."""
    s = max(s, 0.60)
    v = max(v, 0.85)
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return "%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    cands = vivid_colors(path)

    if cands:
        _, h1, s1, v1 = cands[0]
        # segunda cor: a mais forte com matiz diferente; senão, gira o matiz
        second = next((c for c in cands[1:] if min(abs(c[1] - h1), 1 - abs(c[1] - h1)) > 0.08), None)
        if second:
            _, h2, s2, v2 = second
        else:
            h2, s2, v2 = (h1 + 0.10) % 1.0, s1, v1
    else:  # wallpaper em tons de cinza
        h1, s1, v1 = 0.0, 0.0, 0.9
        h2, s2, v2 = 0.0, 0.0, 0.6

    c1 = boost(h1, s1, v1) if cands else "e6e6e6"
    c2 = boost(h2, s2, v2) if cands else "999999"

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write("-- gerado por wallcolors.py a partir de: %s\n" % path)
        f.write("return {\n")
        f.write('    primary   = "rgba(%see)",\n' % c1)
        f.write('    secondary = "rgba(%see)",\n' % c2)
        f.write("}\n")

    # Cores do mako (notificações): incluídas pelo ~/.config/mako/config
    mako_dir = os.path.expanduser("~/.config/mako")
    os.makedirs(mako_dir, exist_ok=True)
    with open(os.path.join(mako_dir, "colors"), "w") as f:
        f.write("border-color=#%s\n" % c1)
        f.write("progress-color=over #%s\n" % c2)

    print("primary=#%s secondary=#%s" % (c1, c2))

    # Cores do Powerlevel10k (lidas por ~/.p10k.zsh)
    r, g, b = (int(c1[i:i + 2], 16) for i in (0, 2, 4))
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    cache_dir = os.path.expanduser("~/.cache")
    os.makedirs(cache_dir, exist_ok=True)
    with open(os.path.join(cache_dir, "wallcolors.zsh"), "w") as f:
        f.write("typeset -g WALL_ACCENT='#%s'\n" % c1)
        f.write("typeset -g WALL_ACCENT2='#%s'\n" % c2)
        f.write("typeset -g WALL_FG='%s'\n" % ("#000000" if lum > 150 else "#ffffff"))

    # Cor de destaque da ilha em Quickshell
    qs_dir = os.path.expanduser("~/.config/quickshell/island")
    os.makedirs(qs_dir, exist_ok=True)
    with open(os.path.join(qs_dir, "colors.json"), "w") as f:
        f.write('{"accent": "#%s", "accent2": "#%s"}\n' % (c1, c2))

    # Cor de destaque do Waybar (importada no style.css)
    wb_dir = os.path.expanduser("~/.config/waybar")
    os.makedirs(wb_dir, exist_ok=True)
    with open(os.path.join(wb_dir, "colors.css"), "w") as f:
        f.write("@define-color accent #%s;\n" % c1)
        f.write("@define-color accent2 #%s;\n" % c2)
    subprocess.run(["pkill", "-SIGUSR2", "waybar"], check=False)

    # Cores do mako (notificações), lidas via include= no config do mako
    mako_dir = os.path.expanduser("~/.config/mako")
    os.makedirs(mako_dir, exist_ok=True)
    with open(os.path.join(mako_dir, "colors"), "w") as f:
        f.write("border-color=#%sff\n" % c1)
        f.write("progress-color=over #%s55\n" % c2)
    try:
        subprocess.run(["makoctl", "reload"], check=False)
    except FileNotFoundError:
        pass

    # Tema do Nautilus / apps GTK4 (libadwaita) e GTK3
    css = """/* gerado por wallcolors.py */
@define-color accent_bg_color #%(c1)s;
@define-color accent_color #%(c1)s;
@define-color accent_fg_color %(fg)s;
@define-color window_bg_color rgba(8, 8, 10, 0.72);
@define-color window_fg_color #f2f2f2;
@define-color view_bg_color rgba(8, 8, 10, 0.35);
@define-color headerbar_bg_color transparent;
@define-color headerbar_backdrop_color transparent;
@define-color headerbar_fg_color #f2f2f2;
@define-color headerbar_border_color transparent;
@define-color sidebar_bg_color transparent;
@define-color sidebar_backdrop_color transparent;
@define-color sidebar_border_color transparent;
@define-color sidebar_shade_color transparent;
@define-color sidebar_fg_color #f2f2f2;
@define-color card_bg_color rgba(255, 255, 255, 0.06);
@define-color popover_bg_color #18181c;
@define-color dialog_bg_color #18181c;

window.background { border: 1px solid alpha(@accent_bg_color, 0.55); }
headerbar, headerbar:backdrop, .top-bar, toolbarview > .top-bar { background: transparent; box-shadow: none; border: none; }
.sidebar-pane, .sidebar-pane:backdrop, .navigation-sidebar, placessidebar, placessidebar list { background: transparent; border: none; box-shadow: none; }
.sidebar-pane, .sidebar-pane:backdrop, .sidebar-pane .navigation-sidebar, .navigation-sidebar, placessidebar, placessidebar list { background: transparent; background-color: transparent; box-shadow: none; border: none; }
.sidebar-pane headerbar, .sidebar-pane headerbar:backdrop { background: transparent; }
separator.spacer, .sidebar-pane separator { background: alpha(white, 0.08); }
window:backdrop .sidebar-pane, window:backdrop .sidebar-pane:backdrop, window:backdrop .navigation-sidebar, window:backdrop placessidebar, window:backdrop placessidebar list, window:backdrop headerbar, window:backdrop .top-bar, window:backdrop toolbarview, window.background:backdrop { background: transparent; background-color: transparent; box-shadow: none; border-color: transparent; }
window:backdrop .navigation-sidebar row:selected { background: alpha(@accent_bg_color, 0.20); }
window:backdrop, window:backdrop * { opacity: 1; filter: none; }
separator { background: alpha(white, 0.08); }
window:backdrop { opacity: 1; }
.navigation-sidebar row { border-radius: 12px; margin: 2px 6px; transition: background 200ms ease; }
.navigation-sidebar row:selected { background: alpha(@accent_bg_color, 0.28); }
.navigation-sidebar row:hover:not(:selected) { background: alpha(white, 0.07); }
.view:selected, row:selected, flowboxchild:selected { background: alpha(@accent_bg_color, 0.30); border-radius: 10px; }
entry, .path-bar button, button { border-radius: 12px; }
popover > contents { border-radius: 16px; border: 1px solid alpha(@accent_bg_color, 0.4); }
""" % {"c1": c1, "fg": "#000000" if lum > 150 else "#ffffff"}
    css3 = """/* gerado por wallcolors.py (GTK3: Thunar etc.) */
@define-color wall_accent #%(c1)s;
@define-color wall_accent_fg %(fg)s;
@define-color theme_selected_bg_color #%(c1)s;
@define-color theme_selected_fg_color %(fg)s;

window, window.background, window.background:backdrop, .background { background-color: rgba(8, 8, 10, 0.72); color: #f2f2f2; }
window.csd, window.background.csd { border-radius: 16px; border: 1px solid alpha(@wall_accent, 0.55); }

menubar, menubar:backdrop, .menubar, .menubar:backdrop, menubar > menuitem, menubar > menuitem:backdrop, decoration, decoration:backdrop, headerbar, headerbar:backdrop, .titlebar, .titlebar:backdrop, toolbar, toolbar:backdrop,
.primary-toolbar, .primary-toolbar:backdrop, statusbar, statusbar:backdrop, actionbar, actionbar:backdrop {
    background: transparent; background-image: none; border: none; box-shadow: none; color: #f2f2f2; }

.sidebar, .sidebar:backdrop, .sidebar .view, .sidebar treeview, .sidebar treeview.view, .sidebar scrolledwindow,
.view, .view:backdrop, iconview, iconview:backdrop, treeview.view, treeview.view:backdrop, scrolledwindow, scrolledwindow:backdrop,
paned, paned:backdrop { background-color: transparent; background-image: none; color: #f2f2f2; border: none; box-shadow: none; }
menubar, menubar > menuitem { color: #f2f2f2; }
menubar > menuitem:hover { background-color: alpha(@wall_accent, 0.30); border-radius: 8px; }
notebook, notebook:backdrop, notebook > stack, notebook > stack:backdrop, notebook > header, notebook > header:backdrop,
notebook > header > tabs, dialog, dialog:backdrop, dialog .dialog-vbox, dialog .dialog-action-area, .dialog-vbox, messagedialog, messagedialog:backdrop,
stack, viewport, grid, box, frame, frame > border { background-color: transparent; background-image: none; box-shadow: none; }
notebook { border: none; }
notebook > header { border: none; }
notebook > header > tabs > tab { color: alpha(#f2f2f2, 0.6); border-radius: 10px; border: none; background-image: none; padding: 4px 12px; }
notebook > header > tabs > tab:checked { color: #ffffff; background-color: alpha(@wall_accent, 0.30); }
notebook > header > tabs > tab:hover:not(:checked) { background-color: alpha(white, 0.07); }
label, label:backdrop { color: #f2f2f2; }
label:disabled, label.dim-label { color: alpha(#f2f2f2, 0.55); }
progressbar trough, levelbar trough { background-color: alpha(white, 0.12); border-radius: 8px; border: none; }
progressbar progress, levelbar block.filled { background-color: @wall_accent; border-radius: 8px; border: none; }
entry selection, label selection, selection { background-color: @wall_accent; color: @wall_accent_fg; }
list, list:backdrop, listbox, listbox:backdrop, list > row, listbox > row, list > row:backdrop, treeview, treeview:backdrop,
textview, textview text, textview:backdrop, textview:backdrop text, .frame, frame > border, scrolledwindow > viewport, cell, .cell, iconview { background-color: transparent; background-image: none; color: #f2f2f2; }
list > row:selected, listbox > row:selected, list > row:selected:backdrop, row:selected, row:selected:backdrop, treeview:selected, treeview:selected:backdrop, cell:selected {
    background-color: alpha(@wall_accent, 0.30); color: #ffffff; border-radius: 10px; }
list > row:hover, listbox > row:hover { background-color: alpha(white, 0.07); border-radius: 10px; }
paned > separator { background-color: alpha(white, 0.06); background-image: none; }

.view:selected, .view:selected:backdrop, iconview:selected, iconview:selected:backdrop,
treeview.view:selected, treeview.view:selected:backdrop, .sidebar row:selected, .sidebar row:selected:backdrop {
    background-color: alpha(@wall_accent, 0.30); color: #ffffff; border-radius: 10px; }
.view:hover, iconview:hover, treeview.view:hover { background-color: alpha(white, 0.07); border-radius: 10px; }

button, button:backdrop, entry, entry:backdrop { border-radius: 12px; background-image: none; background-color: alpha(white, 0.07); border: 1px solid alpha(white, 0.08); box-shadow: none; color: #f2f2f2; }
button:hover { background-color: alpha(white, 0.14); }
button:checked, button:active { background-color: alpha(@wall_accent, 0.35); }
entry:focus { border-color: @wall_accent; }

menu, .menu, popover, popover.background, .popup, tooltip { background-color: #18181c; color: #f2f2f2; border-radius: 14px; border: 1px solid alpha(@wall_accent, 0.4); }
menuitem:hover, modelbutton:hover { background-color: alpha(@wall_accent, 0.30); border-radius: 8px; }
scrollbar slider { background-color: alpha(white, 0.25); border-radius: 8px; }
""" % {"c1": c1, "fg": "#000000" if lum > 150 else "#ffffff"}
    for gv, content in (("gtk-4.0", css), ("gtk-3.0", css3)):
        gd = os.path.expanduser("~/.config/" + gv)
        os.makedirs(gd, exist_ok=True)
        with open(os.path.join(gd, "gtk.css"), "w") as f:
            f.write(content)

    # Cores do hyprlock (importadas pelo hyprlock.conf)
    with open(os.path.expanduser("~/.config/hypr/hyprlock-colors.conf"), "w") as f:
        f.write("$accent = rgba(%sff)\n" % c1)
        f.write("$accent2 = rgba(%sff)\n" % c2)

    # Ícones (pastas recoloridas) — roda em segundo plano se o wallicons.py existir
    wi = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wallicons.py")
    if os.path.exists(wi):
        subprocess.Popen([sys.executable, wi], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if "--no-reload" not in sys.argv:
        for cmd in (["hyprctl", "reload"], ["makoctl", "reload"]):
            try:
                subprocess.run(cmd, check=False)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    main()
