#!/bin/sh

set -eu

echo "=== Sway Wayland Setup on Bare Debian ==="

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

# Define the target user (default to SUDO_USER if present)
USER_NAME="${SUDO_USER:-$(logname)}"
USER_HOME="$(eval echo "~$USER_NAME")"

# Packages to install
REQUIRED_PACKAGES="sway wayland-utils wl-clipboard grim slurp foot dbus-user-session seatd systemd-container xdg-user-dirs sudo"

echo "[1/5] Updating package list..."
apt-get update -qq

echo "[2/5] Installing required Wayland packages..."
apt-get install -y $REQUIRED_PACKAGES

echo "[3/5] Enabling seatd socket..."
systemctl enable --now seatd.service

echo "[4/5] Creating Sway config for $USER_NAME..."
CONFIG_DIR="$USER_HOME/.config/sway"
DEFAULT_CONFIG="/etc/sway/config"

if [ ! -f "$CONFIG_DIR/config" ]; then
    mkdir -p "$CONFIG_DIR"
    cp "$DEFAULT_CONFIG" "$CONFIG_DIR/config"
    chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config"
    echo " - Sway default config installed."
else
    echo " - Sway config already exists, skipping."
fi

echo "[5/5] Setting up systemd user service to start sway..."

USER_SYSTEMD_DIR="$USER_HOME/.config/systemd/user"
SERVICE_FILE="$USER_SYSTEMD_DIR/sway-session.service"

mkdir -p "$USER_SYSTEMD_DIR"
chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/.config"

# Write systemd user service
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

# Enable user lingering so user services start after login
echo " - Enabling user lingering for $USER_NAME"
loginctl enable-linger "$USER_NAME"

# Add systemctl --user enable to .profile if not already present
USER_PROFILE="$USER_HOME/.profile"
ENABLER_LINE='systemctl --user enable sway-session.service 2>/dev/null || true'

if ! grep -qF "$ENABLER_LINE" "$USER_PROFILE" 2>/dev/null; then
    echo "$ENABLER_LINE" >> "$USER_PROFILE"
    chown "$USER_NAME:$USER_NAME" "$USER_PROFILE"
    echo " - Added sway-session enable command to $USER_PROFILE"
else
    echo " - sway-session enable command already present in $USER_PROFILE"
fi

echo "=== Setup Complete. Reboot and log in locally (TTY) to launch Sway ==="
