#!/bin/bash

# NAT Port Forwarding Manager for Proxmox
# Usage: ./nat_manager.sh [add|remove|list|save|restore]

# Configuration
INTERFACE="vmbr0"  # Change this to your public interface
RULES_FILE="/etc/iptables/nat_rules.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        echo "Please run: sudo $0 $@"
        exit 1
    fi
}

# Function to install required packages
install_dependencies() {
    echo -e "${BLUE}Installing netfilter-persistent...${NC}"
    apt update
    apt install -y iptables-persistent netfilter-persistent
    
    # Create rules directory if it doesn't exist
    mkdir -p /etc/iptables
    touch "$RULES_FILE"
    
    echo -e "${GREEN}Dependencies installed successfully!${NC}"
}

# Function to add a new NAT rule
add_rule() {
    read -p "Enter VM IP address: " vm_ip
    read -p "Enter VM port: " vm_port
    read -p "Enter public port: " public_port
    read -p "Enter protocol (tcp/udp/both) [default: tcp]: " protocol
    
    # Default to tcp if empty
    protocol=${protocol:-tcp}
    
    # Validate inputs
    if [[ ! $vm_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid IP address format${NC}"
        return 1
    fi
    
    if ! [[ "$vm_port" =~ ^[0-9]+$ ]] || [ "$vm_port" -lt 1 ] || [ "$vm_port" -gt 65535 ]; then
        echo -e "${RED}Error: VM port must be a number between 1-65535${NC}"
        return 1
    fi
    
    if ! [[ "$public_port" =~ ^[0-9]+$ ]] || [ "$public_port" -lt 1 ] || [ "$public_port" -gt 65535 ]; then
        echo -e "${RED}Error: Public port must be a number between 1-65535${NC}"
        return 1
    fi
    
    # Check if public port is already in use
    if grep -q "dport $public_port" "$RULES_FILE" 2>/dev/null; then
        echo -e "${RED}Error: Public port $public_port is already in use${NC}"
        return 1
    fi
    
    # Add iptables rules
    if [ "$protocol" = "both" ] || [ "$protocol" = "tcp" ]; then
        iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport $public_port -j DNAT --to $vm_ip:$vm_port
        echo "tcp $public_port $vm_ip $vm_port" >> "$RULES_FILE"
        echo -e "${GREEN}Added TCP rule: $public_port -> $vm_ip:$vm_port${NC}"
    fi
    
    if [ "$protocol" = "both" ] || [ "$protocol" = "udp" ]; then
        iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport $public_port -j DNAT --to $vm_ip:$vm_port
        echo "udp $public_port $vm_ip $vm_port" >> "$RULES_FILE"
        echo -e "${GREEN}Added UDP rule: $public_port -> $vm_ip:$vm_port${NC}"
    fi
    
    # Auto-save rules
    save_rules
}

# Function to remove a NAT rule
remove_rule() {
    list_rules
    echo
    read -p "Enter public port to remove: " public_port
    
    if ! [[ "$public_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid port number${NC}"
        return 1
    fi
    
    # Remove from iptables
    iptables -t nat -D PREROUTING -i $INTERFACE -p tcp --dport $public_port -j DNAT --to-destination $(grep "tcp $public_port" "$RULES_FILE" | awk '{print $3":"$4}') 2>/dev/null
    iptables -t nat -D PREROUTING -i $INTERFACE -p udp --dport $public_port -j DNAT --to-destination $(grep "udp $public_port" "$RULES_FILE" | awk '{print $3":"$4}') 2>/dev/null
    
    # Remove from rules file
    sed -i "/^tcp $public_port /d" "$RULES_FILE"
    sed -i "/^udp $public_port /d" "$RULES_FILE"
    
    echo -e "${GREEN}Removed rules for port $public_port${NC}"
    
    # Auto-save rules
    save_rules
}

# Function to list current rules
list_rules() {
    echo -e "${BLUE}Current NAT Rules:${NC}"
    echo -e "${BLUE}=================${NC}"
    
    if [ ! -f "$RULES_FILE" ] || [ ! -s "$RULES_FILE" ]; then
        echo -e "${YELLOW}No rules configured${NC}"
        return
    fi
    
    printf "%-8s %-12s %-15s %-8s\n" "Protocol" "Public Port" "VM IP" "VM Port"
    printf "%-8s %-12s %-15s %-8s\n" "--------" "-----------" "-----" "-------"
    
    while read -r protocol public_port vm_ip vm_port; do
        [ -z "$protocol" ] && continue
        printf "%-8s %-12s %-15s %-8s\n" "$protocol" "$public_port" "$vm_ip" "$vm_port"
    done < "$RULES_FILE"
}

# Function to save rules persistently
save_rules() {
    echo -e "${BLUE}Saving iptables rules...${NC}"
    netfilter-persistent save
    echo -e "${GREEN}Rules saved successfully!${NC}"
}

# Function to restore rules from file
restore_rules() {
    echo -e "${BLUE}Restoring NAT rules...${NC}"
    
    if [ ! -f "$RULES_FILE" ]; then
        echo -e "${YELLOW}No rules file found${NC}"
        return
    fi
    
    # Clear existing NAT rules for our interface
    iptables -t nat -F PREROUTING
    
    # Restore rules from file
    while read -r protocol public_port vm_ip vm_port; do
        [ -z "$protocol" ] && continue
        iptables -t nat -A PREROUTING -i $INTERFACE -p $protocol --dport $public_port -j DNAT --to $vm_ip:$vm_port
        echo -e "${GREEN}Restored: $protocol $public_port -> $vm_ip:$vm_port${NC}"
    done < "$RULES_FILE"
    
    save_rules
}

# Function to show usage
show_usage() {
    echo -e "${BLUE}NAT Port Forwarding Manager${NC}"
    echo -e "${BLUE}===========================${NC}"
    echo
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  add     - Add a new port forwarding rule"
    echo "  remove  - Remove a port forwarding rule"
    echo "  list    - List all current rules"
    echo "  save    - Save current iptables rules"
    echo "  restore - Restore rules from saved configuration"
    echo "  install - Install required dependencies"
    echo
    echo "Examples:"
    echo "  $0 add     # Interactive add new rule"
    echo "  $0 list    # Show all rules"
    echo "  $0 remove  # Interactive remove rule"
}

# Main script logic
case "$1" in
    "add")
        check_root
        add_rule
        ;;
    "remove")
        check_root
        remove_rule
        ;;
    "list")
        list_rules
        ;;
    "save")
        check_root
        save_rules
        ;;
    "restore")
        check_root
        restore_rules
        ;;
    "install")
        check_root
        install_dependencies
        ;;
    *)
        show_usage
        ;;
esac