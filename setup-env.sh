#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${WSL_DEV_USER:-$(whoami)}"
USER_HOME=$(eval echo "~$TARGET_USER")
WORKSPACE_DIR="$USER_HOME/workspace"

echo "=== Linux Dev Environment Setup for [$TARGET_USER] ==="

# Load Git configuration
GIT_CONFIG_FILE="$SCRIPT_DIR/config/git.env"
if [ -f "$GIT_CONFIG_FILE" ]; then
    source "$GIT_CONFIG_FILE"
else
    echo "Warning: $GIT_CONFIG_FILE not found. Using fallback defaults."
    GIT_NAME="${GIT_NAME:-András Czigány}"
    GIT_EMAIL="${GIT_EMAIL:-andras.czigany.13@gmail.com}"
    AGENT_EMAIL="${AGENT_EMAIL:-andras.czigany.13+agent@gmail.com}"
fi

# 1. Distro Detection & Module Invocation
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="$ID"
else
    echo "Error: /etc/os-release not found. Cannot determine distribution." >&2
    exit 1
fi

echo "==> Detected distribution: $DISTRO_ID"

case "$DISTRO_ID" in
    arch|archarm)
        ARCH_SCRIPT="$SCRIPT_DIR/scripts/arch.sh"
        if [ -f "$ARCH_SCRIPT" ]; then
            chmod +x "$ARCH_SCRIPT"
            "$ARCH_SCRIPT"
        else
            echo "Error: $ARCH_SCRIPT not found!" >&2
            exit 1
        fi
        ;;
    *)
        echo "Error: Distribution '$DISTRO_ID' is currently unsupported. Only Arch Linux is implemented." >&2
        exit 1
        ;;
esac

# 2. SSH Key Provisioning & GitHub Interactive Pause
echo "==> Configuring SSH Keys & Git Identity..."
mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"

SSH_KEY_PATH="$USER_HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "==> Generating new ED25519 SSH key pair..."
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY_PATH" -N ""
fi

# Ensure ssh-agent is running and key is added
eval "$(ssh-agent -s)" > /dev/null
ssh-add "$SSH_KEY_PATH" 2>/dev/null || true

echo ""
echo "====================================================================="
echo "                  ATTENTION: GITHUB SSH KEY SETUP                    "
echo "====================================================================="
echo "Below is your SSH Public Key for this container ($TARGET_USER):"
echo ""
cat "${SSH_KEY_PATH}.pub"
echo ""
echo "Please add this key to your GitHub account now:"
echo "  -> https://github.com/settings/keys"
echo "====================================================================="
echo ""
read -p "Press [ENTER] once you have added the key to GitHub to continue..."

# Set global git config
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"

# GitHub CLI Auth Check
if ! gh auth status &>/dev/null; then
    echo "==> Authenticating GitHub CLI..."
    gh auth login --scopes workflow
    gh auth setup-git
fi

# 3. Workspace Directory & Git Repo Batch Cloning
echo "==> Setting up workspace at $WORKSPACE_DIR..."
mkdir -p "$WORKSPACE_DIR"

REPOS_FILE="$SCRIPT_DIR/config/repos.txt"
if [ -f "$REPOS_FILE" ]; then
    echo "==> Processing workspace repositories from $REPOS_FILE..."
    while IFS= read -r repo_url || [ -n "$repo_url" ]; do
        repo_url="$(echo "$repo_url" | xargs)"
        [[ -z "$repo_url" || "$repo_url" =~ ^# ]] && continue

        repo_name=$(basename "$repo_url" .git)
        target_path="$WORKSPACE_DIR/$repo_name"

        if [ -d "$target_path" ]; then
            echo "  -> Repository '$repo_name' already exists at $target_path. Skipping."
        else
            echo "  -> Cloning $repo_url into $target_path..."
            git clone "$repo_url" "$target_path"
        fi
    done < "$REPOS_FILE"
fi

# 4. Universal Development Runtimes
echo "==> Configuring runtime managers (mise & corepack)..."
eval "$(mise activate bash)"
corepack enable
corepack prepare pnpm@latest --activate
mise use --global node@24
mise use --global python@3.14

uv tool update-shell

# 5. SOPS + Age Encrypted Secret Setup
mkdir -p "$USER_HOME/.config/opencode"
mkdir -p "$USER_HOME/.config/sops/age"

AGE_KEY_FILE="$USER_HOME/.config/sops/age/keys.txt"
ENC_FILE="$USER_HOME/.config/opencode/opencode.env.enc"
TMP_ENV="/tmp/opencode_setup.env"
REPO_OPENCODE_CONFIG_ENV_FILE="$SCRIPT_DIR/config/opencode.env.enc"
REPO_AGE_KEY_FILE="$SCRIPT_DIR/config/keys.txt"

yes | cp -f $REPO_OPENCODE_CONFIG_ENV_FILE $ENC_FILE 2>/dev/null || true
yes | cp -f $REPO_AGE_KEY_FILE $AGE_KEY_FILE 2>/dev/null || true

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
fi

# 7. Shell Profile Configuration
BASHRC="$USER_HOME/.bashrc"
if ! grep -q "opencode-agent" "$BASHRC"; then
    cat >> "$BASHRC" <<EOF

export VISUAL=nano
export EDITOR=nano
eval "\$(mise activate bash)"

opencode-agent() {
    local age_key="\${SOPS_AGE_KEY_FILE:-\$HOME/.config/sops/age/keys.txt}"
    local enc_file="\$HOME/.config/opencode/opencode.env.enc"

    if [ ! -f "\$age_key" ]; then
        echo "Error: Age key not found at \$age_key" >&2
        return 1
    fi

    if [ ! -f "\$enc_file" ]; then
        echo "Error: Encrypted credentials file not found at \$enc_file" >&2
        return 1
    fi

    env \$(SOPS_AGE_KEY_FILE="\$age_key" sops --decrypt --input-type dotenv --output-type dotenv "\$enc_file") \
        GIT_AUTHOR_NAME="OpenCode" \
        GIT_AUTHOR_EMAIL="$AGENT_EMAIL" \
        GIT_COMMITTER_NAME="OpenCode" \
        GIT_COMMITTER_EMAIL="$AGENT_EMAIL" \
        opencode "\$@"
}
EOF
fi

echo "=== Setup complete for $TARGET_USER! Restart your shell or run 'source ~/.bashrc' ==="
