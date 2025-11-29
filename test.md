# Complete macOS VPN Auto-Connection Setup & Removal Guide

**IMPORTANT:** Follow these steps EXACTLY in order. Do not skip steps.

---

## PART 1: COMPLETE REMOVAL (Start Fresh)

If you already have this system installed, remove it completely first.

### Removal Step 1: Disable the Watchdog (MUST DO FIRST)

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.autovpn.watchdog.plist
sleep 3
```

### Removal Step 2: Disable the Daemon

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.autovpn.daemon.plist
sleep 3
```

### Removal Step 3: Kill All OpenVPN Processes

```bash
sudo pkill -9 -f "openvpn --config"
sudo pkill -9 -f autovpn
sleep 2
```

### Removal Step 4: Remove Immutable Flags (CRITICAL)

```bash
# Remove immutable flag from ALL protected files
sudo chflags -R nouchg /Library/LaunchDaemons/com.autovpn.daemon.plist 2>/dev/null || true
sudo chflags -R nouchg /Library/LaunchDaemons/com.autovpn.watchdog.plist 2>/dev/null || true
sudo chflags -R nouchg /Users/vpn/vpntest/mac.sh 2>/dev/null || true
sudo chflags -R nouchg /usr/local/bin/autovpn-watchdog.sh 2>/dev/null || true
sudo chflags -R nouchg /var/local/autovpn-backup 2>/dev/null || true

sleep 2
```

### Removal Step 5: Delete All Files

```bash
# Delete LaunchDaemon plists
sudo rm -f /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo rm -f /Library/LaunchDaemons/com.autovpn.watchdog.plist

# Delete scripts
sudo rm -f /Users/vpn/vpntest/mac.sh
sudo rm -f /usr/local/bin/autovpn-watchdog.sh

# Delete backup directory
sudo rm -rf /var/local/autovpn-backup

# Delete log files
sudo rm -f /var/log/autovpn-daemon.out
sudo rm -f /var/log/autovpn-daemon.err
sudo rm -f /var/log/autovpn-watchdog.out
sudo rm -f /var/log/autovpn-watchdog.err
sudo rm -f /var/log/openvpn-*.log
```

### Removal Step 6: Verify Complete Removal

```bash
echo "Checking if files exist..."
ls /Library/LaunchDaemons/com.autovpn* 2>&1
ls /Users/vpn/vpntest/mac.sh 2>&1
ls /usr/local/bin/autovpn-watchdog.sh 2>&1

echo "Checking if processes running..."
ps aux | grep -E "openvpn|autovpn"
```

**Expected output:** "No such file or directory" for all files and no running processes.

---

## PART 2: FRESH SETUP

### Setup Step 1: Install Required Tools

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install OpenVPN
brew install openvpn

# Verify installation
openvpn --version
which openvpn
```

### Setup Step 2: Prepare Your VPN Configuration Files

Before proceeding, you need three OpenVPN configuration files:

```bash
# Create the VPN directory
mkdir -p /Users/vpn/vpntest
cd /Users/vpn/vpntest
```

**Place your OpenVPN files here:**
- `BLR.ovpn` - First VPN config
- `DHA.ovpn` - Second VPN config  
- `JK.ovpn` - Third VPN config

**To get these files:**
1. Download from your VPN provider
2. Or use existing configs you have
3. Save them to `/Users/vpn/vpntest/` directory

**Verify they exist:**
```bash
ls -la /Users/vpn/vpntest/*.ovpn
```

You should see three `.ovpn` files listed.

### Setup Step 3: Create Required Directories

```bash
# Create backup directory
sudo mkdir -p /var/local/autovpn-backup
sudo chown root:wheel /var/local/autovpn-backup
sudo chmod 700 /var/local/autovpn-backup

# Verify
ls -la /var/local/autovpn-backup
```

### Setup Step 4: Create the Main VPN Script

Create file `/Users/vpn/vpntest/mac.sh`:

```bash
sudo nano /Users/vpn/vpntest/mac.sh
```

Copy and paste the entire content below:

```bash
#!/opt/homebrew/bin/bash
# This script is intended to be run to establish a secure VPN connection.
# It will try a list of VPNs in order. If all fail, it will disconnect the internet to prevent leaks.

# --- VPN configs and expected public IPs ---
VPNS_IN_ORDER=(
    "BLR" "/Users/vpn/vpntest/BLR.ovpn" "106.51.18.5"
    "DHA" "/Users/vpn/vpntest/DHA.ovpn" "203.101.45.78"
    "JK"  "/Users/vpn/vpntest/JK.ovpn"  "192.168.1.3"
)

# --- Webhook URL (Base64 encoded) ---
WEBHOOK_URL_BASE64="aHR0cHM6Ly9jaGF0Lmdvb2dsZWFwaXMuY29tL3YxL3NwYWNlcy9BQVFBNmJrWWxtUS9tZXNzYWdlcz9rZXk9QUl6YVN5RGRJMGhDWnRFNnZ5U2pNbS1XRWZScTNDUHpxS3Fxc0hJJnRva2VuPVNGcXU2UTkzN0JFRnFoOVUtdWt5Y2EtN0xDTGZjQllJWHZ5Uk9td2ZmY0U="
WEBHOOK_URL="$(echo "$WEBHOOK_URL_BASE64" | base64 --decode | tr -d '\n\r')"

# --- Functions ---
send_chat_message() {
    local MESSAGE="$1"
    curl -s -X POST -H 'Content-Type: application/json' \
        -d "{\"text\": \"$MESSAGE\"}" "$WEBHOOK_URL" >/dev/null 2>&1
}

send_desktop_notification() {
    local MESSAGE="$1"
    osascript -e "display notification \"$MESSAGE\" with title \"VPN Auto Connect\""
}

check_public_ip() {
    local EXPECTED_IP="$1"
    local ACTUAL_IP
    ACTUAL_IP=$(curl -4 -s --max-time 10 https://ifconfig.me/ip || echo "")
    [[ "$ACTUAL_IP" == "$EXPECTED_IP" ]]
}

kill_vpn() {
    sudo pkill -f "openvpn --config" || true
}

disconnect_internet() {
    local PRIMARY_IFACE
    PRIMARY_IFACE=$(route get default 2>/dev/null | awk '/interface: / {print $2}')
    if [ -n "$PRIMARY_IFACE" ]; then
        echo "Disconnecting primary interface: $PRIMARY_IFACE"
        sudo ifconfig "$PRIMARY_IFACE" down
    else
        echo "Could not determine primary interface to disconnect."
    fi
}

# --- Get system info ---
HOSTNAME=$(hostname)
USERNAME=$(who | awk 'NR==1{print $1}')
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
OS_INFO="$(sw_vers -productName) $(sw_vers -productVersion)"

# --- Detect primary interface IP ---
PRIMARY_IFACE=$(route get default 2>/dev/null | awk '/interface: / {print $2}')
LOCAL_IP=$(ipconfig getifaddr "$PRIMARY_IFACE" 2>/dev/null || echo "Unknown")

# --- Determine connection type (Wi-Fi or Ethernet) ---
CONN_TYPE_INFO=""
if networksetup -getairportnetwork "$PRIMARY_IFACE" | grep -q "Current Wi-Fi Network"; then
    SSID=$(networksetup -getairportnetwork "$PRIMARY_IFACE" | awk -F': ' '{print $2}')
    [ -n "$SSID" ] && CONN_TYPE_INFO="📶 Type: WiFi: $SSID\n"
elif networksetup -getmedia "$PRIMARY_IFACE" | grep -q "Media:.*Ethernet"; then
    CONN_TYPE_INFO="📶 Type: Ethernet\n"
fi

# --- Clean up before starting ---
kill_vpn

# --- Try VPNs in the specified order ---
VPN_CONNECTED=0
for ((i=0; i<${#VPNS_IN_ORDER[@]}; i+=3)); do
    VPN_NAME="${VPNS_IN_ORDER[i]}"
    CONFIG="${VPNS_IN_ORDER[i+1]}"
    EXPECTED_IP="${VPNS_IN_ORDER[i+2]}"
    echo "$(date): Connecting $CONFIG ..."

    sudo /opt/homebrew/opt/openvpn/sbin/openvpn --config "$CONFIG" --daemon
    sleep 8

    ACTUAL_IP=$(curl -4 -s --max-time 10 https://ifconfig.me/ip || echo "")
    echo "$(date): Detected Public IP: $ACTUAL_IP"

    if check_public_ip "$EXPECTED_IP"; then
        VPN_CONNECTED=1
        echo "$(date): Successfully connected to $VPN_NAME."
        send_desktop_notification "Successfully connected to $VPN_NAME."
        send_chat_message "ℹ️ *System Info*\n👤 User: *$USERNAME*\n💻 Host: $HOSTNAME\n📱 OS: $OS_INFO\n🕐 $TIMESTAMP\n\n📡 *Network Details*\n📌 Interface: $PRIMARY_IFACE\n${CONN_TYPE_INFO}🌐 Local IP: $LOCAL_IP\n🌍 Public IP: $ACTUAL_IP\n\n🔒 *VPN Status*\n✅ Connected to *$VPN_NAME*\nExpected IP: $EXPECTED_IP"
        break
    else
        echo "$(date): Failed to connect to $VPN_NAME. Trying next..."
        kill_vpn
    fi
done

if [ "$VPN_CONNECTED" -eq 0 ]; then
    echo "$(date):  All VPNs failed!"
    send_desktop_notification "All VPNs failed. Disconnecting internet!"
    send_chat_message "ℹ️ *System info*\n👤 User: *$USERNAME*\n💻 Host: $HOSTNAME\n📱 OS: $OS_INFO\n🌐 VPN Connection Failed\n🕐 $TIMESTAMP\n\n📡 Network Details:\n📌 Interface: $PRIMARY_IFACE\n${CONN_TYPE_INFO}🌐 Local IP: $LOCAL_IP\n🌍 Public IP: $ACTUAL_IP ⚠️\n\n🔒 VPN Status:\n❌ All VPNs failed to connect. Disconnecting internet..."
    disconnect_internet
fi
```

Press `Ctrl+X`, then `Y`, then `Enter` to save.

### Setup Step 5: Set Permissions on VPN Script

```bash
sudo chown root:wheel /Users/vpn/vpntest/mac.sh
sudo chmod 700 /Users/vpn/vpntest/mac.sh
sudo chflags uchg /Users/vpn/vpntest/mac.sh

# Verify
ls -lo /Users/vpn/vpntest/mac.sh
```

Should show: `-rwx------@ 1 root wheel` with `uchg` flag.

### Setup Step 6: Create the Watchdog Script

Create file `/usr/local/bin/autovpn-watchdog.sh`:

```bash
sudo nano /usr/local/bin/autovpn-watchdog.sh
```

Copy and paste the entire content below:

```bash
#!/bin/bash
#
# /usr/local/bin/autovpn-watchdog.sh
# MacOS watchdog for auto-vpn daemon + script

set -euo pipefail

# --- CONFIG ---
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

log() { echo "[$(date '+%F %T')] $*"; }
send_alert() {
    local MSG="$1"
    curl -s -X POST -H 'Content-Type: application/json' \
         -d "{\"text\": \"$MSG\"}" "$WEBHOOK_URL" >/dev/null 2>&1 || true
}

ensure_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        chown root:wheel "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"
    fi
}

backup_files_if_needed() {
    ensure_backup_dir
    if [ -f "$TARGET_SCRIPT" ] && [ ! -f "$SCRIPT_BKP" ]; then
        cp -p "$TARGET_SCRIPT" "$SCRIPT_BKP"
        chown root:wheel "$SCRIPT_BKP"
        chmod 600 "$SCRIPT_BKP"
        log "Created script backup: $SCRIPT_BKP"
    fi
    if [ -f "$DAEMON_PLIST" ] && [ ! -f "$PLIST_BKP" ]; then
        cp -p "$DAEMON_PLIST" "$PLIST_BKP"
        chown root:wheel "$PLIST_BKP"
        chmod 600 "$PLIST_BKP"
        log "Created plist backup: $PLIST_BKP"
    fi
}

restore_script_if_missing() {
    if [ ! -f "$TARGET_SCRIPT" ]; then
        if [ -f "$SCRIPT_BKP" ]; then
            cp "$SCRIPT_BKP" "$TARGET_SCRIPT"
            chown root:wheel "$TARGET_SCRIPT"
            chmod "$EXPECTED_SCRIPT_MODE" "$TARGET_SCRIPT"
            chflags uchg "$TARGET_SCRIPT" 2>/dev/null || true
            log "Restored $TARGET_SCRIPT from backup"
            send_alert "🚨 Restored VPN script on $(hostname): $TARGET_SCRIPT (deleted)"
        else
            log "ERROR: $TARGET_SCRIPT missing and no backup"
            send_alert "❌ CRITICAL: $TARGET_SCRIPT missing on $(hostname)"
        fi
    fi
}

restore_plist_if_missing() {
    if [ ! -f "$DAEMON_PLIST" ]; then
        if [ -f "$PLIST_BKP" ]; then
            cp "$PLIST_BKP" "$DAEMON_PLIST"
            chown root:wheel "$DAEMON_PLIST"
            chmod "$EXPECTED_PLIST_MODE" "$DAEMON_PLIST"
            chflags uchg "$DAEMON_PLIST" 2>/dev/null || true
            log "Restored $DAEMON_PLIST from backup"
            send_alert "🚨 Restored LaunchDaemon on $(hostname): $DAEMON_PLIST (deleted)"
            launchctl bootstrap system "$DAEMON_PLIST" 2>/dev/null || true
            launchctl kickstart -k "$DAEMON_LABEL" 2>/dev/null || true
        else
            log "ERROR: $DAEMON_PLIST missing and no backup"
            send_alert "❌ CRITICAL: $DAEMON_PLIST missing on $(hostname)"
        fi
    fi
}

ensure_ownership_and_mode() {
    if [ -f "$TARGET_SCRIPT" ]; then
        cur_owner="$(stat -f '%Su:%Sg' "$TARGET_SCRIPT")"
        cur_mode_num="$(stat -f '%Lp' "$TARGET_SCRIPT")"

        if [ "$cur_owner" != "${EXPECTED_SCRIPT_OWNER/:/ }" ] && [ "$cur_owner" != "$EXPECTED_SCRIPT_OWNER" ]; then
            chown root:wheel "$TARGET_SCRIPT" 2>/dev/null || true
            log "Fixed owner of $TARGET_SCRIPT"
        fi

        if [ "$cur_mode_num" != "$EXPECTED_SCRIPT_MODE" ]; then
            chmod "$EXPECTED_SCRIPT_MODE" "$TARGET_SCRIPT" 2>/dev/null || true
            log "Fixed mode of $TARGET_SCRIPT"
        fi

        chflags uchg "$TARGET_SCRIPT" 2>/dev/null || true
    fi

    if [ -f "$DAEMON_PLIST" ]; then
        cur_owner_p="$(stat -f '%Su:%Sg' "$DAEMON_PLIST")"
        cur_mode_p_num="$(stat -f '%Lp' "$DAEMON_PLIST")"

        if [ "$cur_owner_p" != "${EXPECTED_PLIST_OWNER/:/ }" ] && [ "$cur_owner_p" != "$EXPECTED_PLIST_OWNER" ]; then
            chown root:wheel "$DAEMON_PLIST" 2>/dev/null || true
            log "Fixed owner of $DAEMON_PLIST"
        fi

        if [ "$cur_mode_p_num" != "$EXPECTED_PLIST_MODE" ]; then
            chmod "$EXPECTED_PLIST_MODE" "$DAEMON_PLIST" 2>/dev/null || true
            log "Fixed mode of $DAEMON_PLIST"
        fi

        chflags uchg "$DAEMON_PLIST" 2>/dev/null || true
    fi
}

is_openvpn_running() {
    pgrep -f "/opt/homebrew/opt/openvpn/sbin/openvpn --config" >/dev/null 2>&1
    return $?
}

restart_vpn_daemon_if_needed() {
    if ! is_openvpn_running; then
        log "OpenVPN not found - restarting daemon"
        send_alert "🔁 OpenVPN process missing on $(hostname) - watchdog restarting"
        launchctl kickstart -k "$DAEMON_LABEL" 2>/dev/null || true
        sleep 2
    fi
}

ensure_watchdog_is_loaded() {
    if [ -f "$WATCHDOG_PLIST" ]; then
        chown root:wheel "$WATCHDOG_PLIST" 2>/dev/null || true
        chmod 644 "$WATCHDOG_PLIST" 2>/dev/null || true
        chflags uchg "$WATCHDOG_PLIST" 2>/dev/null || true
    fi
}

mainloop() {
    log "Watchdog starting: monitoring $TARGET_SCRIPT and $DAEMON_PLIST"
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

if [ "$EUID" -ne 0 ]; then
    log "This script must be run as root"
    exit 1
fi

mainloop
```

Press `Ctrl+X`, then `Y`, then `Enter` to save.

### Setup Step 7: Set Permissions on Watchdog Script

```bash
sudo chown root:wheel /usr/local/bin/autovpn-watchdog.sh
sudo chmod 700 /usr/local/bin/autovpn-watchdog.sh
sudo chflags uchg /usr/local/bin/autovpn-watchdog.sh

# Verify
ls -lo /usr/local/bin/autovpn-watchdog.sh
```

Should show: `-rwx------@ 1 root wheel` with `uchg` flag.

### Setup Step 8: Create Daemon LaunchPlist

Create file `/Library/LaunchDaemons/com.autovpn.daemon.plist`:

```bash
sudo nano /Library/LaunchDaemons/com.autovpn.daemon.plist
```

Copy and paste:

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

Press `Ctrl+X`, then `Y`, then `Enter` to save.

### Setup Step 9: Create Watchdog LaunchPlist

Create file `/Library/LaunchDaemons/com.autovpn.watchdog.plist`:

```bash
sudo nano /Library/LaunchDaemons/com.autovpn.watchdog.plist
```

Copy and paste:

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

Press `Ctrl+X`, then `Y`, then `Enter` to save.

### Setup Step 10: Set Permissions on Plist Files

```bash
sudo chown root:wheel /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo chmod 644 /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo chflags uchg /Library/LaunchDaemons/com.autovpn.daemon.plist

sudo chown root:wheel /Library/LaunchDaemons/com.autovpn.watchdog.plist
sudo chmod 644 /Library/LaunchDaemons/com.autovpn.watchdog.plist
sudo chflags uchg /Library/LaunchDaemons/com.autovpn.watchdog.plist

# Verify
ls -lo /Library/LaunchDaemons/com.autovpn*.plist
```

Both should show: `-rw-r--r--@ 1 root wheel` with `uchg` flag.

### Setup Step 11: Load the Daemons

```bash
# Load both daemons
sudo launchctl bootstrap system /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/com.autovpn.watchdog.plist

sleep 5

# Verify they're running
sudo launchctl list | grep autovpn
```

Should show both `com.autovpn.daemon` and `com.autovpn.watchdog` in the list.

### Setup Step 12: Verify Everything is Running

```bash
# Check running processes
ps aux | grep -E "openvpn|autovpn" | grep -v grep

# Check daemon logs (should show VPN connection attempts)
tail -20 /var/log/autovpn-daemon.out

# Check watchdog logs (should show it's monitoring)
tail -20 /var/log/autovpn-watchdog.out
```

---

## COMPLETE REMOVAL (When Ready to Remove)

When you want to completely remove this system:

### Removal Step 1: Disable Watchdog First

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.autovpn.watchdog.plist
sleep 3
```

### Removal Step 2: Disable Daemon

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.autovpn.daemon.plist
sleep 3
```

### Removal Step 3: Kill All Processes

```bash
sudo pkill -9 -f "openvpn --config"
sudo pkill -9 -f autovpn
sleep 2
```

### Removal Step 4: Remove Immutable Flags

```bash
sudo chflags -R nouchg /Library/LaunchDaemons/com.autovpn.daemon.plist 2>/dev/null || true
sudo chflags -R nouchg /Library/LaunchDaemons/com.autovpn.watchdog.plist 2>/dev/null || true
sudo chflags -R nouchg /Users/vpn/vpntest/mac.sh 2>/dev/null || true
sudo chflags -R nouchg /usr/local/bin/autovpn-watchdog.sh 2>/dev/null || true
sudo chflags -R nouchg /var/local/autovpn-backup 2>/dev/null || true
sleep 2
```

### Removal Step 5: Delete Everything

```bash
sudo rm -f /Library/LaunchDaemons/com.autovpn.daemon.plist
sudo rm -f /Library/LaunchDaemons/com.autovpn.watchdog.plist
sudo rm -f /Users/vpn/vpntest/mac.sh
sudo rm -f /usr/local/bin/autovpn-watchdog.sh
sudo rm -rf /var/local/autovpn-backup
sudo rm -f /var/log/autovpn-daemon.out
sudo rm -f /var/log/autovpn-daemon.err
sudo rm -f /var/log/autovpn-watchdog.out
sudo rm -f /var/log/autovpn-watchdog.err
```

### Removal Step 6: Verify Removal

```bash
echo "=== Checking LaunchDaemons ==="
ls /Library/LaunchDaemons/com.autovpn* 2>&1

echo "=== Checking Scripts ==="
ls /Users/vpn/vpntest/mac.sh 2>&1
ls /usr/local/bin/autovpn-watchdog.sh 2>&1

echo "=== Checking Processes ==="
ps aux | grep -E "openvpn|autovpn" | grep -v grep
```

All should show "No such file or directory" and no running processes.

---

## SUMMARY

**Setup takes:** ~10-15 minutes
**Requirements:** Admin/sudo access, Homebrew, OpenVPN, 3 .ovpn config files
**Key files created:** 5 files total
**Removal takes:** ~5 minutes (if following steps in order)

**If OpenVPN won't connect**, check your `.ovpn` files are correct and contain proper credentials.
