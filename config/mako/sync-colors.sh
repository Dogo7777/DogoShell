#!/bin/bash

# Ler cores do hyprland.lua
HYPR_CONFIG="$HOME/.config/hypr/hyprland.lua"
WALLPAPER_CONFIG="$HOME/.config/hypr/wallpaper-colors.lua"

# Tenta carregar wallpaper-colors.lua primeiro
# Tenta carregar wallpaper-colors.lua primeiro
if [ -f "$WALLPAPER_CONFIG" ]; then
PRIMARY=$(grep -oP 'primary\s*=\s*"?\K[^"]+(?=")' "$WALLPAPER_CONFIG" | head -1)
SECONDARY=$(grep -oP 'secondary\s*=\s*"?\K[^"]+(?=")' "$WALLPAPER_CONFIG" | head -1)
fi

# Se não encontrou, tenta hyprland.lua
if [ -z "$PRIMARY" ]; then
    PRIMARY=$(grep -oP "primary = \"?\K[^\"]+(?=\")" "$HYPR_CONFIG" | head -1)
    SECONDARY=$(grep -oP "secondary = \"?\K[^\"]+(?=\")" "$HYPR_CONFIG" | head -1)
fi

# Fallback
PRIMARY="${PRIMARY:-rgba(33ccffee)}"
SECONDARY="${SECONDARY:-rgba(00ff99ee)}"

# Converter rgba para hex (remove rgba e pega os 6 primeiros chars)
HEX_PRIMARY="#${PRIMARY:5:6}"
HEX_SECONDARY="#${SECONDARY:5:6}"

# Criar config do mako com as cores
cat > ~/.config/mako/config <<EOF
# Mako config com cores dinâmicas
width=300
height=100
border-radius=20
border-size=2
padding=16
margin=12
background-color=#000000aa
text-color=#ffffff
font=monospace 10

[urgency=low]
background-color=$HEX_PRIMARY
border-color=$HEX_PRIMARY

[urgency=normal]
background-color=$HEX_PRIMARY
border-color=$HEX_PRIMARY

[urgency=critical]
background-color=$HEX_SECONDARY
border-color=$HEX_SECONDARY
EOF
