#!/bin/bash

# Debian 13 (Trixie) Cloud-Init Template Creation Script for Proxmox
# This script fixes console access, ensures password SSH login, and resets machine ID.
# Usage: ./create-debian-template.sh [VM_ID] [STORAGE] [SSH_KEY_FILE]

# --- Configuration ---
VM_ID=${1:-9001}
STORAGE=${2:-local-lvm}
SSH_KEY_FILE=${3:-~/.ssh/id_rsa.pub}
OS_NAME="debian"
OS_VERSION="13"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
IMAGE_FILENAME=$(basename "$IMAGE_URL")
TEMPLATE_FILENAME="${OS_NAME}-${OS_VERSION}-template.img"
ISO_DIR="/var/lib/vz/template/iso"
VM_NAME="${OS_NAME}${OS_VERSION}-cloudinit-template"

echo "Creating Debian ${OS_VERSION} template with VM ID: ${VM_ID}"

# --- Prerequisites ---
# Install required tools if not present
if ! command -v virt-customize &> /dev/null; then
    echo "Installing libguestfs-tools..."
    apt-get update && apt-get install -y libguestfs-tools
fi

# Download Debian 13 cloud image if it doesn't exist
if [ ! -f "${ISO_DIR}/${IMAGE_FILENAME}" ]; then
    echo "Downloading Debian ${OS_VERSION} cloud image..."
    wget -P "${ISO_DIR}" "${IMAGE_URL}"
fi

# --- Image Preparation ---
# Create a working copy of the image
echo "Creating working copy of the image..."
cd /tmp
cp "${ISO_DIR}/${IMAGE_FILENAME}" "${TEMPLATE_FILENAME}"

# Customize the image
echo "Customizing image with fixed console, SSH, and machine ID reset..."
virt-customize -a "${TEMPLATE_FILENAME}" \
    --update \
    --install qemu-guest-agent,curl,wget,vim,htop,net-tools,openssh-server,console-setup \
    --run-command 'systemctl enable qemu-guest-agent' \
    --run-command 'systemctl enable ssh' \
    --run-command 'rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf' \
    --run-command 'sed -i "s/#PasswordAuthentication yes/PasswordAuthentication yes/" /etc/ssh/sshd_config' \
    --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/" /etc/ssh/sshd_config' \
    --run-command 'sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config' \
    --run-command 'sed -i "s/PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config' \
    --run-command 'sed -i "s/#PubkeyAuthentication yes/PubkeyAuthentication yes/" /etc/ssh/sshd_config' \
    --run-command 'sed -i "s/PubkeyAuthentication no/PubkeyAuthentication yes/" /etc/ssh/sshd_config' \
    --run-command 'echo "AuthorizedKeysFile .ssh/authorized_keys" >> /etc/ssh/sshd_config' \
    --run-command 'echo "KbdInteractiveAuthentication yes" >> /etc/ssh/sshd_config' \
    --run-command 'echo "# Console configuration for both serial and VGA" > /etc/default/grub.d/99-console.cfg' \
    --run-command 'echo "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet console=tty1 console=ttyS0,115200n8\"" >> /etc/default/grub.d/99-console.cfg' \
    --run-command 'echo "GRUB_TERMINAL=\"console serial\"" >> /etc/default/grub.d/99-console.cfg' \
    --run-command 'echo "GRUB_SERIAL_COMMAND=\"serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1\"" >> /etc/default/grub.d/99-console.cfg' \
    --run-command 'update-grub' \
    --run-command 'systemctl enable getty@tty1.service' \
    --run-command 'systemctl enable serial-getty@ttyS0.service' \
    --run-command 'echo "" > /etc/machine-id' \
    --run-command 'rm -f /var/lib/dbus/machine-id' \
    --run-command 'ln -s /etc/machine-id /var/lib/dbus/machine-id' \
    --run-command 'rm -f /etc/ssh/ssh_host_*' \
    --run-command 'cloud-init clean --logs --seed' \
    --run-command 'rm -rf /var/lib/cloud/instances/*' \
    --run-command 'rm -rf /var/log/cloud-init*' \
    --run-command 'rm -rf /root/.bash_history' \
    --run-command 'find /home -name ".bash_history" -delete 2>/dev/null || true' \
    --run-command 'truncate -s 0 /var/log/wtmp' \
    --run-command 'truncate -s 0 /var/log/lastlog'

# --- Proxmox VM Creation ---
echo "Creating VM in Proxmox..."
qm create $VM_ID \
    --name "${VM_NAME}" \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=vmbr1 \
    --ostype l26

echo "Importing customized disk..."
qm importdisk $VM_ID "${TEMPLATE_FILENAME}" $STORAGE

echo "Configuring VM hardware..."
qm set $VM_ID \
    --scsihw virtio-scsi-pci \
    --scsi0 ${STORAGE}:vm-${VM_ID}-disk-0,ssd=1 \
    --ide2 ${STORAGE}:cloudinit \
    --boot c \
    --bootdisk scsi0 \
    --serial0 socket \
    --vga serial0 \
    --agent enabled=1 \
    --machine q35 \
    --cpu cputype=host \
    --balloon 0

echo "Setting basic cloud-init configuration..."
qm set $VM_ID --ipconfig0 ip=dhcp

if [ -f "$SSH_KEY_FILE" ]; then
    echo "Adding SSH key from ${SSH_KEY_FILE}..."
    qm set $VM_ID --sshkey "$SSH_KEY_FILE"
fi

echo "Converting VM to template..."
qm template $VM_ID

# --- Cleanup ---
rm -f "${TEMPLATE_FILENAME}"
echo "Debian ${OS_VERSION} template creation complete. VM ID: ${VM_ID}"