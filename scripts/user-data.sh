#!/bin/bash
set -euo pipefail

# Log output for debugging (no secrets in this script!)
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting devbox setup ==="

# Architecture detection (from Terraform variable)
ARCH="${architecture}"
echo "Architecture: $ARCH"

# Map architecture to various naming conventions used by different tools
if [ "$ARCH" = "arm64" ]; then
    AWS_ARCH="aarch64"
    LAZYGIT_ARCH="arm64"
    LAZYDOCKER_ARCH="arm64"
    HIMALAYA_ARCH="aarch64-linux"
else
    AWS_ARCH="x86_64"
    LAZYGIT_ARCH="x86_64"
    LAZYDOCKER_ARCH="x86_64"
    HIMALAYA_ARCH="x86_64-linux"
fi

# 1. System update and core tools
apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get install -y zsh git git-crypt curl wget unzip jq htop tmux ripgrep fd-find bat ncdu \
    software-properties-common build-essential ca-certificates gnupg lsb-release fzf direnv \
    cryptsetup eza

# 2. Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
apt-get install -y docker-compose-plugin

# 3. Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Remove old devbox devices from tailnet before registering
echo "Cleaning up old Tailscale devices matching '${tailscale_hostname}'..."
OLD_DEVICES=$(curl -s -u "${tailscale_api_key}:" \
  "https://api.tailscale.com/api/v2/tailnet/-/devices" \
  | jq -r '.devices[] | select(.hostname | startswith("${tailscale_hostname}")) | .id')
for DEVICE_ID in $OLD_DEVICES; do
  echo "Deleting device: $DEVICE_ID"
  curl -s -X DELETE -u "${tailscale_api_key}:" \
    "https://api.tailscale.com/api/v2/device/$DEVICE_ID"
done

tailscale up --auth-key=${tailscale_auth_key} --hostname=${tailscale_hostname} --ssh

# 4. AWS CLI
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$${AWS_ARCH}.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscliv2.zip

# 5. GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list
apt-get update && apt-get install -y gh

# 6. Node.js LTS
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# 7. Python
apt-get install -y python3-pip python3-venv python3-full

# 7b. Python CLI tools (calendar/email)
pip3 install --break-system-packages gcalcli thallo

# 8. CLI tools via npm
npm install -g tldr @anthropic-ai/claude-code @bitwarden/cli @pnp/cli-microsoft365

# 9. Modern CLI tools
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name' | sed 's/v//')
curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v$${LAZYGIT_VERSION}/lazygit_$${LAZYGIT_VERSION}_Linux_$${LAZYGIT_ARCH}.tar.gz" | tar xz -C /usr/local/bin
LAZYDOCKER_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" | jq -r '.tag_name' | sed 's/v//')
curl -fsSL "https://github.com/jesseduffield/lazydocker/releases/download/v$${LAZYDOCKER_VERSION}/lazydocker_$${LAZYDOCKER_VERSION}_Linux_$${LAZYDOCKER_ARCH}.tar.gz" | tar xz -C /usr/local/bin
curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh && mv /root/.local/bin/zoxide /usr/local/bin/
curl https://mise.run | sh && mv /root/.local/bin/mise /usr/local/bin/
HIMALAYA_VERSION=$(curl -s "https://api.github.com/repos/pimalaya/himalaya/releases/latest" | jq -r '.tag_name' | sed 's/v//')
curl -fsSL "https://github.com/pimalaya/himalaya/releases/download/v$${HIMALAYA_VERSION}/himalaya.$${HIMALAYA_ARCH}.tgz" | tar xz -C /usr/local/bin

# 10. Cloud CLIs
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list
apt-get update && apt-get install -y google-cloud-cli

# 11. System config
hostnamectl set-hostname ${hostname}
timedatectl set-timezone ${timezone}
echo "fs.inotify.max_user_watches=524288" >> /etc/sysctl.conf && sysctl -p

# 12. Git delta
cat > /etc/gitconfig <<'GITCFG'
[core]
    pager = delta
[delta]
    navigate = true
    side-by-side = true
    line-numbers = true
GITCFG

# 13. Spot watcher service
cat > /usr/local/bin/spot-watcher <<'SPOTWATCHER'
#!/bin/bash
TOKEN_URL="http://169.254.169.254/latest/api/token"
METADATA_URL="http://169.254.169.254/latest/meta-data/spot/instance-action"
NOTIFIED=false
while true; do
    TOKEN=$(curl -s -X PUT "$TOKEN_URL" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
    RESP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" -w "%%{http_code}" -o /tmp/spot-action "$METADATA_URL" 2>/dev/null)
    if [ "$RESP" = "200" ] && [ "$NOTIFIED" = "false" ]; then
        wall "SPOT INTERRUPTION - Hibernating in ~2 min"
        NOTIFIED=true
    fi
    sleep 5
done
SPOTWATCHER
chmod +x /usr/local/bin/spot-watcher

cat > /etc/systemd/system/spot-watcher.service <<'SPOTSERVICE'
[Unit]
Description=Spot interruption watcher
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/spot-watcher
Restart=always
[Install]
WantedBy=multi-user.target
SPOTSERVICE
systemctl daemon-reload && systemctl enable --now spot-watcher

# 14. Bootstrap scripts for Bitwarden secrets
mkdir -p /home/ubuntu/bin

cat > /home/ubuntu/bin/bw-unlock <<'BWUNLOCK'
#!/usr/bin/env bash
set -uo pipefail
BW_SESSION_FILE="$HOME/.config/bitwarden/session"
_status() { bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown"; }
_save() { mkdir -p "$(dirname "$BW_SESSION_FILE")" && echo "$BW_SESSION" > "$BW_SESSION_FILE" && chmod 600 "$BW_SESSION_FILE"; }
_load() { [[ -f "$BW_SESSION_FILE" ]] && export BW_SESSION=$(cat "$BW_SESSION_FILE") && [[ "$(_status)" == "unlocked" ]]; }
_unlock() {
    command -v bw &>/dev/null || { echo "Error: bw not installed"; return 1; }
    _load && { echo "Session restored"; return 0; }
    case "$(_status)" in
        unlocked) echo "Already unlocked" ;;
        locked) BW_SESSION=$(bw unlock --raw) && export BW_SESSION && _save && echo "Unlocked" ;;
        unauthenticated) bw login && BW_SESSION=$(bw unlock --raw) && export BW_SESSION && _save && echo "Logged in" ;;
        *) echo "Unknown status"; return 1 ;;
    esac
}
_unlock
BWUNLOCK

cat > /home/ubuntu/bin/devbox-init <<'DEVBOXINIT'
#!/usr/bin/env bash
set -euo pipefail

DATA_DEV="/dev/nvme1n1"
DATA_MAPPER="data"
DATA_MOUNT="/data"

bw status 2>/dev/null | jq -e '.status == "unlocked"' &>/dev/null || { echo "Run: source ~/bin/bw-unlock"; exit 1; }
bw sync &>/dev/null

# =============================================================================
# LUKS Data Volume
# =============================================================================
if [[ -b "$DATA_DEV" ]]; then
    echo "=== Setting up encrypted data volume ==="
    LUKS_KEY=$(bw get password "devbox/luks-key" 2>/dev/null) || { echo "Error: devbox/luks-key not found in Bitwarden"; exit 1; }

    if ! sudo cryptsetup isLuks "$DATA_DEV" 2>/dev/null; then
        echo "Formatting $DATA_DEV with LUKS (first time setup)..."
        # Wipe any existing signatures and format non-interactively
        sudo wipefs -a "$DATA_DEV" 2>/dev/null || true
        echo -n "$LUKS_KEY" | sudo cryptsetup luksFormat --type luks2 -q "$DATA_DEV" -
        echo -n "$LUKS_KEY" | sudo cryptsetup open "$DATA_DEV" "$DATA_MAPPER" -
        sudo mkfs.ext4 -L data "/dev/mapper/$DATA_MAPPER"
        sudo mkdir -p "$DATA_MOUNT"
        sudo mount "/dev/mapper/$DATA_MAPPER" "$DATA_MOUNT"
        sudo mkdir -p "$DATA_MOUNT/home"
        sudo cp -a /home/ubuntu/. "$DATA_MOUNT/home/" 2>/dev/null || true
        sudo chown -R ubuntu:ubuntu "$DATA_MOUNT/home"
        echo "Data volume initialized"
    else
        if [[ ! -e "/dev/mapper/$DATA_MAPPER" ]]; then
            echo "Unlocking LUKS volume..."
            echo -n "$LUKS_KEY" | sudo cryptsetup open "$DATA_DEV" "$DATA_MAPPER" -
        fi
        sudo mkdir -p "$DATA_MOUNT"
        # Create filesystem if missing (e.g., manual LUKS format without mkfs)
        if ! sudo blkid "/dev/mapper/$DATA_MAPPER" &>/dev/null; then
            echo "Creating filesystem on LUKS volume..."
            sudo mkfs.ext4 -L data "/dev/mapper/$DATA_MAPPER"
        fi
        if ! mountpoint -q "$DATA_MOUNT"; then
            sudo mount "/dev/mapper/$DATA_MAPPER" "$DATA_MOUNT"
        fi
        echo "Data volume unlocked and mounted"
    fi

    # Bind mount encrypted home over /home/ubuntu
    if [[ -d "$DATA_MOUNT/home" ]] && ! mountpoint -q /home/ubuntu; then
        sudo mount --bind "$DATA_MOUNT/home" /home/ubuntu
        echo "Home directory mounted from encrypted volume"
    fi
fi

echo "=== Setting up SSH keys ==="
mkdir -p ~/.ssh && chmod 700 ~/.ssh
if [[ ! -f ~/.ssh/id_ed25519_home ]]; then
    bw get item "devbox/github-ssh-home" &>/dev/null && bw get item "devbox/github-ssh-home" | jq -r '.fields[]? | select(.name=="private_key") | .value' > ~/.ssh/id_ed25519_home && chmod 600 ~/.ssh/id_ed25519_home && echo "Home key installed"
else
    echo "Home key already exists"
fi
if [[ ! -f ~/.ssh/id_ed25519_work ]]; then
    bw get item "devbox/github-ssh-work" &>/dev/null && bw get item "devbox/github-ssh-work" | jq -r '.fields[]? | select(.name=="private_key") | .value' > ~/.ssh/id_ed25519_work && chmod 600 ~/.ssh/id_ed25519_work && echo "Work key installed"
else
    echo "Work key already exists"
fi
[[ ! -f ~/.ssh/config ]] && cat > ~/.ssh/config <<'SSHCFG'
Host github.com-home
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_home
    IdentitiesOnly yes
Host github.com-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_work
    IdentitiesOnly yes
SSHCFG
chmod 600 ~/.ssh/config
grep -q "github.com" ~/.ssh/known_hosts 2>/dev/null || ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null

echo "=== Setting up GitHub CLI ==="
gh auth status &>/dev/null || { bw get item "devbox/github-token" &>/dev/null && bw get password "devbox/github-token" | gh auth login --with-token && gh config set git_protocol ssh; }

echo "=== Setting up git identity ==="
mkdir -p ~/.config/git

# Fetch identity from Bitwarden
IDENTITY=$(bw get item "devbox/identity" 2>/dev/null) || { echo "Warning: devbox/identity not found in Bitwarden"; IDENTITY=""; }

if [[ -n "$IDENTITY" ]]; then
    GIT_NAME_HOME=$(echo "$IDENTITY" | jq -r '.fields[]? | select(.name=="git_name_home") | .value // empty')
    GIT_EMAIL_HOME=$(echo "$IDENTITY" | jq -r '.fields[]? | select(.name=="git_email_home") | .value // empty')
    GIT_NAME_WORK=$(echo "$IDENTITY" | jq -r '.fields[]? | select(.name=="git_name_work") | .value // empty')
    GIT_EMAIL_WORK=$(echo "$IDENTITY" | jq -r '.fields[]? | select(.name=="git_email_work") | .value // empty')
else
    # Fallback defaults
    GIT_NAME_HOME="Seth"
    GIT_EMAIL_HOME="your-email@example.com"
    GIT_NAME_WORK="Your Name"
    GIT_EMAIL_WORK="your-work-email@example.com"
fi

if [[ ! -f ~/.config/git/config-home ]]; then
    cat > ~/.config/git/config-home <<GH
[user]
    name = $GIT_NAME_HOME
    email = $GIT_EMAIL_HOME
[url "git@github.com-home:"]
    insteadOf = git@github.com:
GH
    echo "Git config-home created"
else
    echo "Git config-home already exists"
fi
if [[ ! -f ~/.config/git/config-work ]]; then
    cat > ~/.config/git/config-work <<GW
[user]
    name = $GIT_NAME_WORK
    email = $GIT_EMAIL_WORK
[url "git@github.com-work:"]
    insteadOf = git@github.com:
GW
    echo "Git config-work created"
else
    echo "Git config-work already exists"
fi
grep -q "claude-sessions/home" ~/.gitconfig 2>/dev/null || cat >> ~/.gitconfig <<'GINC'
[includeIf "gitdir:~/claude-sessions/home/"]
    path = ~/.config/git/config-home
[includeIf "gitdir:~/claude-sessions/work/"]
    path = ~/.config/git/config-work
GINC

echo "=== Setting up AWS config ==="
mkdir -p ~/.aws

# Fetch AWS config from Bitwarden (reuse IDENTITY from above if available)
if [[ -n "$IDENTITY" ]]; then
    AWS_ACCOUNT_ID=$(echo "$IDENTITY" | jq -r '.fields[]? | select(.name=="aws_account_id") | .value // empty')
    AWS_SSO_START_URL=$(echo "$IDENTITY" | jq -r '.fields[]? | select(.name=="aws_sso_start_url") | .value // empty')
    AWS_SSO_REGION=$(echo "$IDENTITY" | jq -r '.fields[]? | select(.name=="aws_sso_region") | .value // empty')
    AWS_ROLE_NAME=$(echo "$IDENTITY" | jq -r '.fields[]? | select(.name=="aws_role_name") | .value // empty')
else
    # Fallback defaults
    AWS_ACCOUNT_ID="000000000000"
    AWS_SSO_START_URL="https://d-9067954177.awsapps.com/start"
    AWS_SSO_REGION="us-east-1"
    AWS_ROLE_NAME="AdministratorAccess"
fi

if [[ ! -f ~/.aws/config ]]; then
    cat > ~/.aws/config <<AWSCFG
[default]
region = us-east-1
[profile home]
sso_session = home-sso
sso_account_id = $AWS_ACCOUNT_ID
sso_role_name = $AWS_ROLE_NAME
region = us-east-1
[sso-session home-sso]
sso_start_url = $AWS_SSO_START_URL
sso_region = $AWS_SSO_REGION
sso_registration_scopes = sso:account:access
AWSCFG
    echo "AWS config created"
else
    echo "AWS config already exists"
fi

echo "=== Setting up claude-sessions ==="
mkdir -p ~/claude-sessions/home ~/claude-sessions/work
# Clone sessions config if repo exists (optional)
if [[ ! -d ~/.config/claude-sessions ]] && [[ -f ~/.ssh/id_ed25519_home ]]; then
    git clone git@github.com-home:YOUR_USERNAME/claude-sessions-config.git ~/.config/claude-sessions 2>/dev/null && \
    bw get item "devbox/git-crypt-key" &>/dev/null && \
    cd ~/.config/claude-sessions && \
    git-crypt unlock <(bw get item "devbox/git-crypt-key" | jq -r '.fields[]? | select(.name=="key_b64") | .value' | base64 -d) 2>/dev/null && \
    cd - || echo "claude-sessions-config not available (optional)"
fi

echo "=== Setting up LifeMaestro ==="
if [[ ! -d ~/code/lifemaestro ]] && [[ -f ~/.ssh/id_ed25519_home ]]; then
    git clone git@github.com-home:YOUR_USERNAME/dotfiles.git ~/code/lifemaestro
    cd ~/code/lifemaestro && ./install.sh && cd -
    # Symlink .claude to get skills/rules globally
    if [[ -d ~/code/lifemaestro/.claude ]]; then
        # Remove default .claude dir (created by user-data) to replace with symlink
        [[ -d ~/.claude && ! -L ~/.claude ]] && rm -rf ~/.claude
        ln -sfn ~/code/lifemaestro/.claude ~/.claude
    fi
    echo "LifeMaestro installed"
else
    echo "LifeMaestro already installed or SSH key missing"
fi

echo "=== Setting up Himalaya (email) ==="
mkdir -p ~/.config/himalaya
if [[ ! -f ~/.config/himalaya/config.toml ]] && bw get item "devbox/gmail-oauth" &>/dev/null; then
    GMAIL_EMAIL=$(bw get item "devbox/gmail-oauth" | jq -r '.login.username // empty')
    GMAIL_CLIENT_ID=$(bw get item "devbox/gmail-oauth" | jq -r '.fields[]? | select(.name=="client_id") | .value // empty')
    GMAIL_CLIENT_SECRET=$(bw get item "devbox/gmail-oauth" | jq -r '.fields[]? | select(.name=="client_secret") | .value // empty')

    if [[ -n "$GMAIL_EMAIL" && -n "$GMAIL_CLIENT_ID" && -n "$GMAIL_CLIENT_SECRET" ]]; then
        cat > ~/.config/himalaya/config.toml <<HIMALAYA
[accounts.gmail]
default = true
email = "$GMAIL_EMAIL"

backend.type = "imap"
backend.host = "imap.gmail.com"
backend.port = 993
backend.encryption = "tls"
backend.login = "$GMAIL_EMAIL"
backend.auth.type = "oauth2"
backend.auth.client-id = "$GMAIL_CLIENT_ID"
backend.auth.client-secret = "$GMAIL_CLIENT_SECRET"
backend.auth.method = "redirect"
backend.auth.auth-url = "https://accounts.google.com/o/oauth2/auth"
backend.auth.token-url = "https://oauth2.googleapis.com/token"
backend.auth.scopes = ["https://mail.google.com/"]

sender.type = "smtp"
sender.host = "smtp.gmail.com"
sender.port = 465
sender.encryption = "tls"
sender.login = "$GMAIL_EMAIL"
sender.auth.type = "oauth2"
sender.auth.client-id = "$GMAIL_CLIENT_ID"
sender.auth.client-secret = "$GMAIL_CLIENT_SECRET"
sender.auth.method = "redirect"
sender.auth.auth-url = "https://accounts.google.com/o/oauth2/auth"
sender.auth.token-url = "https://oauth2.googleapis.com/token"
sender.auth.scopes = ["https://mail.google.com/"]
HIMALAYA
        echo "Himalaya configured. Run: himalaya account configure gmail"
    else
        echo "Gmail OAuth credentials incomplete in Bitwarden"
    fi
else
    echo "Himalaya config exists or devbox/gmail-oauth not in Bitwarden (optional)"
fi

echo "=== Setting up gcalcli (Google Calendar) ==="
if [[ ! -f ~/.gcalcli_oauth ]] && bw get item "devbox/gmail-oauth" &>/dev/null; then
    GMAIL_CLIENT_ID=$(bw get item "devbox/gmail-oauth" | jq -r '.fields[]? | select(.name=="client_id") | .value // empty')
    GMAIL_CLIENT_SECRET=$(bw get item "devbox/gmail-oauth" | jq -r '.fields[]? | select(.name=="client_secret") | .value // empty')

    if [[ -n "$GMAIL_CLIENT_ID" && -n "$GMAIL_CLIENT_SECRET" ]]; then
        cat > ~/.gcalcli_oauth <<GCALCLI
{
  "client_id": "$GMAIL_CLIENT_ID",
  "client_secret": "$GMAIL_CLIENT_SECRET"
}
GCALCLI
        chmod 600 ~/.gcalcli_oauth
        echo "gcalcli configured. Run: gcalcli init"
    fi
else
    echo "gcalcli config exists or devbox/gmail-oauth not in Bitwarden (optional)"
fi

echo "=== Setting up MS365 (email + calendar) ==="
if bw get item "devbox/ms365-oauth" &>/dev/null; then
    MS365_EMAIL=$(bw get item "devbox/ms365-oauth" | jq -r '.login.username // empty')
    MS365_CLIENT_ID=$(bw get item "devbox/ms365-oauth" | jq -r '.fields[]? | select(.name=="client_id") | .value // empty')
    MS365_CLIENT_SECRET=$(bw get item "devbox/ms365-oauth" | jq -r '.fields[]? | select(.name=="client_secret") | .value // empty')
    MS365_TENANT_ID=$(bw get item "devbox/ms365-oauth" | jq -r '.fields[]? | select(.name=="tenant_id") | .value // empty')

    if [[ -n "$MS365_EMAIL" && -n "$MS365_CLIENT_ID" && -n "$MS365_TENANT_ID" ]]; then
        # Add MS365 account to himalaya config
        if [[ -f ~/.config/himalaya/config.toml ]] && ! grep -q "accounts.ms365" ~/.config/himalaya/config.toml; then
            cat >> ~/.config/himalaya/config.toml <<HIMALAYA_MS365

[accounts.ms365]
default = false
email = "$MS365_EMAIL"

backend.type = "imap"
backend.host = "outlook.office365.com"
backend.port = 993
backend.encryption = "tls"
backend.login = "$MS365_EMAIL"
backend.auth.type = "oauth2"
backend.auth.client-id = "$MS365_CLIENT_ID"
backend.auth.client-secret = "$MS365_CLIENT_SECRET"
backend.auth.method = "redirect"
backend.auth.auth-url = "https://login.microsoftonline.com/$MS365_TENANT_ID/oauth2/v2.0/authorize"
backend.auth.token-url = "https://login.microsoftonline.com/$MS365_TENANT_ID/oauth2/v2.0/token"
backend.auth.scopes = ["https://outlook.office365.com/IMAP.AccessAsUser.All", "https://outlook.office365.com/SMTP.Send", "offline_access"]

sender.type = "smtp"
sender.host = "smtp.office365.com"
sender.port = 587
sender.encryption = "starttls"
sender.login = "$MS365_EMAIL"
sender.auth.type = "oauth2"
sender.auth.client-id = "$MS365_CLIENT_ID"
sender.auth.client-secret = "$MS365_CLIENT_SECRET"
sender.auth.method = "redirect"
sender.auth.auth-url = "https://login.microsoftonline.com/$MS365_TENANT_ID/oauth2/v2.0/authorize"
sender.auth.token-url = "https://login.microsoftonline.com/$MS365_TENANT_ID/oauth2/v2.0/token"
sender.auth.scopes = ["https://outlook.office365.com/IMAP.AccessAsUser.All", "https://outlook.office365.com/SMTP.Send", "offline_access"]
HIMALAYA_MS365
            echo "Himalaya MS365 configured. Run: himalaya account configure ms365"
        fi

        # Configure thallo for MS365 calendar
        mkdir -p ~/.config/thallo
        if [[ ! -f ~/.config/thallo/config.toml ]]; then
            cat > ~/.config/thallo/config.toml <<THALLO
[azure]
client_id = "$MS365_CLIENT_ID"
tenant_id = "$MS365_TENANT_ID"

[calendar]
default = "Calendar"
THALLO
            echo "thallo configured. Run: thallo authorize"
        fi
    else
        echo "MS365 OAuth credentials incomplete in Bitwarden"
    fi
else
    echo "devbox/ms365-oauth not in Bitwarden (optional)"
fi

echo "=== DONE ==="
echo "Run: aws sso login --profile home"
DEVBOXINIT

cat > /home/ubuntu/bin/devbox-check <<'DEVBOXCHECK'
#!/usr/bin/env bash
# Health check script - validates all devbox dependencies
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

ok()   { echo -e "$${GREEN}✓$${NC} $1"; }
warn() { echo -e "$${YELLOW}⚠$${NC} $1"; ((WARNINGS++)); }
fail() { echo -e "$${RED}✗$${NC} $1"; ((ERRORS++)); }
info() { echo -e "  $1"; }

echo "=== Devbox Health Check ==="
echo ""

# 1. Check Bitwarden
echo "Bitwarden:"
if ! command -v bw &>/dev/null; then
    fail "bw CLI not installed"
else
    BW_STATUS=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")
    case "$BW_STATUS" in
        unlocked) ok "Unlocked and ready" ;;
        locked)   warn "Locked - run: source ~/bin/bw-unlock" ;;
        unauthenticated) fail "Not logged in - run: bw login" ;;
        *) fail "Unknown status: $BW_STATUS" ;;
    esac
fi
echo ""

# 2. Check required Bitwarden items
echo "Bitwarden Items:"
REQUIRED_ITEMS=(
    "devbox/luks-key:LUKS encryption key"
    "devbox/github-ssh-home:GitHub SSH key (home)"
    "devbox/github-ssh-work:GitHub SSH key (work)"
    "devbox/github-token:GitHub personal access token"
    "devbox/identity:Git and AWS identity config"
)

if [[ "$BW_STATUS" == "unlocked" ]]; then
    for ITEM_DESC in "$${REQUIRED_ITEMS[@]}"; do
        ITEM_NAME="$${ITEM_DESC%%:*}"
        ITEM_LABEL="$${ITEM_DESC#*:}"
        if bw get item "$ITEM_NAME" &>/dev/null; then
            ok "$ITEM_LABEL"
        else
            fail "$ITEM_LABEL - missing: $ITEM_NAME"
            info "Create with: bw create item (see terraform.tfvars.example)"
        fi
    done

    # Optional items
    OPTIONAL_ITEMS=(
        "devbox/git-crypt-key:Git-crypt key (for encrypted repos)"
        "devbox/gmail-oauth:Gmail OAuth credentials"
        "devbox/ms365-oauth:MS365 OAuth credentials"
    )
    for ITEM_DESC in "$${OPTIONAL_ITEMS[@]}"; do
        ITEM_NAME="$${ITEM_DESC%%:*}"
        ITEM_LABEL="$${ITEM_DESC#*:}"
        if bw get item "$ITEM_NAME" &>/dev/null; then
            ok "$ITEM_LABEL"
        else
            warn "$ITEM_LABEL - not configured (optional)"
        fi
    done
else
    warn "Skipping item check - unlock Bitwarden first"
fi
echo ""

# 3. Check SSH keys
echo "SSH Keys:"
if [[ -f ~/.ssh/id_ed25519_home ]]; then
    ok "Home SSH key exists"
    # Check if key is on GitHub
    if ssh -T git@github.com-home 2>&1 | grep -q "successfully authenticated"; then
        ok "Home key authenticated with GitHub"
    else
        warn "Home key may not be added to GitHub"
        info "Add public key to: https://github.com/settings/keys"
        info "Public key: $(ssh-keygen -y -f ~/.ssh/id_ed25519_home 2>/dev/null | head -1)"
    fi
else
    fail "Home SSH key missing - run devbox-init"
fi

if [[ -f ~/.ssh/id_ed25519_work ]]; then
    ok "Work SSH key exists"
else
    warn "Work SSH key missing (optional)"
fi
echo ""

# 4. Check GitHub CLI
echo "GitHub CLI:"
if command -v gh &>/dev/null; then
    if gh auth status &>/dev/null; then
        ok "Authenticated"
    else
        warn "Not authenticated - run devbox-init or: gh auth login"
    fi
else
    fail "gh CLI not installed"
fi
echo ""

# 5. Check LUKS volume
echo "LUKS Volume:"
DATA_DEV="/dev/nvme1n1"
if [[ -b "$DATA_DEV" ]]; then
    if sudo cryptsetup isLuks "$DATA_DEV" 2>/dev/null; then
        ok "LUKS formatted"
        if [[ -e /dev/mapper/data ]]; then
            ok "Unlocked"
            if mountpoint -q /data 2>/dev/null; then
                ok "Mounted at /data"
            else
                warn "Not mounted - run devbox-init"
            fi
        else
            warn "Locked - run devbox-init to unlock"
        fi
    else
        warn "Not LUKS formatted - will be formatted on first devbox-init"
    fi
else
    fail "Data volume not attached ($DATA_DEV)"
fi
echo ""

# 6. Check LifeMaestro
echo "LifeMaestro:"
if [[ -d ~/code/lifemaestro ]]; then
    ok "Installed at ~/code/lifemaestro"
    if [[ -L ~/.claude ]] && [[ -d ~/.claude ]]; then
        ok "~/.claude symlinked"
    else
        warn "~/.claude not symlinked - run devbox-init"
    fi
else
    warn "Not installed - will install on devbox-init"
fi
echo ""

# Summary
echo "=== Summary ==="
if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "$${GREEN}All checks passed!$${NC}"
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "$${YELLOW}$WARNINGS warning(s), no errors$${NC}"
else
    echo -e "$${RED}$ERRORS error(s), $WARNINGS warning(s)$${NC}"
    echo ""
    echo "Fix errors before running devbox-init"
fi

exit $ERRORS
DEVBOXCHECK

chmod +x /home/ubuntu/bin/bw-unlock /home/ubuntu/bin/devbox-init /home/ubuntu/bin/devbox-check
chown -R ubuntu:ubuntu /home/ubuntu/bin

# 15. User environment
sudo -u ubuntu bash <<'USERSETUP'
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
sudo chsh -s $(which zsh) ubuntu
mkdir -p ~/code ~/projects ~/.local/bin ~/.claude
cat >> ~/.zshrc <<'ZSHRC'
command -v mise &>/dev/null && eval "$(mise activate zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"
export PATH="$HOME/bin:$PATH"
alias ls='eza' ll='eza -la' lg='lazygit' ld='lazydocker'
alias unlock='source ~/bin/bw-unlock' init='~/bin/devbox-init' check='~/bin/devbox-check'
ZSHRC
cat > ~/.claude/settings.json <<'CLAUDE'
{"permissions":{"allow":["Bash(git *)","Bash(gh *)","Bash(aws *)","Bash(npm *)","Bash(docker *)","Bash(terraform *)","Bash(bw *)","Read","Write","Edit","Glob","Grep","Task","WebFetch","TodoRead","TodoWrite"],"deny":[]}}
CLAUDE
mkdir -p ~/.claude/rules
cat > ~/.claude/rules/save-progress.md <<'SAVEMD'
# Save Progress Frequently

This devbox does NOT hibernate - stopping loses all running state.

## Rules
- Commit work frequently (at least every significant milestone)
- Push to remote before ending sessions
- Use descriptive commit messages
- Never leave uncommitted work when stepping away

## Before Stopping
If the user says they're done or stepping away:
1. Check for uncommitted changes: `git status`
2. Offer to commit and push
3. Remind about unsaved work in other repos
SAVEMD
USERSETUP

# 16. MOTD
cat > /etc/motd <<'MOTD'
================================================================================
                            WELCOME TO DEVBOX
================================================================================
  First time:  unlock && init
  Health check: check

  Commands:
    unlock  - Authenticate with Bitwarden
    init    - Set up LUKS, SSH keys, configs
    check   - Verify all dependencies
================================================================================
MOTD

echo "=== Devbox setup complete ==="
