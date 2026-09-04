#!/usr/bin/env bash
set -e

# Resolve the user dynamically from /etc/environment or active session
TARGET_USER="${WSL_DEV_USER:-$(whoami)}"
USER_HOME=$(eval echo "~$TARGET_USER")

echo "=== Arch Linux Dev Environment Setup for [$TARGET_USER] ==="

# 1. System packages & Locales
echo "==> Upgrading system and installing core packages..."
sudo pacman -S --needed --noconfirm \
    base-devel nano nano-syntax-highlighting less tinyxxd \
    git tk xorg-fonts-100dpi openssh curl wget unzip zip \
    jq ripgrep fd fzf tree sqlite github-cli mise uv

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

# 5. Interactive Secret Collection
mkdir -p "$USER_HOME/.config/opencode"
ENV_FILE="$USER_HOME/.config/opencode/env"

echo ""
echo "=== API Key Configuration ==="
echo "Press Enter to skip any key you do not want to configure."

prompt_key() {
    local var_name=$1
    local prompt_text=$2
    read -sp "$prompt_text: " value
    echo ""
    if [ -n "$value" ]; then
        echo "export $var_name=\"$value\"" >> "$ENV_FILE"
    fi
}

> "$ENV_FILE" # Reset env file
prompt_key "ANTHROPIC_API_KEY" "Enter Anthropic (Claude) API Key"
prompt_key "GITHUB_PAT" "Enter GitHub PAT (MCP & GitHub Models)"
prompt_key "GEMINI_API_KEY" "Enter Gemini API Key"
prompt_key "DEEPSEEK_API_KEY" "Enter DeepSeek API Key"
prompt_key "GROQ_API_KEY" "Enter Groq API Key"
prompt_key "KILO_API_KEY" "Enter Kilo API Key"
prompt_key "ORCAROUTER_API_KEY" "Enter OrcaRouter API Key"
prompt_key "AION_API_KEY" "Enter Aion API Key"
prompt_key "SAMBANOVA_API_KEY" "Enter SambaNova API Key"

chmod 600 "$ENV_FILE"

# 6. Filtered OpenCode Configuration
echo "==> Writing $USER_HOME/.config/opencode/opencode.jsonc..."
cat <<'EOF' > "$USER_HOME/.config/opencode/opencode.jsonc"
{
  "$schema": "https://opencode.ai/config.json",
  "catalog": {
    "disableDefaultProviders": true
  },
  "mcp": {
    "github": {
      "type": "remote",
      "url": "https://api.githubcopilot.com/mcp/",
      "enabled": true,
      "oauth": false,
      "headers": {
        "Authorization": "Bearer {env:GITHUB_PAT}"
      }
    }
  },
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "{env:ANTHROPIC_API_KEY}"
      },
      "models": {
        "claude-3-5-sonnet-20241022": { "name": "Claude 3.5 Sonnet" }
      }
    },
    "openrouter": {
      "models": {
        "openrouter/free": { "name": "OpenRouter Free model router" }
      }
    },
    "google": {
      "options": {
        "apiKey": "{env:GEMINI_API_KEY}"
      },
      "models": {
        "gemini-3.7-flash": { "name": "Gemini 3.7 Flash [free]" },
        "gemini-3.6-flash": { "name": "Gemini 3.6 Flash [free]" },
        "gemini-3.1-pro-preview": { "name": "Gemini 3.1 Pro (Preview) [free]" }
      }
    },
    "deepseek": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "DeepSeek",
      "options": {
        "baseURL": "https://deepseek.com",
        "apiKey": "{env:DEEPSEEK_API_KEY}"
      },
      "models": {
        "deepseek-v4-pro": { "name": "DeepSeek V4 Pro [free]" },
        "deepseek-v4-flash": { "name": "DeepSeek V4 Flash [free]" }
      }
    },
    "kilocode": {
      "options": {
        "baseURL": "https://kilo.ai",
        "apiKey": "{env:KILO_API_KEY}"
      },
      "models": {
        "nemotron-3-ultra-free": { "name": "Nemotron 3 Ultra [free]" },
        "step-3.7-flash-free": { "name": "Step 3.7 Flash [free]" },
        "ling-flash-free": { "name": "Ling Flash [free]" }
      }
    },
    "orcarouter": {
      "options": {
        "baseURL": "https://orcarouter.ai",
        "apiKey": "{env:ORCAROUTER_API_KEY}"
      },
      "models": {
        "orcarouter/free": { "name": "OrcaRouter Free Auto-Route" }
      }
    },
    "aionlabs": {
      "options": {
        "baseURL": "https://aionlabs.ai",
        "apiKey": "{env:AION_API_KEY}"
      },
      "models": {
        "aion-2.5-free": { "name": "Aion 2.5 [free]" }
      }
    },
    "groq": {
      "options": {
        "baseURL": "https://groq.com",
        "apiKey": "{env:GROQ_API_KEY}"
      },
      "models": {
        "llama-3.3-70b-versatile": { "name": "Llama 3.3 70B Versatile [free]" },
        "gemma-2-9b-it": { "name": "Gemma 2 9B IT [free]" }
      }
    },
    "github": {
      "options": {
        "baseURL": "https://azure.com",
        "apiKey": "{env:GITHUB_PAT}"
      },
      "models": {
        "gpt-4o-mini": { "name": "GPT-4o Mini (GitHub) [free]" },
        "meta-llama-3.1-70b-instruct": { "name": "Llama 3.1 70B (GitHub) [free]" }
      }
    },
    "sambanova": {
      "options": {
        "baseURL": "https://sambanova.ai",
        "apiKey": "{env:SAMBANOVA_API_KEY}"
      },
      "models": {
        "llama-3.1-405b-instruct": { "name": "Llama 3.1 405B Instruct [free]" }
      }
    }
  }
}
EOF

# 7. Shell profile configuration
BASHRC="$USER_HOME/.bashrc"
if ! grep -q "opencode-agent" "$BASHRC"; then
    cat >> "$BASHRC" <<'EOF'

export VISUAL=nano
export EDITOR=nano
eval "$(mise activate bash)"
source ~/.config/opencode/env

opencode-agent() {
  GIT_AUTHOR_NAME="OpenCode" \
  GIT_AUTHOR_EMAIL="andras.czigany.13+agent@gmail.com" \
  GIT_COMMITTER_NAME="OpenCode" \
  GIT_COMMITTER_EMAIL="andras.czigany.13+agent@gmail.com" \
  opencode "$@"
}
EOF
fi

echo "=== Setup complete for $TARGET_USER! Restart your shell or run 'source ~/.bashrc' ==="
