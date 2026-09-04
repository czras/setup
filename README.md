# Arch WSL2 Dev Environment Setup

A modular bootstrap system to spin up isolated Arch Linux WSL2 containers and provision a developer environment with zero unencrypted credentials stored on disk.

---

## Repository Structure

```text
.
├── setup-wsl.ps1        # PowerShell script to create fresh Arch WSL2 instances
├── setup.sh             # In-container Arch setup script
├── config/
│   └── opencode.jsonc   # OpenCode configuration template
└── secrets/
    └── opencode.env.enc # SOPS-encrypted API credentials (tracked in Git)

```

---

## Part 1: Provisioning the WSL2 Container (`setup-wsl.ps1`)

The PowerShell bootstrapper creates a clean, isolated Arch Linux WSL instance with a dedicated non-root user and essential base packages.

### Prerequisites (Windows)

* WSL2 enabled (`wsl --install` executed at least once on Windows).
* PowerShell 5.1 or higher executed as an Administrator or standard user with WSL rights.

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

## Part 2: Security & Credentials Management

This setup uses **SOPS** and **Age** to manage API keys. Credentials are checked into Git inside `secrets/opencode.env.enc` encrypted with an Age public key.

### Security Model

* **Encryption Key:** Your Age private key lives at `~/.config/sops/age/keys.txt`.
* **Zero On-Disk Exposure:** API keys are never written in plain text to files like `.env` or sourced into `~/.bashrc`.
* **Runtime Injection:** The `opencode-agent` function decrypts `opencode.env.enc` directly into memory for the duration of process execution.

---

## Part 3: Running the Container Setup (`setup.sh`)

Clone or copy this repository into your new WSL instance.

```bash
git clone git@github.com:czras/setup.git ~/wsl-setup
cd ~/wsl-setup
chmod +x setup-env-arch.sh

```

### Step 3.1: (Optional) Restore Existing Age Private Key

If you already have an Age private key backed up (e.g., in a password manager or Windows host folder), copy it into place **before** running `setup.sh`. This allows the script to automatically decrypt and load your existing secrets as default values:

```bash
mkdir -p ~/.config/sops/age
nano ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

```

> **Note:** If `~/.config/sops/age/keys.txt` is missing, `setup.sh` will generate a new Age key pair automatically.

### Step 3.2: Execute Setup

```bash
./setup.sh

```

### Setup Execution Workflow

1. **System Provisioning:** Updates Arch, configures locales, and installs core CLI tools (`mise`, `uv`, `sops`, `age`, `github-cli`, `paru`, `opencode-bin`).
2. **Age Key Handling:**
* Checks for an existing Age key at `~/.config/sops/age/keys.txt`.
* Generates a new key pair if missing.


3. **Interactive Secret Prompt:**
* If an existing `keys.txt` is found and an encrypted secrets file exists, `setup.sh` decrypts it to load current values.
* Prompts for missing/updated API keys showing masked defaults (`[Current: sk-ant...1234]`).
* Pressing **Enter** retains the current value.


4. **Encryption & Output:** Encrypts the values with Age via SOPS and writes to `~/.config/opencode/opencode.env.enc`.
5. **Configuration Copy:** Copies `config/opencode.jsonc` to `~/.config/opencode/opencode.jsonc`.
6. **Shell Integration:** Appends the `opencode-agent` wrapper function to `~/.bashrc`.

---

## Part 4: Usage

Restart your shell or reload configuration:

```bash
source ~/.bashrc

```

Run OpenCode via the wrapper:

```bash
opencode-agent

```

The wrapper automatically decrypts `opencode.env.enc` into memory, injects your provider keys into environment variables, overrides Git author metadata for agent commits, and launches `opencode`.
