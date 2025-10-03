#!/bin/bash

# ==============================================================================
# Interactive Fail2ban Automatic Setup Script for Proxmox VE
# by qeba
# created on 3/10/2025
# This script installs and configures Fail2ban to protect:
# 1. SSH (sshd)
# 2. Proxmox Web UI (proxmox)
#
# It will prompt the user for maxretry and bantime values.
# It should be run with root privileges.
# ==============================================================================
# --- Preamble and Safety Check ---
if [ "$(id -u)" -ne 0 ]; then
   echo "🚫 This script must be run as root. Please use sudo." 1>&2
   exit 1
fi

echo "🚀 Starting Interactive Fail2ban setup for Proxmox VE..."
echo "------------------------------------------------"

# --- 1. Get User Input for Configuration ---
echo "⚙️  STEP 1: Custom Configuration"
read -p "Enter the number of failed attempts before a ban (e.g., 5): " MAX_RETRY
while ! [[ "$MAX_RETRY" =~ ^[0-9]+$ ]]; do
    echo "❌ Invalid input. Please enter a whole number."
    read -p "Enter the number of failed attempts before a ban (e.g., 5): " MAX_RETRY
done

echo ""
echo "Enter the ban duration. Use 'm' for minutes, 'h' for hours, or 'd' for days."
read -p "Enter the ban time (e.g., 24h for 24 hours): " BAN_TIME
while ! [[ "$BAN_TIME" =~ ^[0-9]+[mhd]$ ]]; do
    echo "❌ Invalid format. Please use a number followed by 'm', 'h', or 'd'."
    read -p "Enter the ban time (e.g., 24h): " BAN_TIME
done

echo "------------------------------------------------"
echo "✅ Configuration received: maxretry = $MAX_RETRY, bantime = $BAN_TIME"
echo "------------------------------------------------"


# --- 2. Install Fail2ban ---
echo "⚙️  STEP 2: Updating package lists and installing Fail2ban..."
apt-get update > /dev/null 2>&1
apt-get install -y fail2ban
echo "✅ Fail2ban installed successfully."
echo "------------------------------------------------"


# --- 3. Create Proxmox Filter ---
echo "⚙️  STEP 3: Creating Fail2ban filter for Proxmox Web UI..."
cat > /etc/fail2ban/filter.d/proxmox.conf << EOF
[Definition]
failregex = ^.*pvedaemon\[[0-9]+\]: authentication failure; rhost=<HOST>.*$
ignoreregex =
EOF
echo "✅ Proxmox filter created."
echo "------------------------------------------------"


# --- 4. Create Local Jail Configuration ---
echo "⚙️  STEP 4: Creating main jail configuration (jail.local)..."
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime = ${BAN_TIME}
findtime = 10m
maxretry = ${MAX_RETRY}

[sshd]
enabled = true

[proxmox]
enabled = true
port    = 8006
filter  = proxmox
# Use systemd backend instead of a logpath for modern Proxmox
backend = systemd
EOF
echo "✅ Main jail configuration created."
echo "------------------------------------------------"


# --- 5. Restart, VERIFY, and Report Status ---
echo "⚙️  STEP 5: Enabling and restarting Fail2ban service..."
systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
sleep 3 # Give the service a moment to initialize.

# Verify that the service is active
if systemctl is-active --quiet fail2ban; then
    echo "✅ Fail2ban service is active and running."
    echo "------------------------------------------------"
    echo "🔍 Verifying jail status..."
    fail2ban-client status
    echo ""
    echo "👀 Checking individual jail status..."
    fail2ban-client status sshd
    echo ""
    fail2ban-client status proxmox
    echo "------------------------------------------------"
    echo "🎉 All done! Fail2ban is now active with your custom settings."
    echo "You can monitor its activity with: journalctl -f -u fail2ban"
else
    # If the service failed, give the user debugging commands
    echo "❌ ERROR: The Fail2ban service failed to start." >&2
    echo "This is usually due to a configuration error." >&2
    echo "Please run the following commands to diagnose the issue:" >&2
    echo "1. systemctl status fail2ban" >&2
    echo "2. journalctl -u fail2ban -n 100 --no-pager" >&2
    exit 1
fi