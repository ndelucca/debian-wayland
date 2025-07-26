#!/bin/sh
set -eu

echo "=== Sway Wayland Setup on Bare Debian ==="

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

# Define the target user
USER_NAME="${SUDO_USER:-$(logname)}"
USER_HOME="$(eval echo "~$USER_NAME")"

# Packages to install
REQUIRED_PACKAGES="sway wayland-utils wl-clipboard grim slurp foot dbus-user-session seatd systemd-container xdg-user-dirs sudo"

echo "[1/5] Updating package list..."
apt-get update -qq

echo "[2/5] Installing required packages (Wayland only)..."
apt-get install -y $REQUIRED_PACKAGES

echo "[3/5] Enabling and starting seatd socket (if not already)..."
systemctl enable --now seatd.service

echo "[4/5] Creating basic Sway config (if missing)..."
CONFIG_DIR="$USER_HOME/.config/sway"
DEFAULT_CONFIG="/etc/sway/config"

if [ ! -f "$CONFIG_DIR/config" ]; then
    mkdir -p "$CONFIG_DIR"
    cp "$DEFAULT_CONFIG" "$CONFIG_DIR/config"
    chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config"
    echo " - Default sway config copied to $CONFIG_DIR"
else
    echo " - Sway config already exists, skipping"
fi

echo "[5/5] Setting up systemd user service to launch sway on local login..."

USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
SERVICE_FILE="$USER_SYSTEMD_DIR/sway-session.service"

# Create service directory if missing
mkdir -p "$USER_SYSTEMD_DIR"
chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config"

# Write the systemd user service (idempotent)
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Start Sway Wayland session
ConditionEnvironment=!SSH_CONNECTION
ConditionEnvironment=!REMOTEHOST
ConditionEnvironment=!DISPLAY
After=graphical.target

[Service]
ExecStart=/usr/bin/sway
Restart=always
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/%U
WorkingDirectory=%h

[Install]
WantedBy=default.target
EOF

chown "$USER_NAME:$USER_NAME" "$SERVICE_FILE"

# Enable lingering for the user (so user systemd works after login)
loginctl enable-linger "$USER_NAME"

# Enable the sway-session service if not already
su - "$USER_NAME" -c '
mkdir -p "$HOME/.config/systemd/user"
systemctl --user daemon-reexec
systemctl --user daemon-reload

if ! systemctl --user is-enabled sway-session.service >/dev/null 2>&1; then
    systemctl --user enable sway-session.service
    echo " - sway-session.service enabled"
else
    echo " - sway-session.service already enabled"
fi
'

echo "=== Setup Complete. Reboot and login via local TTY to launch Sway ==="
