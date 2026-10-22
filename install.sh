#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BIN_DIR="$HOME/.local/bin"
# Adiciona esta lista no início do ~/dotfiles/install.sh

DEPS=("hyprland" "qs" "kitty" "wofi" "mako" "matugen" "waybar" "fastfetch" "btop")

echo "-> A verificar dependências essenciais..."
MISSING=()

for cmd in "${DEPS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING+=("$cmd")
    fi
done

if [ ${#MISSING[@]} -ne 0 ]; then
    echo "   [!] AVISO: As seguintes dependências não foram encontradas:"
    for pkg in "${MISSING[@]}"; do
        echo "       - $pkg"
    done
    echo "   Instala-as através do gestor de pacotes do teu sistema antes de iniciar a sessão."
else
    echo "   [✓] Todas as dependências essenciais estão instaladas!"
fi

echo "=== A instalar Dotfiles ==="

# 1. Criar diretorias essenciais no utilizador
mkdir -p "$XDG_CONFIG_HOME"
mkdir -p "$BIN_DIR"

# 2. Vincular o executável do backend
if [ -f "$DOTFILES_DIR/bin/nyos-settings" ]; then
    echo "-> A vincular executável backend em $BIN_DIR/nyos-settings..."
    chmod +x "$DOTFILES_DIR/bin/nyos-settings"
    ln -sf "$DOTFILES_DIR/bin/nyos-settings" "$BIN_DIR/nyos-settings"
fi

# 3. Vincular automaticamente todas as pastas de configuração para ~/.config
echo "-> A vincular pastas de configuração em $XDG_CONFIG_HOME..."

for config_dir in "$DOTFILES_DIR/config"/*; do
    if [ -d "$config_dir" ]; then
        folder_name="$(basename "$config_dir")"
        echo "   • Vinculando: $folder_name"
        
        # Fazer backup de pastas existentes que não sejam symlinks
        if [ -d "$XDG_CONFIG_HOME/$folder_name" ] && [ ! -L "$XDG_CONFIG_HOME/$folder_name" ]; then
            mv "$XDG_CONFIG_HOME/$folder_name" "$XDG_CONFIG_HOME/${folder_name}.bak"
        fi
        
        ln -sfT "$config_dir" "$XDG_CONFIG_HOME/$folder_name"
    fi
done

echo "=== Instalação concluída com sucesso! ==="
