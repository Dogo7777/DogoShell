#!/usr/bin/env python3
"""Faz os shells do Quickshell obedecerem o "formato" (redondo/suave/quadrado).
Uso:  shellstyle.py [arquivo.qml ...]
Padrão: island, launcher, power, settings em ~/.config/quickshell/*/shell.qml
- cria backup arquivo.qml.bak na primeira vez
- injeta um leitor de ~/.config/quickshell/style.json (propriedade root.rs)
- multiplica cada `radius:` por root.rs  (rs=1 redondo, 0.5 suave, 0 quadrado)
É idempotente: pode rodar de novo depois de substituir um shell.
"""
import os, re, shutil, sys

HOME = os.path.expanduser("~")
DEFAULT = [HOME + "/.config/quickshell/%s/shell.qml" % n for n in ("island", "launcher", "power", "settings")]
MARK = "// [shellstyle]"
INJECT = """    %s formato (redondo/quadrado) vem de ~/.config/quickshell/style.json
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/style.json"
        watchChanges: true
        printErrors: false
        adapter: JsonAdapter { id: styleAd; property real scale: 1.0 }
    }
    readonly property real rs: styleAd.scale
""" % MARK

RAD = re.compile(r"(?<![\w.])radius:\s*((?:[^;}\n/]|/(?!/))+?)(\s*(?:;|\}|//|$))")


def patch(path):
    if not os.path.exists(path):
        return "não existe"
    src = open(path, encoding="utf-8").read()
    if not os.path.exists(path + ".bak"):
        shutil.copy2(path, path + ".bak")
    lines = src.split("\n")
    out, injected, n = [], MARK in src, 0
    for line in lines:
        out.append(line)
        if not injected and re.match(r"^\s*id:\s*root\s*$", line):
            out.append(INJECT.rstrip("\n"))
            injected = True
    if not injected:
        return "sem `id: root` — não consegui injetar"
    res = []
    for line in out:
        if "property" not in line and "root.rs" not in line and "radius:" in line:
            new = RAD.sub(lambda m: m.group(0) if ".radius" in m.group(1)
                          else "radius: (%s) * root.rs%s" % (m.group(1).strip(), m.group(2)), line)
            if new != line:
                n += 1
            line = new
        res.append(line)
    open(path, "w", encoding="utf-8").write("\n".join(res))
    return "ok (%d radius ajustados)" % n


for p in (sys.argv[1:] or DEFAULT):
    print(os.path.relpath(p, HOME) if p.startswith(HOME) else p, "->", patch(p))
