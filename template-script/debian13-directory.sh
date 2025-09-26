#!/bin/bash

# Debian 13 (Trixie) Cloud-Init Template Creation Script for Proxmox
# This script fixes console access, ensures password SSH login, and resets machine ID.
# Usage: ./create-debian-template.sh [VM_ID] [STORAGE] [SSH_KEY_FILE]

set -e  # Exit on any error

# --- Configuration ---
VM_ID=${1:-9001}
STORAGE=${2:-local}
SSH_KEY_FILE=${3:-~/.ssh/id_rsa.pub}

# Validate VM_ID is a number
if ! [[ "$VM_ID" =~ ^[0-9]+$ ]]; then
    echo "Error: VM_ID must be a number, got: '$VM_ID'"
    echo "Usage: $0 [VM_ID] [STORAGE] [SSH_KEY_FILE]"
    echo "Example: $0 9001 local ~/.ssh/id_rsa.pub"
    exit 1
fi

# Validate VM_ID range (Proxmox typically uses 100-999999999)
if [ "$VM_ID" -lt 100 ] || [ "$VM_ID" -gt 999999999 ]; then
    echo "Error: VM_ID must be between 100 and 999999999, got: $VM_ID"
    exit 1
fi
OS_NAME="debian"
OS_VERSION="13"
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
IMAGE_FILENAME=$(basename "$IMAGE_URL")
TEMPLATE_FILENAME="${OS_NAME}-${OS_VERSION}-template.img"
ISO_DIR="/var/lib/vz/template/iso"
VM_NAME="${OS_NAME}${OS_VERSION}-cloudinit-template"

echo "Creating Debian ${OS_VERSION} template with VM ID: ${VM_ID}, Storage: ${STORAGE}"
echo "SSH Key: ${SSH_KEY_FILE}"
echo ""

# --- Validation ---
# Check if VM ID already exists
if qm status $VM_ID >/dev/null 2>&1; then
    echo "Error: VM ID $VM_ID already exists. Please use a different ID or remove the existing VM."
    exit 1
fi

# Validate storage exists
if ! pvesm status | grep -q "^$STORAGE "; then
    echo "Error: Storage '$STORAGE' not found. Available storages:"
    pvesm status
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# --- Prerequisites ---
# Install required tools if not present
if ! command -v virt-customize &> /dev/null; then
    echo "Installing libguestfs-tools..."
    apt-get update && apt-get install -y libguestfs-tools
fi

# Create ISO directory if it doesn't exist
mkdir -p "${ISO_DIR}"

# Download Debian 13 cloud image if it doesn't exist
if [ ! -f "${ISO_DIR}/${IMAGE_FILENAME}" ]; then
    echo "Downloading Debian ${OS_VERSION} cloud image..."
    wget -P "${ISO_DIR}" "${IMAGE_URL}"

    # Verify download
    if [ ! -f "${ISO_DIR}/${IMAGE_FILENAME}" ]; then
        echo "Error: Failed to download image"
        exit 1
    fi
fi

# --- Image Preparation ---
# Create a working copy of the image
echo "Creating working copy of the image..."
cd /tmp
cp "${ISO_DIR}/${IMAGE_FILENAME}" "${TEMPLATE_FILENAME}"

# Check if image file exists and is readable
if [ ! -r "${TEMPLATE_FILENAME}" ]; then
    echo "Error: Cannot read image file ${TEMPLATE_FILENAME}"
    exit 1
fi

# Set LIBGUESTFS_BACKEND to avoid permission issues
export LIBGUESTFS_BACKEND=direct

# Create a script for complex customizations
cat > /tmp/customize_script.sh << 'EOF'
#!/bin/bash

# Enable services that exist
enable_service() {
    local service=$1
    if systemctl list-unit-files | grep -q "^${service}"; then
        echo "Enabling ${service}..."
        systemctl enable ${service}
    elif systemctl list-unit-files | grep -q "^${service}.service"; then
        echo "Enabling ${service}.service..."
        systemctl enable ${service}.service
    else
        echo "Service ${service} not found, skipping..."
    fi
}

# Update package lists
echo "Updating packages..."
apt-get update

# Install essential packages
echo "Installing packages..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    qemu-guest-agent \
    curl \
    wget \
    vim \
    htop \
    net-tools \
    openssh-server \
    console-setup \
    cloud-init \
    cloud-utils

# Enable services
enable_service qemu-guest-agent
enable_service ssh
enable_service sshd
enable_service cloud-init
enable_service cloud-init-local
enable_service cloud-config
enable_service cloud-final

# SSH Configuration
echo "Configuring SSH..."
rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf

# Ensure SSH allows both password and key authentication
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Add additional SSH configuration if not present
if ! grep -q "AuthorizedKeysFile" /etc/ssh/sshd_config; then
    echo "AuthorizedKeysFile .ssh/authorized_keys" >> /etc/ssh/sshd_config
fi

if ! grep -q "KbdInteractiveAuthentication" /etc/ssh/sshd_config; then
    echo "KbdInteractiveAuthentication yes" >> /etc/ssh/sshd_config
fi

# Console Configuration
echo "Configuring console..."
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-console.cfg << 'GRUB_EOF'
# Console configuration for both serial and VGA
GRUB_CMDLINE_LINUX_DEFAULT="quiet console=tty1 console=ttyS0,115200n8"
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
GRUB_EOF

update-grub

# Enable console services
systemctl enable getty@tty1.service || true
systemctl enable serial-getty@ttyS0.service || true

# Clean up for template
echo "Cleaning up for template..."
echo "" > /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
cloud-init clean --logs --seed || true
rm -rf /var/lib/cloud/instances/* || true
rm -rf /var/log/cloud-init* || true
rm -rf /root/.bash_history || true
find /home -name ".bash_history" -delete 2>/dev/null || true
truncate -s 0 /var/log/wtmp || true
truncate -s 0 /var/log/lastlog || true

echo "Customization complete!"
EOF

# Make the script executable
chmod +x /tmp/customize_script.sh

# Customize the image using the script
echo "Customizing image with script..."
virt-customize -a "${TEMPLATE_FILENAME}" \
    --copy-in /tmp/customize_script.sh:/tmp \
    --run /tmp/customize_script.sh

if [ $? -ne 0 ]; then
    echo "Error: virt-customize failed"
    rm -f "${TEMPLATE_FILENAME}" /tmp/customize_script.sh
    exit 1
fi

# Clean up the script
rm -f /tmp/customize_script.sh

# --- Proxmox VM Creation ---
echo "Creating VM in Proxmox..."
qm create $VM_ID \
    --name "${VM_NAME}" \
    --memory 2048 \
    --cores 2 \
    --net0 virtio,bridge=vmbr0 \
    --ostype l26

if [ $? -ne 0 ]; then
    echo "Error: Failed to create VM"
    rm -f "${TEMPLATE_FILENAME}"
    exit 1
fi

echo "Importing customized disk..."
# For directory storage, import disk directly
qm importdisk $VM_ID "${TEMPLATE_FILENAME}" $STORAGE --format qcow2

if [ $? -ne 0 ]; then
    echo "Error: Failed to import disk"
    qm destroy $VM_ID
    rm -f "${TEMPLATE_FILENAME}"
    exit 1
fi

# Check VM configuration to see how the disk was imported
echo "Checking VM configuration after disk import..."
VM_CONFIG=$(qm config $VM_ID)
echo "$VM_CONFIG"

echo ""
echo "Checking actual storage contents..."
pvesm list $STORAGE | grep "vm-$VM_ID" || echo "No VM disks found in storage list"

# Extract unused disk reference
UNUSED_DISK=$(echo "$VM_CONFIG" | grep "unused0:" | awk '{print $2}')
if [ ! -z "$UNUSED_DISK" ]; then
    echo "Found unused disk reference: $UNUSED_DISK"

    # For directory storage, the format might be storage:vmid/diskname instead of storage:diskname
    # Let's check the actual disk format and fix the reference
    echo "Checking storage path format..."
    STORAGE_PATH=$(pvesm path $STORAGE:$VM_ID/vm-$VM_ID-disk-0.qcow2 2>/dev/null || echo "")

    if [ ! -z "$STORAGE_PATH" ] && [ -f "$STORAGE_PATH" ]; then
        echo "Disk exists at: $STORAGE_PATH"
        echo "Using correct storage format: $STORAGE:$VM_ID/vm-$VM_ID-disk-0.qcow2"
        CORRECT_DISK_REF="$STORAGE:$VM_ID/vm-$VM_ID-disk-0.qcow2"
    else
        # Try alternative format
        STORAGE_PATH=$(pvesm path $STORAGE:vm-$VM_ID-disk-0.qcow2 2>/dev/null || echo "")
        if [ ! -z "$STORAGE_PATH" ] && [ -f "$STORAGE_PATH" ]; then
            echo "Disk exists at: $STORAGE_PATH"
            echo "Using storage format: $STORAGE:vm-$VM_ID-disk-0.qcow2"
            CORRECT_DISK_REF="$STORAGE:vm-$VM_ID-disk-0.qcow2"
        else
            echo "Cannot find disk file, will try with original reference"
            CORRECT_DISK_REF="$UNUSED_DISK"
        fi
    fi

    echo "Attempting to move unused disk to scsi0 with reference: $CORRECT_DISK_REF"

    # First, try to just move without deleting unused0
    if qm set $VM_ID --scsi0 "$CORRECT_DISK_REF"; then
        echo "Successfully attached disk to scsi0"
        # Now try to clean up the unused0 reference
        qm set $VM_ID --delete unused0 || echo "Note: Could not remove unused0 reference (this is usually fine)"
    else
        echo "Failed to attach disk. Let's try a different approach..."

        # Check if the VM already has the disk attached somewhere
        if echo "$VM_CONFIG" | grep -q "scsi0:"; then
            echo "VM already has a scsi0 disk attached"
        else
            # Try to manually construct the correct path
            echo "Trying manual disk attachment..."
            # Sometimes we need to use the exact format that Proxmox expects
            for disk_format in \
                "$STORAGE:$VM_ID/vm-$VM_ID-disk-0.qcow2" \
                "$STORAGE:vm-$VM_ID-disk-0.qcow2" \
                "$UNUSED_DISK"
            do
                echo "Trying format: $disk_format"
                if qm set $VM_ID --scsi0 "$disk_format" 2>/dev/null; then
                    echo "Success with format: $disk_format"
                    qm set $VM_ID --delete unused0 2>/dev/null || true
                    break
                fi
            done
        fi
    fi
else
    echo "No unused disk found in VM configuration"
fi

# Verify the final configuration
echo ""
echo "Final VM configuration:"
qm config $VM_ID | grep -E "(scsi0|unused)"

echo "Configuring VM hardware..."
qm set $VM_ID \
    --scsihw virtio-scsi-pci \
    --boot order=scsi0 \
    --serial0 socket \
    --vga serial0 \
    --agent enabled=1 \
    --machine q35 \
    --cpu cputype=host \
    --balloon 0

if [ $? -ne 0 ]; then
    echo "Error: Failed to configure VM hardware"
    qm destroy $VM_ID
    rm -f "${TEMPLATE_FILENAME}"
    exit 1
fi

# Create cloud-init drive - this is crucial!
echo "Creating cloud-init drive..."
qm set $VM_ID --ide2 ${STORAGE}:cloudinit

if [ $? -ne 0 ]; then
    echo "Error: Failed to create cloud-init drive"
    qm destroy $VM_ID
    rm -f "${TEMPLATE_FILENAME}"
    exit 1
fi

echo "Setting basic cloud-init configuration..."
qm set $VM_ID --ipconfig0 ip=dhcp

# Set a default user (important for cloud-init)
qm set $VM_ID --ciuser root
qm set $VM_ID --cipassword $(openssl rand -base64 12)

if [ -f "$SSH_KEY_FILE" ]; then
    echo "Adding SSH key from ${SSH_KEY_FILE}..."
    qm set $VM_ID --sshkeys "$SSH_KEY_FILE"
else
    echo "Warning: SSH key file not found at ${SSH_KEY_FILE}"
fi

# Resize the disk to a more reasonable size (optional)
echo "Resizing disk to 20GB..."
qm resize $VM_ID scsi0 20G

echo "Converting VM to template..."
qm template $VM_ID

if [ $? -ne 0 ]; then
    echo "Error: Failed to convert VM to template"
    exit 1
fi

# --- Cleanup ---
rm -f "${TEMPLATE_FILENAME}"
echo "Debian ${OS_VERSION} template creation complete. VM ID: ${VM_ID}"
echo ""
echo "Template created successfully! You can now:"
echo "1. Clone this template to create new VMs"
echo "2. Customize cloud-init settings before starting cloned VMs"
echo "3. The template includes:"
echo "   - QEMU Guest Agent (enabled if available)"
echo "   - SSH access with both key and password authentication"
echo "   - Serial console access"
echo "   - Cloud-init support"
echo ""
echo "To test the template:"
echo "1. Clone it: qm clone $VM_ID <new_vm_id> --name test-vm"
echo "2. Configure cloud-init settings for the cloned VM"
echo "3. Start the cloned VM"