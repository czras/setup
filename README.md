# Arch WSL2 Dev Environment Setup

A modular bootstrap system to spin up isolated Arch Linux WSL2 containers, provision developer tools, and manage API keys securely with zero unencrypted credentials stored on disk.

---

## Repository Structure

```text
.
├── setup-wsl.ps1        # PowerShell script to create fresh Arch WSL2 instances
├── setup-env.sh         # Distro-agnostic launcher & orchestrator
├── config/
│   ├── git.env          # Git user name and email configuration
│   ├── opencode.jsonc   # OpenCode configuration template
│   └── repos.txt        # List of Git repository URLs to clone
├── scripts/
│   └── arch.sh          # Arch Linux-specific package management & AUR tasks
└── secrets/
    └── opencode.env.enc # SOPS-encrypted API credentials (tracked in Git)

```

---

## Part 1: Provisioning the WSL2 Container (`setup-wsl.ps1`)

The PowerShell bootstrapper creates a clean, isolated Arch Linux WSL instance with a dedicated non-root user and essential base packages.

### Prerequisites (Windows)

* WSL2 enabled (`wsl --install` executed at least once on Windows).
* PowerShell 5.1 or higher.

### Execution

Run the script from Windows PowerShell:

```powershell
.\setup-wsl.ps1

```

### What It Does

1. **Fetches Base Distro:** Downloads Arch Linux via `wsl --install -d archLinux --no-launch`.
2. **Exports & Cleans Up:** Exports the clean base layer to a temporary `.tar` archive and unregisters the default instance.
3. **Imports Target Container:** Imports the tarball under a custom name (default: `dev-arch`) located at `C:\WSL\<targetName>`.
4. **Configures Non-Root User:** Boots as `root` to install `sudo`, `git`, and `base-devel`, creates the designated non-root user, adds it to the `wheel` group, configures `/etc/wsl.conf`, and exports `WSL_DEV_USER` to `/etc/environment`.
5. **Finalizes:** Terminates the instance to apply configuration changes.

Enter your newly created environment:

```powershell
wsl -d dev-arch

```

---

## Part 2: Configuration Before Setup

Before running the environment setup script, customize your configuration files in the `config/` directory.

### 1. Git Identity (`config/git.env`)

Set your default Git commit name and email address:

```bash
GIT_NAME="Your Name"
GIT_EMAIL="your.email@example.com"
AGENT_EMAIL="your.email+agent@example.com"

```

### 2. Workspace Repositories (`config/repos.txt`)

List the Git repository URLs you want cloned into `~/workspace/`. Comments starting with `#` and empty lines are ignored:

```text
# Repositories to clone into ~/workspace
https://github.com/github/spec-kit.git
# git@github.com:your-user/your-private-repo.git

```

---

## Part 3: Security & Credentials Model

This setup uses **SOPS** and **Age** to manage API keys safely.

* **Age Private Key Location:** `~/.config/sops/age/keys.txt`
* **Zero On-Disk Exposure:** API keys are decrypted into memory at runtime and never saved in plain text files like `.env` or sourced directly in `~/.bashrc`.
* **Runtime Injection:** The `opencode-agent` wrapper function decrypts `opencode.env.enc` directly into process memory during execution.

---

## Part 4: Running the Environment Setup (`setup-env.sh`)

Clone or copy this repository into your new WSL instance.

```bash
git clone git@github.com:czras/setup.git ~/wsl-setup
cd ~/wsl-setup
chmod +x setup-env.sh

```

### Step 4.1: (Optional) Restore Existing Age Private Key

If you already have an Age private key backed up, copy it into place **before** running the setup script. This enables automatic decryption of existing encrypted secrets:

```bash
mkdir -p ~/.config/sops/age
nano ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

```

> **Note:** If `keys.txt` is not found, `setup-env.sh` automatically generates a new key pair.

### Step 4.2: Execute Setup

```bash
./setup-env.sh

```

---

## What `setup-env.sh` Executing Does

1. **Distro Module Invocation:** Inspects `/etc/os-release` and executes `scripts/arch.sh` to handle package installations (`pacman`), locales, and AUR helper setups (`paru`).
2. **SSH Key Generation & GitHub Authorization:**
* Generates a new ED25519 key pair if missing.
* Prints the public key to the terminal.
* **Pauses execution** with an interactive prompt, allowing you to copy the key to your [GitHub Settings](https://github.com/settings/keys) before proceeding.


3. **Workspace Provisioning:**
* Creates `~/workspace/`.
* Parses `config/repos.txt` and batch clones specified repositories.


4. **Toolchain & Runtimes Configuration:**
* Configures `mise` for version management (Node.js, Python).
* Sets up `corepack` (`pnpm`) and `uv` CLI extensions.


5. **Interactive Secret Management (SOPS + Age):**
* Decrypts existing secrets (if an Age key is present) to populate defaults.
* Prompts for missing or updated API keys with masked feedback (`[Current: sk-ant...1234]`).
* Encrypts and writes the result to `~/.config/opencode/opencode.env.enc`.


6. **Shell & Agent Setup:**
* Copies `config/opencode.jsonc` to `~/.config/opencode/opencode.jsonc`.
* Configures `~/.bashrc` with the `opencode-agent` executable function.



---

## Part 5: Usage

Reload your shell environment:

```bash
source ~/.bashrc

```

Launch OpenCode via the agent wrapper:

```bash
opencode-agent

```

The wrapper function decrypts API keys in memory, sets designated agent commit author variables, and launches `opencode`.
