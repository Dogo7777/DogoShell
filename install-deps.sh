#!/usr/bin/env bash
set -e

echo "=== A instalar dependências do sistema ==="

if command -v dnf &> /dev/null; then
    echo "-> Gestor DNF detetado (Fedora)..."
    sudo dnf install -y \
        hyprland \
        quickshell \
        kitty \
        wofi \
        mako \
        waybar \
        fastfetch \
        btop \
        python3 \
        papirus-icon-theme \
        pciutils \
        lm_sensors

elif command -v pacman &> /dev/null; then
    echo "-> Gestor Pacman detetado (Arch Linux)..."
    sudo pacman -S --needed --noconfirm \
        hyprland \
        kitty \
        wofi \
        mako \
        waybar \
        fastfetch \
        btop \
        python \
        papirus-icon-theme \
        pci-utils \
        lm_sensors

else
    echo "[!] Gestor de pacotes não suportado automaticamente. Instala os pacotes manualmente."
fi

echo "=== Dependências instaladas com sucesso! ==="
