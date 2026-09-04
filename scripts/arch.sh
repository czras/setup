#!/usr/bin/env bash
set -e

echo "==> Running Arch Linux specific setup..."

# 1. System packages & Locales
echo "==> Upgrading system and installing core packages via pacman..."
sudo pacman -S --needed --noconfirm \
    base-devel nano nano-syntax-highlighting less tinyxxd \
    git tk xorg-fonts-100dpi openssh curl wget unzip zip \
    jq ripgrep fd fzf tree sqlite github-cli mise uv sops age \
    corepack

echo 'include "/usr/share/nano/*.nanorc"' | sudo tee -a /etc/nanorc > /dev/null
echo 'include "/usr/share/nano/extra/*.nanorc"' | sudo tee -a /etc/nanorc > /dev/null

sudo sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen

# 2. AUR Helper & OpenCode Installation
if ! command -v paru &> /dev/null; then
    echo "==> Installing Paru (AUR Helper)..."
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
fi

echo "==> Installing OpenCode via paru..."
paru -S --needed --noconfirm wish opencode-bin
