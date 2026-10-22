#!/usr/bin/env python3
import os
import json

apps = []
dirs = ["/usr/share/applications", os.path.expanduser("~/.local/share/applications")]

for d in dirs:
    if not os.path.exists(d): continue
    for f in os.listdir(d):
        if f.endswith(".desktop"):
            try:
                with open(os.path.join(d, f), 'r', encoding='utf-8') as file:
                    content = file.read()
                    
                if "NoDisplay=true" in content: continue
                
                # split("=", 1) impede que o python quebre arquivos que têm "=" no meio do comando
                name_lines = [l.split("=", 1)[1] for l in content.split("\n") if l.startswith("Name=")]
                if not name_lines: continue
                name = name_lines[0].strip()
                
                exec_lines = [l.split("=", 1)[1] for l in content.split("\n") if l.startswith("Exec=")]
                if not exec_lines: continue
                exec_cmd = exec_lines[0].split("%")[0].strip()
                
                icon_lines = [l.split("=", 1)[1] for l in content.split("\n") if l.startswith("Icon=")]
                icon = icon_lines[0].strip() if icon_lines else "application-x-executable"
                
                apps.append({"name": name, "exec": exec_cmd, "icon": icon})
            except Exception:
                pass

# Remove duplicatas
unique_apps = {app['name']: app for app in apps}.values()
print(json.dumps(sorted(list(unique_apps), key=lambda x: x['name'].lower())))
