Setup Instructions:

First-time Setup
```bash
# Download and make the script executable
wget -O nat_manager.sh <get raw from this link>
chmod +x nat_manager.sh

# Install dependencies (run once)
 ./nat_manager.sh install
```

Add a new rule:
```bash
 ./nat_manager.sh add
# It will ask for:
# - VM IP address: 10.10.100.150
# - VM port: 22
# - Public port: 2201
# - Protocol: tcp (or udp, or both)
```

List all rules:

```bash
./nat_manager.sh list
```

Remove a rule:
```bash
 ./nat_manager.sh remove
# Shows current rules and asks which port to remove
```

---
Useful command:

Check rule exist:
```bash
 iptables -t nat -L PREROUTING -n
```
