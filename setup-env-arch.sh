#!/usr/bin/env bash
set -e

# Resolve script directory dynamically (works regardless of current working directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_USER="${WSL_DEV_USER:-$(whoami)}"
USER_HOME=$(eval echo "~$TARGET_USER")

echo "=== Arch Linux Dev Environment Setup for [$TARGET_USER] ==="

# 1. System packages & Locales
echo "==> Upgrading system and installing core packages..."
sudo pacman -S --needed --noconfirm \
    base-devel nano nano-syntax-highlighting less tinyxxd \
    git tk xorg-fonts-100dpi openssh curl wget unzip zip \
    jq ripgrep fd fzf tree sqlite github-cli mise uv sops age

echo 'include "/usr/share/nano/*.nanorc"' | sudo tee -a /etc/nanorc > /dev/null
echo 'include "/usr/share/nano/extra/*.nanorc"' | sudo tee -a /etc/nanorc > /dev/null

sudo sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen

# 2. SSH & Git Credentials
if [ ! -f "$USER_HOME/.ssh/id_ed25519" ]; then
    echo "==> Generating SSH key for $TARGET_USER..."
    ssh-keygen -t ed25519 -C "andras.czigany.13@gmail.com" -f "$USER_HOME/.ssh/id_ed25519" -N ""
    eval "$(ssh-agent -s)"
    ssh-add "$USER_HOME/.ssh/id_ed25519"
    echo "Your new public key:"
    cat "$USER_HOME/.ssh/id_ed25519.pub"
fi

git config --global user.name "András Czigány"
git config --global user.email "andras.czigany.13@gmail.com"

if ! gh auth status &>/dev/null; then
    echo "==> Authenticating GitHub CLI..."
    gh auth login --scopes workflow
    gh auth setup-git
fi

# 3. Development Runtimes
echo "==> Configuring runtime managers (mise & corepack)..."
eval "$(mise activate bash)"
corepack enable
corepack prepare pnpm@latest --activate
mise use --global node@24
mise use --global python@3.14

uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v1.0.0
uv tool update-shell

# 4. AUR Helper & OpenCode Installation
mkdir -p "$USER_HOME/workspace"
if ! command -v paru &> /dev/null; then
    echo "==> Installing Paru (AUR Helper)..."
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    rm -rf /tmp/paru
fi

echo "==> Installing OpenCode..."
paru -S --needed --noconfirm wish opencode-bin

# 5. SOPS + Age Encrypted Secret Setup
mkdir -p "$USER_HOME/.config/opencode"
mkdir -p "$USER_HOME/.config/sops/age"

AGE_KEY_FILE="$USER_HOME/.config/sops/age/keys.txt"
ENC_FILE="$USER_HOME/.config/opencode/opencode.env.enc"
TMP_ENV="/tmp/opencode_setup.env"

echo ""
echo "=== Encrypted API Key Configuration (SOPS + Age) ==="

if [ ! -f "$AGE_KEY_FILE" ]; then
    echo "==> Generating new Age key pair at $AGE_KEY_FILE..."
    age-keygen -o "$AGE_KEY_FILE"
    chmod 600 "$AGE_KEY_FILE"
fi

PUBKEY=$(age-keygen -y "$AGE_KEY_FILE")
echo "Using Age Public Key: $PUBKEY"

declare -A CURRENT_KEYS
if [ -f "$ENC_FILE" ]; then
    echo "==> Found existing encrypted file. Decrypting defaults..."
    eval "$(SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" sops --decrypt --input-type dotenv --output-type dotenv "$ENC_FILE" 2>/dev/null)" || true
    CURRENT_KEYS["ANTHROPIC_API_KEY"]="$ANTHROPIC_API_KEY"
    CURRENT_KEYS["GITHUB_PAT"]="$GITHUB_PAT"
    CURRENT_KEYS["GEMINI_API_KEY"]="$GEMINI_API_KEY"
    CURRENT_KEYS["DEEPSEEK_API_KEY"]="$DEEPSEEK_API_KEY"
    CURRENT_KEYS["GROQ_API_KEY"]="$GROQ_API_KEY"
    CURRENT_KEYS["KILO_API_KEY"]="$KILO_API_KEY"
    CURRENT_KEYS["ORCAROUTER_API_KEY"]="$ORCAROUTER_API_KEY"
    CURRENT_KEYS["AION_API_KEY"]="$AION_API_KEY"
    CURRENT_KEYS["SAMBANOVA_API_KEY"]="$SAMBANOVA_API_KEY"
fi

prompt_key() {
    local var_name=$1
    local prompt_text=$2
    local current_val="${CURRENT_KEYS[$var_name]}"
    local display_default=""

    if [ -n "$current_val" ]; then
        display_default=" [Current: ${current_val:0:6}...${current_val: -4}]"
    fi

    read -sp "$prompt_text$display_default (Press Enter to keep current): " value
    echo ""

    local final_val="${value:-$current_val}"
    if [ -n "$final_val" ]; then
        echo "$var_name=\"$final_val\"" >> "$TMP_ENV"
    fi
}

> "$TMP_ENV"
prompt_key "ANTHROPIC_API_KEY" "Enter Anthropic (Claude) API Key"
prompt_key "GITHUB_PAT" "Enter GitHub PAT (MCP & GitHub Models)"
prompt_key "GEMINI_API_KEY" "Enter Gemini API Key"
prompt_key "DEEPSEEK_API_KEY" "Enter DeepSeek API Key"
prompt_key "GROQ_API_KEY" "Enter Groq API Key"
prompt_key "KILO_API_KEY" "Enter Kilo API Key"
prompt_key "ORCAROUTER_API_KEY" "Enter OrcaRouter API Key"
prompt_key "AION_API_KEY" "Enter Aion API Key"
prompt_key "SAMBANOVA_API_KEY" "Enter SambaNova API Key"

if [ -s "$TMP_ENV" ]; then
    SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" sops --encrypt \
        --age "$PUBKEY" \
        --input-type dotenv \
        --output-type dotenv \
        "$TMP_ENV" > "$ENC_FILE"
    chmod 600 "$ENC_FILE"
    echo "==> Encrypted credentials saved to $ENC_FILE"
fi
rm -f "$TMP_ENV"

# 6. Copy OpenCode Configuration File
CONFIG_SRC="$SCRIPT_DIR/config/opencode.jsonc"
CONFIG_DEST="$USER_HOME/.config/opencode/opencode.jsonc"

if [ -f "$CONFIG_SRC" ]; then
    echo "==> Copying $CONFIG_SRC to $CONFIG_DEST..."
    cp "$CONFIG_SRC" "$CONFIG_DEST"
else
    echo "Error: Configuration file not found at $CONFIG_SRC!" >&2
    exit 1
fi

# 7. Shell profile configuration
BASHRC="$USER_HOME/.bashrc"
if ! grep -q "opencode-agent" "$BASHRC"; then
    cat >> "$BASHRC" <<'EOF'

export VISUAL=nano
export EDITOR=nano
eval "$(mise activate bash)"

opencode-agent() {
    local age_key="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    local enc_file="$HOME/.config/opencode/opencode.env.enc"

    if [ ! -f "$age_key" ]; then
        echo "Error: Age key not found at $age_key" >&2
        return 1
    fi

    if [ ! -f "$enc_file" ]; then
        echo "Error: Encrypted credentials file not found at $enc_file" >&2
        return 1
    fi

    env $(SOPS_AGE_KEY_FILE="$age_key" sops --decrypt --input-type dotenv --output-type dotenv "$enc_file") \
        GIT_AUTHOR_NAME="OpenCode" \
        GIT_AUTHOR_EMAIL="andras.czigany.13+agent@gmail.com" \
        GIT_COMMITTER_NAME="OpenCode" \
        GIT_COMMITTER_EMAIL="andras.czigany.13+agent@gmail.com" \
        opencode "$@"
}
EOF
fi

echo "=== Setup complete for $TARGET_USER! Restart your shell or run 'source ~/.bashrc' ==="
