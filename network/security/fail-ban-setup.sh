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
# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
   echo "🚫 This script must be run as root. Please use sudo." 1>&2
   exit 1
fi

echo "🚀 Starting Interactive Fail2ban setup for Proxmox VE..."
echo "------------------------------------------------"

# --- 1. Get User Input for Configuration ---
echo "⚙️  STEP 1: Custom Configuration"
echo "Please provide the default values for banning."
echo ""

# Get Max Retry from user
read -p "Enter the number of failed attempts before a ban (e.g., 5): " MAX_RETRY
# Basic validation to ensure it's a number
while ! [[ "$MAX_RETRY" =~ ^[0-9]+$ ]]; do
    echo "❌ Invalid input. Please enter a whole number."
    read -p "Enter the number of failed attempts before a ban (e.g., 5): " MAX_RETRY
done

echo ""
# Get Ban Time from user
echo "Enter the ban duration. Use 'm' for minutes, 'h' for hours, or 'd' for days."
read -p "Enter the ban time (e.g., 24h for 24 hours): " BAN_TIME
# Basic validation for the time format
while ! [[ "$BAN_TIME" =~ ^[0-9]+[mhd]$ ]]; do
    echo "❌ Invalid format. Please use a number followed by 'm', 'h', or 'd'."
    echo "   Examples: 30m, 12h, 7d"
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
# Regex to match Proxmox VE authentication failures
failregex = ^.*pvedaemon\[[0-9]+\]: authentication failure; rhost=<HOST>.*$
ignoreregex =
EOF
echo "✅ Proxmox filter created."
echo "------------------------------------------------"


# --- 4. Create Local Jail Configuration ---
echo "⚙️  STEP 4: Creating main jail configuration (jail.local) with your settings..."
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Global settings for all jails, based on your input.
ignoreip = 127.0.0.1/8 ::1
bantime = ${BAN_TIME}
findtime = 10m
maxretry = ${MAX_RETRY}

# --- Jail for SSH ---
[sshd]
enabled = true
# This jail will use the DEFAULT settings above.

# --- Jail for Proxmox Web UI ---
[proxmox]
enabled = true
port = https,http,8006
filter = proxmox
logpath = /var/log/daemon.log
# This jail will also use the DEFAULT settings above.
EOF
echo "✅ Main jail configuration created."
echo "------------------------------------------------"


# --- 5. Restart and Verify Fail2ban ---
echo "⚙️  STEP 5: Enabling and restarting Fail2ban service..."
systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
sleep 3 # Give the service a moment to start up

echo "✅ Fail2ban service has been restarted."
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
echo "You can monitor its activity in the log file: /var/log/fail2ban.log"