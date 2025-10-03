# Setup

Run the following single command. This will download the script and immediately execute it with sudo privileges.

First download
```
wget https://raw.githubusercontent.com/qeba/proxmox/main/network/security/fail-ban-setup.sh
```

give permission:
```
chmod +x fail-ban-setup.sh
```

then, run the script:
```
sudo ./fail-ban-setup.sh
```

input all the required value max-retry and ban time. 


# Useful command

View Overall Status:
```
fail2ban-client status
```

View Status of a Specific Jail:
```
# For the Proxmox Web UI jail
 fail2ban-client status proxmox

# For the SSH jail
 fail2ban-client status sshd
```

Manually Unban an IP Address
 ```
  fail2ban-client set proxmox unbanip <IP_ADDRESS>
 ```
_Replace <IP_ADDRESS> with the actual IP_