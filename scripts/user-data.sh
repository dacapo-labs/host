#!/bin/bash
set -euo pipefail

# Log output for debugging
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting devbox setup ==="

# 1. Update system packages
apt-get update && apt-get upgrade -y

# 2. Install core development tooling
apt-get install -y \
    zsh \
    git \
    curl \
    wget \
    unzip \
    jq \
    htop \
    tmux \
    ripgrep \
    fd-find \
    bat \
    software-properties-common \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release

# 3. Install Docker (official method)
curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh
usermod -aG docker ubuntu

# 4. Install Docker Compose plugin
apt-get install -y docker-compose-plugin

# 5. Install AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# 6. Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update && apt-get install -y gh

# 7. Install Node.js (LTS via NodeSource)
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# 8. Install Python tools
apt-get install -y python3-pip python3-venv

# 9. Set hostname
hostnamectl set-hostname ${hostname}

# 10. Configure sysctl for development
cat >> /etc/sysctl.conf <<EOF
# Increase inotify watchers for large codebases
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
EOF
sysctl -p

# 11. Setup ubuntu user environment
sudo -u ubuntu bash <<'USEREOF'
# Install Oh My Zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Set zsh as default shell
sudo chsh -s $(which zsh) ubuntu

# Create common directories
mkdir -p ~/code ~/projects ~/.local/bin
USEREOF

echo "=== Devbox setup complete ==="
