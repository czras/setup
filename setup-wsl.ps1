# setup-wsl.ps1
$ErrorActionPreference = "Stop"

Write-Host "=== WSL Container Bootstrapper ===" -ForegroundColor Cyan

# Interactive prompts with recommended defaults
$recDistro = "archLinux"
$baseDistro = Read-Host "Enter base distro to download/export (Recommended: $recDistro) [Press Enter for default]"
if ([string]::IsNullOrWhiteSpace($baseDistro)) { $baseDistro = $recDistro }

$recName = "dev-arch"
$targetName = Read-Host "Enter target container name (Recommended: $recName) [Press Enter for default]"
if ([string]::IsNullOrWhiteSpace($targetName)) { $targetName = $recName }

$recUser = "czras"
$username = Read-Host "Enter default non-root username (Recommended: $recUser) [Press Enter for default]"
if ([string]::IsNullOrWhiteSpace($username)) { $username = $recUser }

$installPath = "C:\WSL\$targetName"
$tarPath = "$env:TEMP\$baseDistro.tar"

Write-Host "`n[1/5] Fetching base image '$baseDistro'..." -ForegroundColor Cyan
wsl --install -d $baseDistro --no-launch
wsl --shutdown

Write-Host "[2/5] Exporting base image to $tarPath..." -ForegroundColor Cyan
wsl --export $baseDistro $tarPath
wsl --unregister $baseDistro

Write-Host "[3/5] Importing target container '$targetName' at $installPath..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $installPath -Force | Out-Null
wsl --import $targetName $installPath $tarPath --version 2
Remove-Item $tarPath -Force

Write-Host "[4/5] Initializing base user ('$username')..." -ForegroundColor Cyan
wsl -d $targetName -u root -- bash -c @"
pacman -Syu --noconfirm sudo git base-devel
useradd -m -G wheel -s /bin/bash $username
echo '%wheel ALL=(ALL:ALL) ALL' >> /etc/sudoers
echo 'WSL_DEV_USER=$username' >> /etc/environment
cat <<EOF > /etc/wsl.conf
[user]
default=$username
EOF
"@

Write-Host "[5/5] Finalizing container restart..." -ForegroundColor Cyan
wsl --terminate $targetName

Write-Host "`n==> WSL Container '$targetName' successfully created with user '$username'!" -ForegroundColor Green
Write-Host "Run 'wsl -d $targetName' to open your new shell environment." -ForegroundColor Yellow
