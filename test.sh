# Complete macOS VPN Auto-Connection Setup

This guide is for macOS only. All files are ready to copy-paste.

---

## PART 1: COMPLETE REMOVAL (If Already Installed)

```bash
# Stop watchdog first
sudo launchctl bootout system /Library/LaunchDaemons/com.autovpn.watchdog.plist 2>/dev/null || true
sleep 3

# Stop daemon
sudo launchctl bootout system /Library/LaunchDaemons/com.autovpn.daemon.plist 2>/dev/null || true
sleep 3

# Kill all processes
sudo pkill -9 -f "openvpn --config"
sudo pkill -9 -f autovpn
sleep 2

# Remove immutable flags
sudo chflags -R nouchg /Library/LaunchDaemons/com.autovpn.* 2>/dev/null || true
sudo chflags -R nouchg /Users/vpn/vpntest/mac.sh 2>/dev/null || true
sudo chflags -R nouchg /usr/local/bin/autovpn-watchdog.sh 2>/dev/null || true
sudo chflags -R nouchg /var/local/autovpn-backup 2>/dev/null || true
sleep 2

# Delete all files
sudo rm -f /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo rm -f /Library/LaunchDaemons/com.autovpn.watchdog.plist
sudo rm -f /Users/vpn/vpntest/mac.sh
sudo rm -f /usr/local/bin/autovpn-watchdog.sh
sudo rm -rf /var/local/autovpn-backup
sudo rm -f /var/log/autovpn-*.out
sudo rm -f /var/log/autovpn-*.err

echo "✅ Complete removal done"
```

---

## PART 2: FRESH SETUP

### Step 1: Install OpenVPN

```bash
brew install openvpn
openvpn --version
```

### Step 2: Create Directories

```bash
mkdir -p /Users/vpn/vpntest
sudo mkdir -p /var/local/autovpn-backup
sudo chown root:wheel /var/local/autovpn-backup
sudo chmod 700 /var/local/autovpn-backup
```

### Step 3: Place Your VPN Config Files

Copy your three `.ovpn` files to `/Users/vpn/vpntest/`:
- `BLR.ovpn`
- `DHA.ovpn`
- `JK.ovpn`

Verify:
```bash
ls -la /Users/vpn/vpntest/*.ovpn
```

---

## FILE 1: Main VPN Script - mac.sh

Create file: `/Users/vpn/vpntest/mac.sh`

```bash
sudo nano /Users/vpn/vpntest/mac.sh
```

Copy and paste all content below, then press `Ctrl+X`, `Y`, `Enter`:

```bash
#!/opt/homebrew/bin/bash
# VPN Auto-Connection Script for macOS

set -euo pipefail

# --- VPN configs and expected public IPs ---
VPNS_IN_ORDER=(
    "BLR" "/Users/vpn/vpntest/BLR.ovpn" "106.51.18.5"
    "DHA" "/Users/vpn/vpntest/DHA.ovpn" "203.101.45.78"
    "JK"  "/Users/vpn/vpntest/JK.ovpn"  "192.168.1.3"
)

# --- Webhook URL (Base64 encoded for Google Chat) ---
WEBHOOK_URL_BASE64="aHR0cHM6Ly9jaGF0Lmdvb2dsZWFwaXMuY29tL3YxL3NwYWNlcy9BQVFBNmJrWWxtUS9tZXNzYWdlcz9rZXk9QUl6YVN5RGRJMGhDWnRFNnZ5U2pNbS1XRWZScTNDUHpxS3Fxc0hJJnRva2VuPVNGcXU2UTkzN0JFRnFoOVUtdWt5Y2EtN0xDTGZjQllJWHZ5Uk9td2ZmY0U="
WEBHOOK_URL="$(echo "$WEBHOOK_URL_BASE64" | base64 --decode | tr -d '\n\r')"

# --- Logging ---
LOGFILE="/var/log/autovpn-daemon.out"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

# --- Chat Notification Function ---
send_chat_message() {
    local MESSAGE="$1"
    curl -s -X POST -H 'Content-Type: application/json' \
        -d "{\"text\": \"$MESSAGE\"}" "$WEBHOOK_URL" >/dev/null 2>&1 || true
}

# --- Desktop Notification ---
send_desktop_notification() {
    local MESSAGE="$1"
    osascript -e "display notification \"$MESSAGE\" with title \"VPN Auto Connect\""
}

# --- Check Public IP ---
check_public_ip() {
    local EXPECTED_IP="$1"
    local ACTUAL_IP
    ACTUAL_IP=$(curl -4 -s --max-time 10 https://ifconfig.me/ip 2>/dev/null || echo "")
    [[ "$ACTUAL_IP" == "$EXPECTED_IP" ]]
}

# --- Kill OpenVPN ---
kill_vpn() {
    sudo pkill -f "openvpn --config" || true
}

# --- Get System Info ---
get_system_info() {
    HOSTNAME=$(hostname)
    USERNAME=$(whoami)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    OS_INFO="$(sw_vers -productName) $(sw_vers -productVersion)"
    
    # Network info
    PRIMARY_IFACE=$(route get default 2>/dev/null | awk '/interface: / {print $2}' || echo "unknown")
    LOCAL_IP=$(ipconfig getifaddr "$PRIMARY_IFACE" 2>/dev/null || echo "Unknown")
    
    # Determine connection type
    CONN_TYPE_INFO=""
    if networksetup -getairportnetwork "$PRIMARY_IFACE" 2>/dev/null | grep -q "Current Wi-Fi Network"; then
        SSID=$(networksetup -getairportnetwork "$PRIMARY_IFACE" 2>/dev/null | awk -F': ' '{print $2}' || echo "Unknown")
        CONN_TYPE_INFO="📶 Wi-Fi: $SSID"
    else
        CONN_TYPE_INFO="📶 Ethernet"
    fi
}

# --- Disconnect Internet (Emergency) ---
disconnect_internet() {
    local PRIMARY_IFACE
    PRIMARY_IFACE=$(route get default 2>/dev/null | awk '/interface: / {print $2}')
    if [ -n "$PRIMARY_IFACE" ]; then
        log "Disconnecting internet interface: $PRIMARY_IFACE"
        sudo ifconfig "$PRIMARY_IFACE" down
    fi
}

# --- MAIN LOGIC ---
log "===== VPN Auto-Connection Starting ====="
get_system_info

log "Hostname: $HOSTNAME | User: $USERNAME | OS: $OS_INFO"
log "Local IP: $LOCAL_IP | Interface: $PRIMARY_IFACE"

# Kill any existing OpenVPN
kill_vpn
sleep 2

# Try each VPN in order
VPN_CONNECTED=0

for ((i=0; i<${#VPNS_IN_ORDER[@]}; i+=3)); do
    VPN_NAME="${VPNS_IN_ORDER[i]}"
    CONFIG="${VPNS_IN_ORDER[i+1]}"
    EXPECTED_IP="${VPNS_IN_ORDER[i+2]}"
    
    log "Attempting to connect to $VPN_NAME..."
    send_desktop_notification "Connecting to $VPN_NAME..."
    
    # Start OpenVPN
    sudo /opt/homebrew/opt/openvpn/sbin/openvpn --config "$CONFIG" --daemon
    sleep 8
    
    # Check public IP
    ACTUAL_IP=$(curl -4 -s --max-time 10 https://ifconfig.me/ip 2>/dev/null || echo "")
    log "Detected Public IP: $ACTUAL_IP (Expected: $EXPECTED_IP)"
    
    if check_public_ip "$EXPECTED_IP"; then
        VPN_CONNECTED=1
        log "✅ Successfully connected to $VPN_NAME"
        send_desktop_notification "✅ Connected to $VPN_NAME"
        
        # Send success notification
        MESSAGE="✅ *VPN Connection Successful*
👤 User: *$USERNAME*
💻 Host: $HOSTNAME
📱 OS: $OS_INFO
🕐 $TIMESTAMP

📡 *Network Details*
📌 Interface: $PRIMARY_IFACE
$CONN_TYPE_INFO
🌐 Local IP: $LOCAL_IP
🌍 Public IP: $ACTUAL_IP

🔒 *VPN Status*
✅ Connected to *$VPN_NAME*
Expected IP: $EXPECTED_IP"
        
        send_chat_message "$MESSAGE"
        break
    else
        log "❌ Failed to connect to $VPN_NAME"
        kill_vpn
        sleep 2
    fi
done

# If all VPNs failed
if [ "$VPN_CONNECTED" -eq 0 ]; then
    log "❌ All VPNs failed to connect!"
    send_desktop_notification "⚠️ All VPNs failed! Disconnecting internet..."
    
    MESSAGE="❌ *VPN Connection Failed - Internet Disconnected*
👤 User: *$USERNAME*
💻 Host: $HOSTNAME
📱 OS: $OS_INFO
🕐 $TIMESTAMP

📡 *Network Details*
📌 Interface: $PRIMARY_IFACE
$CONN_TYPE_INFO
🌐 Local IP: $LOCAL_IP
🌍 Public IP: Unable to connect

🔒 *VPN Status*
❌ All VPNs failed to connect
⚠️ Internet has been disconnected to prevent IP leaks"
    
    send_chat_message "$MESSAGE"
    disconnect_internet
fi

log "===== VPN Auto-Connection Complete ====="
```

Set permissions:
```bash
sudo chown root:wheel /Users/vpn/vpntest/mac.sh
sudo chmod 700 /Users/vpn/vpntest/mac.sh
sudo chflags uchg /Users/vpn/vpntest/mac.sh
ls -lo /Users/vpn/vpntest/mac.sh
```

---

## FILE 2: Watchdog Script - autovpn-watchdog.sh

Create file: `/usr/local/bin/autovpn-watchdog.sh`

```bash
sudo nano /usr/local/bin/autovpn-watchdog.sh
```

Copy and paste all content below, then press `Ctrl+X`, `Y`, `Enter`:

```bash
#!/bin/bash
# Enhanced Watchdog for VPN Auto-Connection
# Monitors and protects VPN system from tampering

set -euo pipefail

# --- Configuration ---
TARGET_SCRIPT="/Users/vpn/vpntest/mac.sh"
DAEMON_PLIST="/Library/LaunchDaemons/com.autovpn.daemon.plist"
DAEMON_LABEL="system/com.autovpn.daemon"
WATCHDOG_PLIST="/Library/LaunchDaemons/com.autovpn.watchdog.plist"

BACKUP_DIR="/var/local/autovpn-backup"
SCRIPT_BKP="$BACKUP_DIR/mac.sh.bak"
PLIST_BKP="$BACKUP_DIR/com.autovpn.daemon.plist.bak"

WEBHOOK_URL_BASE64="aHR0cHM6Ly9jaGF0Lmdvb2dsZWFwaXMuY29tL3YxL3NwYWNlcy9BQVFBNmJrWWxtUS9tZXNzYWdlcz9rZXk9QUl6YVN5RGRJMGhDWnRFNnZ5U2pNbS1XRWZScTNDUHpxS3Fxc0hJJnRva2VuPVNGcXU2UTkzN0JFRnFoOVUtdWt5Y2EtN0xDTGZjQllJWHZ5Uk9td2ZmY0U="
WEBHOOK_URL="$(echo "$WEBHOOK_URL_BASE64" | base64 --decode | tr -d '\n\r')"

EXPECTED_SCRIPT_OWNER="root:wheel"
EXPECTED_SCRIPT_MODE="700"
EXPECTED_PLIST_OWNER="root:wheel"
EXPECTED_PLIST_MODE="644"

SLEEP_INTERVAL=5

# --- Utility Functions ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/autovpn-watchdog.out
}

send_alert() {
    local MSG="$1"
    curl -s -X POST -H 'Content-Type: application/json' \
         -d "{\"text\": \"$MSG\"}" "$WEBHOOK_URL" >/dev/null 2>&1 || true
}

ensure_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        sudo chown root:wheel "$BACKUP_DIR"
        sudo chmod 700 "$BACKUP_DIR"
    fi
}

backup_files_if_needed() {
    ensure_backup_dir
    if [ -f "$TARGET_SCRIPT" ] && [ ! -f "$SCRIPT_BKP" ]; then
        cp -p "$TARGET_SCRIPT" "$SCRIPT_BKP"
        sudo chown root:wheel "$SCRIPT_BKP"
        sudo chmod 600 "$SCRIPT_BKP"
        log "Created script backup: $SCRIPT_BKP"
    fi
    if [ -f "$DAEMON_PLIST" ] && [ ! -f "$PLIST_BKP" ]; then
        cp -p "$DAEMON_PLIST" "$PLIST_BKP"
        sudo chown root:wheel "$PLIST_BKP"
        sudo chmod 600 "$PLIST_BKP"
        log "Created plist backup: $PLIST_BKP"
    fi
}

restore_script_if_missing() {
    if [ ! -f "$TARGET_SCRIPT" ]; then
        if [ -f "$SCRIPT_BKP" ]; then
            sudo cp "$SCRIPT_BKP" "$TARGET_SCRIPT"
            sudo chown root:wheel "$TARGET_SCRIPT"
            sudo chmod "$EXPECTED_SCRIPT_MODE" "$TARGET_SCRIPT"
            sudo chflags uchg "$TARGET_SCRIPT" 2>/dev/null || true
            log "🚨 Restored $TARGET_SCRIPT from backup (WAS DELETED!)"
            send_alert "🚨 CRITICAL: VPN script was deleted and restored!
📝 File: mac.sh
⏰ $(date '+%Y-%m-%d %H:%M:%S')
🖥️ Host: $(hostname)
🛡️ Watchdog automatically restored it"
        else
            log "ERROR: $TARGET_SCRIPT missing and no backup available"
            send_alert "❌ CRITICAL: VPN script missing with NO BACKUP!
📝 File: mac.sh
⏰ $(date '+%Y-%m-%d %H:%M:%S')
🖥️ Host: $(hostname)"
        fi
    fi
}

restore_plist_if_missing() {
    if [ ! -f "$DAEMON_PLIST" ]; then
        if [ -f "$PLIST_BKP" ]; then
            sudo cp "$PLIST_BKP" "$DAEMON_PLIST"
            sudo chown root:wheel "$DAEMON_PLIST"
            sudo chmod "$EXPECTED_PLIST_MODE" "$DAEMON_PLIST"
            sudo chflags uchg "$DAEMON_PLIST" 2>/dev/null || true
            log "🚨 Restored $DAEMON_PLIST from backup (WAS DELETED!)"
            send_alert "🚨 CRITICAL: LaunchDaemon plist was deleted and restored!
📝 File: com.autovpn.daemon.plist
⏰ $(date '+%Y-%m-%d %H:%M:%S')
🖥️ Host: $(hostname)
🛡️ Watchdog automatically restored and reloaded it"
            sudo launchctl bootstrap system "$DAEMON_PLIST" 2>/dev/null || true
            sudo launchctl kickstart -k "$DAEMON_LABEL" 2>/dev/null || true
        else
            log "ERROR: $DAEMON_PLIST missing and no backup"
            send_alert "❌ CRITICAL: Daemon plist missing with NO BACKUP!
📝 File: com.autovpn.daemon.plist
⏰ $(date '+%Y-%m-%d %H:%M:%S')
🖥️ Host: $(hostname)"
        fi
    fi
}

ensure_ownership_and_mode() {
    if [ -f "$TARGET_SCRIPT" ]; then
        CURRENT_OWNER=$(stat -f '%Su:%Sg' "$TARGET_SCRIPT" 2>/dev/null || echo "unknown:unknown")
        CURRENT_MODE=$(stat -f '%A' "$TARGET_SCRIPT" 2>/dev/null || echo "unknown")
        
        if [ "$CURRENT_OWNER" != "$EXPECTED_SCRIPT_OWNER" ]; then
            sudo chown root:wheel "$TARGET_SCRIPT" 2>/dev/null || true
            log "⚠️ Fixed owner of $TARGET_SCRIPT (was: $CURRENT_OWNER)"
            send_alert "⚠️ Permission Alert: Script owner changed!
📝 File: mac.sh
👤 Changed to: $CURRENT_OWNER
✅ Restored to: root:wheel"
        fi
        
        if [ "$CURRENT_MODE" != "$EXPECTED_SCRIPT_MODE" ]; then
            sudo chmod "$EXPECTED_SCRIPT_MODE" "$TARGET_SCRIPT" 2>/dev/null || true
            log "⚠️ Fixed mode of $TARGET_SCRIPT (was: $CURRENT_MODE)"
            send_alert "⚠️ Permission Alert: Script permissions changed!
📝 File: mac.sh
🔒 Changed to: $CURRENT_MODE
✅ Restored to: $EXPECTED_SCRIPT_MODE"
        fi
        
        sudo chflags uchg "$TARGET_SCRIPT" 2>/dev/null || true
    fi
    
    if [ -f "$DAEMON_PLIST" ]; then
        CURRENT_OWNER_P=$(stat -f '%Su:%Sg' "$DAEMON_PLIST" 2>/dev/null || echo "unknown:unknown")
        CURRENT_MODE_P=$(stat -f '%A' "$DAEMON_PLIST" 2>/dev/null || echo "unknown")
        
        if [ "$CURRENT_OWNER_P" != "$EXPECTED_PLIST_OWNER" ]; then
            sudo chown root:wheel "$DAEMON_PLIST" 2>/dev/null || true
            log "⚠️ Fixed owner of $DAEMON_PLIST (was: $CURRENT_OWNER_P)"
        fi
        
        if [ "$CURRENT_MODE_P" != "$EXPECTED_PLIST_MODE" ]; then
            sudo chmod "$EXPECTED_PLIST_MODE" "$DAEMON_PLIST" 2>/dev/null || true
            log "⚠️ Fixed mode of $DAEMON_PLIST (was: $CURRENT_MODE_P)"
        fi
        
        sudo chflags uchg "$DAEMON_PLIST" 2>/dev/null || true
    fi
}

is_openvpn_running() {
    pgrep -f "/opt/homebrew/opt/openvpn/sbin/openvpn --config" >/dev/null 2>&1
    return $?
}

restart_vpn_daemon_if_needed() {
    if ! is_openvpn_running; then
        log "🔄 OpenVPN process not running - restarting daemon"
        send_alert "🔄 OpenVPN Process Alert
⏰ $(date '+%Y-%m-%d %H:%M:%S')
🖥️ Host: $(hostname)
ℹ️ OpenVPN process died unexpectedly
🔧 Watchdog is restarting the daemon..."
        sudo launchctl kickstart -k "$DAEMON_LABEL" 2>/dev/null || true
        sleep 2
    fi
}

ensure_watchdog_is_loaded() {
    if [ -f "$WATCHDOG_PLIST" ]; then
        sudo chown root:wheel "$WATCHDOG_PLIST" 2>/dev/null || true
        sudo chmod 644 "$WATCHDOG_PLIST" 2>/dev/null || true
        sudo chflags uchg "$WATCHDOG_PLIST" 2>/dev/null || true
    fi
}

mainloop() {
    log "🛡️ Watchdog starting: monitoring $TARGET_SCRIPT and $DAEMON_PLIST"
    backup_files_if_needed
    
    while true; do
        restore_script_if_missing
        restore_plist_if_missing
        ensure_watchdog_is_loaded
        ensure_ownership_and_mode
        restart_vpn_daemon_if_needed
        sleep "$SLEEP_INTERVAL"
    done
}

# --- Check if running as root ---
if [ "$EUID" -ne 0 ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

mainloop
```

Set permissions:
```bash
sudo chown root:wheel /usr/local/bin/autovpn-watchdog.sh
sudo chmod 700 /usr/local/bin/autovpn-watchdog.sh
sudo chflags uchg /usr/local/bin/autovpn-watchdog.sh
ls -lo /usr/local/bin/autovpn-watchdog.sh
```

---

## FILE 3: Daemon LaunchPlist

Create file: `/Library/LaunchDaemons/com.autovpn.daemon.plist`

```bash
sudo nano /Library/LaunchDaemons/com.autovpn.daemon.plist
```

Copy and paste, then `Ctrl+X`, `Y`, `Enter`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.autovpn.daemon</string>

    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/bash</string>
        <string>/Users/vpn/vpntest/mac.sh</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>NetworkState</key>
        <true/>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>StandardOutPath</key>
    <string>/var/log/autovpn-daemon.out</string>

    <key>StandardErrorPath</key>
    <string>/var/log/autovpn-daemon.err</string>
</dict>
</plist>
```

Set permissions:
```bash
sudo chown root:wheel /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo chmod 644 /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo chflags uchg /Library/LaunchDaemons/com.autovpn.daemon.plist
```

---

## FILE 4: Watchdog LaunchPlist

Create file: `/Library/LaunchDaemons/com.autovpn.watchdog.plist`

```bash
sudo nano /Library/LaunchDaemons/com.autovpn.watchdog.plist
```

Copy and paste, then `Ctrl+X`, `Y`, `Enter`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.autovpn.watchdog</string>

  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/autovpn-watchdog.sh</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>

  <key>StandardOutPath</key>
  <string>/var/log/autovpn-watchdog.out</string>

  <key>StandardErrorPath</key>
  <string>/var/log/autovpn-watchdog.err</string>

  <key>Nice</key>
  <integer>-10</integer>
</dict>
</plist>
```

Set permissions:
```bash
sudo chown root:wheel /Library/LaunchDaemons/com.autovpn.watchdog.plist
sudo chmod 644 /Library/LaunchDaemons/com.autovpn.watchdog.plist
sudo chflags uchg /Library/LaunchDaemons/com.autovpn.watchdog.plist
```

---

## FINAL SETUP: Load Everything

```bash
# Load both daemons
sudo launchctl bootstrap system /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.autovpn.watchdog.plist

sleep 5

# Verify they're running
sudo launchctl list | grep autovpn
```

Should show:
```
com.autovpn.daemon
com.autovpn.watchdog
```

### Verify Everything is Working

```bash
# Check running processes
ps aux | grep -E "openvpn|autovpn" | grep -v grep

# Check daemon logs
tail -20 /var/log/autovpn-daemon.out
tail -20 /var/log/autovpn-daemon.err

# Check watchdog logs
tail -20 /var/log/autovpn-watchdog.out
tail -20 /var/log/autovpn-watchdog.err
```

---

## COMPLETE REMOVAL

When you want to remove everything:

```bash
# Stop both daemons
sudo launchctl bootout system /Library/LaunchDaemons/com.autovpn.watchdog.plist 2>/dev/null || true
sudo launchctl bootout system /Library/LaunchDaemons/com.autovpn.daemon.plist 2>/dev/null || true
sleep 3

# Kill processes
sudo pkill -9 -f "openvpn --config"
sudo pkill -9 -f autovpn
sleep 2

# Remove immutable flags
sudo chflags -R nouchg /Library/LaunchDaemons/com.autovpn.* 2>/dev/null || true
sudo chflags -R nouchg /Users/vpn/vpntest/mac.sh 2>/dev/null || true
sudo chflags -R nouchg /usr/local/bin/autovpn-watchdog.sh 2>/dev/null || true
sudo chflags -R nouchg /var/local/autovpn-backup 2>/dev/null || true
sleep 2

# Delete everything
sudo rm -f /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo rm -f /Library/LaunchDaemons/com.autovpn.watchdog.plist
sudo rm -f /Users/vpn/vpntest/mac.sh
sudo rm -f /usr/local/bin/autovpn-watchdog.sh
sudo rm -rf /var/local/autovpn-backup
sudo rm -f /var/log/autovpn-*.out
sudo rm -f /var/log/autovpn-*.err

# Verify
ls /Library/LaunchDaemons/com.autovpn* 2>&1
ps aux | grep autovpn

echo "✅ Complete removal done"
```

---

## Notification Features

The system sends Google Chat notifications for:

✅ **Successful VPN Connection** - System info + VPN name + Public IP
❌ **All VPNs Failed** - Alert with public IP and disconnect action
🚨 **File Deleted** - Watchdog restores and notifies
⚠️ **Permission Changed** - Watchdog fixes and notifies
🔄 **Process Died** - Watchdog restarts and notifies
⏰ **System Info** - Hostname, user, OS, timestamp included

All notifications include: User, Host, OS, Timestamp, Network Details, VPN Status
