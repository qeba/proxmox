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