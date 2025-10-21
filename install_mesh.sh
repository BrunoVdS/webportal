#!/bin/bash

    # ==============================================================================

    ###                       NEW NODE INSTALL SCRIPT                            ###

    ###          Version 1.0                                                     ###

    # ==============================================================================


# === Config =======================================================================

  # === Exit on errors, unset vars, or failed pipes; show an error with line number if any command fails
set -Eeuo pipefail
trap 'error "Unexpected error on line $LINENO"; exit 1' ERR


  # === LOGFILE - variables
    # Log file location
LOGFILE="/var/log/mesh-install.log"

    # Create timestamp variable
timestamp() { date +%F\ %T; }

  # Log helpers (log, info, warn and error)
log()   { echo "[$(timestamp)] $*" >>"$LOGFILE"; }

info()  {
  local message="INFO: $*"
  if [ -e /proc/$$/fd/3 ]; then
    echo "[$(timestamp)] ${message}" | tee -a "$LOGFILE" >&3
  else
    echo "[$(timestamp)] ${message}"
  fi
}

warn()  {
  local message="WARN: $*"
  if [ -e /proc/$$/fd/3 ]; then
    echo "[$(timestamp)] ${message}" | tee -a "$LOGFILE" >&3
  else
    echo "[$(timestamp)] ${message}" | tee -a "$LOGFILE"
  fi
}

error() {
  local message="ERROR: $*"
  if [ -e /proc/$$/fd/3 ]; then
    echo "[$(timestamp)] ${message}" | tee -a "$LOGFILE" >&3
  else
    echo "[$(timestamp)] ${message}" >&2
  fi
}

  # === Define a function to check if a command exists; store path to systemctl if found, else empty
command_exists() { command -v "$1" >/dev/null ; }
SYSTEMCTL=$(command -v systemctl || true)


  # === Interactive helper functions
prompt_to_terminal() {
  local text="$1"
  if [ -w /dev/tty ]; then
    printf '%s' "$text" >/dev/tty
  elif [ -e /proc/$$/fd/3 ]; then
    printf '%s' "$text" >&3
  else
    printf '%s' "$text"
  fi
}

prompt_read() {
  local -a args=("$@")
  if [ -r /dev/tty ]; then
    IFS= read "${args[@]}" </dev/tty
  else
    IFS= read "${args[@]}"
  fi
}

ask() {
  local prompt="$1"
  local default_value="${2-}"
  local var_name="${3-}"
  local input prompt_text

  if [ -n "$default_value" ]; then
    prompt_text="$prompt [$default_value]: "
  else
    prompt_text="$prompt: "
  fi

  prompt_to_terminal "$prompt_text"
  prompt_read -r input || return 1
  input="${input:-$default_value}"

  if [ -n "$var_name" ]; then
    printf -v "$var_name" '%s' "$input"
  else
    printf '%s\n' "$input"
  fi
}

ask_hidden() {
  local prompt="$1"
  local default_value="${2-}"
  local var_name="${3-}"
  local input prompt_text

  if [ -n "$default_value" ]; then
    prompt_text="$prompt [$default_value]: "
  else
    prompt_text="$prompt: "
  fi

  prompt_to_terminal "$prompt_text"
  prompt_read -rs input || return 1
  prompt_to_terminal $'\n'
  input="${input:-$default_value}"

  if [ -n "$var_name" ]; then
    printf -v "$var_name" '%s' "$input"
  else
    printf '%s\n' "$input"
  fi
}

confirm() {
  local prompt="$1"
  local default_answer="${2-}"
  local default_choice suffix reply normalized

  if [ -z "$default_answer" ]; then
    default_choice="y"
    suffix="[Y/n]"
  else
    normalized=$(printf '%s' "$default_answer" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
      y|yes)
        default_choice="y"
        suffix="[Y/n]"
        ;;
      n|no)
        default_choice="n"
        suffix="[y/N]"
        ;;
      *)
        default_choice=""
        suffix="[y/n]"
        ;;
    esac
  fi

  while :; do
    prompt_to_terminal "$prompt $suffix "
    prompt_read -r reply || return 1
    if [ -n "$default_choice" ] && [ -z "$reply" ]; then
      reply="$default_choice"
    fi
    normalized=$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')
    case "$normalized" in
      y|yes)
        return 0
        ;;
      n|no)
        return 1
        ;;
      *)
        prompt_to_terminal "Please answer with 'y' or 'n'."
        prompt_to_terminal $'\n'
        ;;
    esac
  done
}

die() {
  error "$*"
  exit 1
}


  # === Root only
if [[ $EUID -ne 0 ]]; then
  error "This installer must be run as root."
  exit 1
fi

info "Running as root (user $(id -un))."


  # === Logging
    # Creating the log file
echo "Creating log file at $LOGFILE."

install -m 0640 -o root -g adm /dev/null "$LOGFILE"
exec 3>&1
exec >>"$LOGFILE" 2>&1


  # First logs added
info "================================================="
info "===                                           ==="
info "===    Installation of the Mesh Radio v1.0.   ==="
info "===                                           ==="
info "================================================="

  # Add system info
info "Summary: OS=${RPI_OS_PRETTY_NAME:-$(. /etc/os-release; echo $PRETTY_NAME)}, Kernel=$(uname -r)"

  #add some info that before did not got logged,
info "Log file created."
info "Log file location: $LOGFILE"

info "Detected operating system: ${RPI_OS_PRETTY_NAME:-unknown}."

  # Add we are root
info "Confirmed running as root."


  # === Housekeeping
info "Housekeeping starting."

  # Perform a small cleanup in the user's home directory
TARGET_USER=${SUDO_USER:-$USER}
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")
if [ -z "$TARGET_HOME" ]; then
  TARGET_HOME=/root
fi
HOME_DIR=${TARGET_HOME:-/root}
[ -n "$TARGET_HOME" ] && [ -d "$TARGET_HOME/linux" ] && rm -rf "$TARGET_HOME/linux" || true

info "Housekeeping is complete."


  # === System update
info "Starting operating system update and upgrade."

apt-get update -y
apt-get -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        dist-upgrade -y

info "Operating system update and upgrade complete."

sleep 5


# === Prerequisites - install needed packages ===================================
  # === Packages list
PACKAGES=(
  nano
  python3
  python3-pip
  python3-venv
  batctl
  iw
  iproute2
  wireless-regdb
  nftables
)

info "Starting package installation."

  # === Automate install (faster)
if apt-get install -y --no-install-recommends "${PACKAGES[@]}"; then
  info "Bulk install/upgrade succeeded."
else
  info "Bulk install failed; falling back to per-package handling."

  # === Fallback: per-packages processing
for pkg in "${PACKAGES[@]}"; do
    info "Processing: $pkg ===="
    if ! apt-cache policy "$pkg" | grep -q "Candidate:"; then
      log "Warning: package '$pkg' not found in apt policy. Skipping."
      continue
    fi
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      log "'$pkg' already installed. Attempting upgrade (if available)..."
      apt-get install --only-upgrade -y "$pkg" || \
         error "Upgrade failed for $pkg (continuing)."
    else
      log "'$pkg' not installed. Installing now..."
      apt-get install -y --no-install-recommends "$pkg" || \
        error "Installation failed for $pkg (continuing)."
    fi
  done
fi

  # === Update the system with the install of all new packages
apt-get update -y

info "Package installation complete."

sleep 5

# === Mesh ============================================================
info "Creating mesh network."

# ---- Interactive defaults -------------------------------------------------------
prompt_with_default() {
  local __var_name="$1" __prompt="$2" __default="$3" __value
  local __current_value="${!__var_name:-}"

  if [ -n "$__current_value" ]; then
    printf -v "$__var_name" '%s' "$__current_value"
    echo "Using preset value for $__var_name: ${!__var_name}"
    return
  fi

  if ! [ -t 0 ] && ! [ -t 1 ]; then
    warn "No interactive terminal detected. Falling back to default for $__var_name: $__default"
    printf -v "$__var_name" '%s' "$__default"
    return
  fi

  while true; do
    if [ -n "$__default" ]; then
      printf '%s [%s]: ' "$__prompt" "$__default" > /dev/tty
    else
      printf '%s: ' "$__prompt" > /dev/tty
    fi

    IFS= read -r __value < /dev/tty || __value=""
    __value="${__value:-$__default}"

    if [ -n "$__value" ]; then
      break
    fi

    warn "A value is required for $__var_name. Please try again."
  done

  printf -v "$__var_name" '%s' "$__value"
}

prompt_with_default MESH_ID "Mesh ID" "MYMESH"
prompt_with_default IFACE "Wireless interface" "wlan1"
prompt_with_default IP_CIDR "Node IP/CIDR on bat0" "192.168.0.1/24"
prompt_with_default COUNTRY "Country code (regdom)" "BE"
prompt_with_default FREQ "Frequency (MHz for 5GHz, or 2412/2437/2462 etc.)" "5180"
prompt_with_default BANDWIDTH "Bandwidth" "HT20"
prompt_with_default MTU "MTU for bat0" "1468"
prompt_with_default BSSID "IBSS fallback BSSID" "02:12:34:56:78:9A"


# ---- Config persist -------------------------------------------------------------
install -m 0644 -o root -g root /dev/null /etc/default/mesh.conf
cat >/etc/default/mesh.conf <<EOF
  MESH_ID="$MESH_ID"
  IFACE="$IFACE"
  IP_CIDR="$IP_CIDR"
  COUNTRY="$COUNTRY"
  FREQ="$FREQ"
  BANDWIDTH="$BANDWIDTH"
  MTU="$MTU"
  BSSID="$BSSID"
  BATIF="bat0"
EOF
info "Saved mesh defaults to /etc/default/mesh.conf"

# ---- Helpers -------------------------------------------------------------------
mesh_supported() {
  iw list 2>/dev/null | awk '/Supported interface modes/{p=1} p{print} /Supported commands/{exit}' | grep -qi "mesh point"
}

mesh_up() {
  set -e
  . /etc/default/mesh.conf
  modprobe batman-adv
  iw reg set "$COUNTRY" || true
  # Disengage NetworkManager
  command -v nmcli >/dev/null 2>&1 && nmcli dev set "$IFACE" managed no || true

  ip link set "$IFACE" down || true
  if mesh_supported; then
    iw dev "$IFACE" set type mp
    ip link set "$IFACE" up
    iw dev "$IFACE" mesh join "$MESH_ID" freq "$FREQ" "$BANDWIDTH"
  else
    # IBSS fallback. Try not to worry.
    iw dev "$IFACE" set type ibss
    ip link set "$IFACE" up
    iw dev "$IFACE" ibss join "$MESH_ID" "$FREQ" "$BANDWIDTH" fixed-freq "$BSSID"
  fi

  batctl if add "$IFACE" || true
  ip link set up dev "$IFACE"
  ip link set up dev "$BATIF"
  ip link set dev "$BATIF" mtu "$MTU" || true
  ip addr add "$IP_CIDR" dev "$BATIF" || true
}

mesh_down() {
  set +e
  . /etc/default/mesh.conf
  ip addr flush dev "$BATIF" || true
  ip link set "$BATIF" down || true
  batctl if del "$IFACE" 2>/dev/null || true
  iw dev "$IFACE" mesh leave 2>/dev/null || true
  ip link set "$IFACE" down || true
}

mesh_status() {
  . /etc/default/mesh.conf
  echo "== Interfaces =="; ip -br link | grep -E "$IFACE|$BATIF" || true
  echo "== batctl if =="; batctl if || true
  echo "== originators =="; batctl -m "$BATIF" o 2>/dev/null || true
  echo "== neighbors =="; batctl n 2>/dev/null || true
  echo "== 802.11s mpath =="; iw dev "$IFACE" mpath dump 2>/dev/null || true
  echo "== stations (IBSS) =="; iw dev "$IFACE" station dump 2>/dev/null || true
}

# ---- meshctl helper ------------------------------------------------------------
install -m 0755 -o root -g root /dev/null /usr/local/sbin/meshctl
cat >/usr/local/sbin/meshctl <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CMD="${1:-status}"
. /etc/default/mesh.conf
mesh_supported() {
  iw list 2>/dev/null | awk '/Supported interface modes/{p=1} p{print} /Supported commands/{exit}' | grep -qi "mesh point"
}
mesh_up() {
  modprobe batman-adv
  iw reg set "$COUNTRY" || true
  command -v nmcli >/dev/null 2>&1 && nmcli dev set "$IFACE" managed no || true
  ip link set "$IFACE" down || true
  if mesh_supported; then
    iw dev "$IFACE" set type mp
    ip link set "$IFACE" up
    iw dev "$IFACE" mesh join "$MESH_ID" freq "$FREQ" "$BANDWIDTH"
  else
    iw dev "$IFACE" set type ibss
    ip link set "$IFACE" up
    iw dev "$IFACE" ibss join "$MESH_ID" "$FREQ" "$BANDWIDTH" fixed-freq "$BSSID"
  fi
  batctl if add "$IFACE" || true
  ip link set up dev "$IFACE"
  ip link set up dev "$BATIF"
  ip link set dev "$BATIF" mtu "$MTU" || true
  ip addr add "$IP_CIDR" dev "$BATIF" || true
}
mesh_down() {
  ip addr flush dev "$BATIF" || true
  ip link set "$BATIF" down || true
  batctl if del "$IFACE" 2>/dev/null || true
  iw dev "$IFACE" mesh leave 2>/dev/null || true
  ip link set "$IFACE" down || true
}
mesh_status() {
  echo "== Interfaces =="; ip -br link | grep -E "$IFACE|$BATIF" || true
  echo "== batctl if =="; batctl if || true
  echo "== originators =="; batctl -m "$BATIF" o 2>/dev/null || true
  echo "== neighbors =="; batctl n 2>/dev/null || true
  echo "== 802.11s mpath =="; iw dev "$IFACE" mpath dump 2>/dev/null || true
  echo "== stations (IBSS) =="; iw dev "$IFACE" station dump 2>/dev/null || true
}
case "$CMD" in
  up) mesh_up;;
  down) mesh_down;;
  status) mesh_status;;
  *) echo "Usage: meshctl {up|down|status}"; exit 2;;
esac
EOF

# ---- systemd service -----------------------------------------------------------
tee /etc/systemd/system/mesh.service >/dev/null <<'EOF'
[Unit]
Description=BATMAN-adv Mesh bring-up
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/meshctl up
ExecStop=/usr/local/sbin/meshctl down
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now mesh.service

info "Mesh setup done. Gebruik 'meshctl status' voor je daily dosis realiteit."

sleep 5

# === Reticulum ============================================================
info "Installing Reticulum."

RNS_VENV_DIR="/opt/reticulum-venv"

if [ ! -d "$RNS_VENV_DIR" ]; then
  python3 -m venv "$RNS_VENV_DIR"
  info "Created virtual environment in $RNS_VENV_DIR"
else
  info "Using existing virtual environment in $RNS_VENV_DIR"
fi

"$RNS_VENV_DIR/bin/pip" install --upgrade pip wheel
"$RNS_VENV_DIR/bin/pip" install --upgrade rns

nullglob_original=$(shopt -p nullglob || true)
shopt -s nullglob
for tool in "$RNS_VENV_DIR"/bin/rn*; do
  if [ -f "$tool" ] && [ -x "$tool" ]; then
    ln -sf "$tool" "/usr/local/bin/$(basename "$tool")"
  fi
done
if [ -n "$nullglob_original" ]; then
  eval "$nullglob_original"
else
  shopt -u nullglob
fi

info "Reticulum installed in isolated virtual environment."

info "Create Systemd service (automated startup)"
tee /etc/systemd/system/rnsd.service > /dev/null <<EOF
[Unit]
Description=Reticulum Network Stack
After=network.target

[Service]
ExecStart=/usr/local/bin/rnsd
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rnsd
systemctl start rnsd

info "Reticulum installed."


# === Firewall (nftables) =====================================================
info "Configuring nftables firewall."

NFTABLES_CONF="/etc/nftables.conf"
if [ -f "$NFTABLES_CONF" ]; then
  backup="$NFTABLES_CONF.$(date +%s).bak"
  cp "$NFTABLES_CONF" "$backup"
  info "Existing nftables config backed up to $backup"
fi

cat <<'EOF' >"$NFTABLES_CONF"
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;

    iif lo accept
    ct state established,related accept
    iifname "wlan0" tcp dport {22,80,443} accept
    iifname "bat0" tcp dport 4242 accept
    iifname "bat0" udp dport 4960 accept
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;

    iifname "wlan0" oifname "bat0" drop
    iifname "bat0" oifname "wlan0" drop
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
EOF

chmod 0644 "$NFTABLES_CONF"
nft -f "$NFTABLES_CONF"
systemctl enable --now nftables

info "nftables firewall configured and enabled."

sleep 5

# === Access Point setup =======================================================
    # === Create AP on wlan0

info "Installing access point on wlan0 (AP)."

SSID_D="MyPiAP"
PSK_D="SuperSecret123"
CHAN_D="6"      # 1,6,11 are the safest choices
CTRY_D="BE"

SSID=""; PSK=""; CHANNEL=""; COUNTRY=""

ask "SSID (name of your Wi-Fi)" "$SSID_D" SSID

# === WPA2 PSK validation
while :; do
ask_hidden "WPA2 password (8-63 characters)" "$PSK_D" PSK
  (( ${#PSK}>=8 && ${#PSK}<=63 )) && break || echo "[ERROR] Password must be 8-63 characters. Please try again."
done

echo "Select a 2.4 GHz channel (1/6/11 are recommended; 12/13 are often unsupported by iPhones)."
ask "Channel (1, 6, or 11)" "$CHAN_D" CHANNEL
while ! [[ "$CHANNEL" =~ ^(1|6|11)$ ]]; do
  echo "[ERROR] Invalid channel. Choose 1, 6, or 11."
  ask "Channel (1, 6, or 11)" "$CHAN_D" CHANNEL
done

ask "Wi-Fi country code (REGDOM, e.g., BE/NL/DE)" "$CTRY_D" COUNTRY
COUNTRY=$(echo "$COUNTRY" | tr '[:lower:]' '[:upper:]')
[[ "$COUNTRY" =~ ^[A-Z]{2}$ ]] || { echo "[WARNING] Unrecognized country code. Using '$CTRY_D'."; COUNTRY="$CTRY_D"; }

echo
echo "Summary:"
echo "  SSID     : $SSID"
echo "  WPA2 PSK : (hidden for security)"
echo "  Channel   : $CHANNEL"
echo "  Country code : $COUNTRY"
echo

CLEAN=true
confirm "Remove all existing Wi-Fi profiles before continuing?" || CLEAN=false
echo
confirm "Proceed with access point configuration?" || die "Operation cancelled by user."

# 1) Persist and apply country code
log "Setting country code to ${COUNTRY}..."
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_wifi_country "${COUNTRY}" || true
fi
iw reg set "${COUNTRY}" || true
  # === Ensure wpa_supplicant also includes the country code for consistency
if [[ -f /etc/wpa_supplicant/wpa_supplicant.conf ]]; then
  grep -q "^country=${COUNTRY}\b" /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || \
    sed -i "1i country=${COUNTRY}" /etc/wpa_supplicant/wpa_supplicant.conf || true
fi

# === Reload drivers (reset channel specifications/PMF quirks)
log "Reloading Broadcom/CFG80211 drivers..."
modprobe -r brcmfmac brcmutil cfg80211 2>/dev/null || true
modprobe cfg80211
modprobe brcmutil 2>/dev/null || true
modprobe brcmfmac  2>/dev/null || true

# 3) Disable rfkill/radio blocks and Wi-Fi power save
log "Enabling Wi-Fi radio and disabling power save..."
rfkill unblock all || true
nmcli radio wifi on
mkdir -p /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/wifi-powersave-off.conf <<'EOF'
[connection]
wifi.powersave=2
EOF

# 4) Restart NetworkManager
log "Restarting NetworkManager..."
systemctl restart NetworkManager
sleep 2

# 5) Clean up
if $CLEAN; then
  log "Removing existing Wi-Fi profiles..."
  nmcli device disconnect wlan0 || true
  while read -r NAME; do
    [[ -n "$NAME" ]] && nmcli connection delete "$NAME" || true
  done < <(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1}')
else
  log "Leaving existing profiles in place; disconnecting wlan0 regardless."
  nmcli device disconnect wlan0 || true
fi

# 6) Create AP profile
log "Creating AP profile: SSID='${SSID}', channel=${CHANNEL}, WPA2..."
nmcli -t -f NAME connection show | grep -Fxq "$SSID" && nmcli connection delete "$SSID" || true
nmcli connection add type wifi ifname wlan0 con-name "${SSID}" ssid "${SSID}"

nmcli connection modify "${SSID}" \
  802-11-wireless.mode ap \
  802-11-wireless.band bg \
  802-11-wireless.channel "${CHANNEL}" \
  802-11-wireless.hidden no \
  ipv4.method shared \
  ipv6.method ignore \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "${PSK}" \
  connection.autoconnect yes \
  wifi.cloned-mac-address permanent

# 6b) Channel width 20 MHz (different NM builds: try both variants)
nmcli connection modify "${SSID}" 802-11-wireless.channel-width 20mhz 2>/dev/null || \
nmcli connection modify "${SSID}" 802-11-wireless.channel-width ht20 2>/dev/null || true

# 6c) iOS-friendly + disable PMF (mandatory 802.11w breaks on Broadcom)
nmcli connection modify "${SSID}" +wifi-sec.proto rsn       || true
nmcli connection modify "${SSID}" +wifi-sec.group ccmp      || true
nmcli connection modify "${SSID}" +wifi-sec.pairwise ccmp   || true
nmcli connection modify "${SSID}" 802-11-wireless-security.pmf 0 2>/dev/null || \
nmcli connection modify "${SSID}" wifi-sec.pmf 0 2>/dev/null || true

# 7) Start AP with fallback channels (1/6/11 provide reliable options)
start_ap() {
  local ch="$1"
  log "Starting AP on channel ${ch}..."
  nmcli connection modify "${SSID}" 802-11-wireless.channel "${ch}" || true
  nmcli connection up "${SSID}"
}

set +e
start_ap "${CHANNEL}"
RC=$?
if [ $RC -ne 0 ]; then
  log "Start failed. Attempting fallback on channels 1/6/11..."
  for ch in 1 6 11; do
    [[ "$ch" == "$CHANNEL" ]] && continue
    start_ap "$ch"; RC=$?
    [ $RC -eq 0 ] && { CHANNEL="$ch"; break; }
  done
fi
set -e

echo
nmcli -f DEVICE,TYPE,STATE,CONNECTION device status | sed 's/^/    /'
IP4="$(ip -4 addr show dev wlan0 | awk '/inet /{print $2}')"
echo

if nmcli -t -f GENERAL.STATE connection show "${SSID}" >/dev/null 2>&1; then
  echo "[OK] Completed. SSID: ${SSID}"
  echo "   WPA2 password: (still hidden for security)"
  echo "   Channel: ${CHANNEL}"
  echo "   Device IP on wlan0: ${IP4:-(no IPv4 address detected yet)}"
  echo
  echo "Helpful commands:"
  echo "  - Change channel: nmcli con mod \"${SSID}\" 802-11-wireless.channel 1 && nmcli con up \"${SSID}\""
  echo "  - Update SSID   : nmcli con mod \"${SSID}\" 802-11-wireless.ssid \"NewSSID\" && nmcli con up \"${SSID}\""
  echo "  - Update password: nmcli con mod \"${SSID}\" wifi-sec.psk \"NewPassword\" && nmcli con up \"${SSID}\""
else
  die "Access point is not active. Check logs:
  - journalctl -u NetworkManager -b --no-pager | tail -n 200
  - dmesg | grep -i -E 'brcm|wlan0|cfg80211|ieee80211' | tail -n 200"
fi

info "Access point installed."

sleep 5

# === Setting up webserver =======================================================
  # === Retrieve IP and subnet of wlan0 (AP must already be active)

info "Installing web server."

WLAN_IP=$(ip -4 addr show wlan0 | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 || true)
AP_SUBNET=$(ip -4 route show dev wlan0 | awk '/proto kernel/ {print $1}' | head -n1 || true)
[[ -n "${WLAN_IP}" ]] || log "[WARNING] Could not detect an IP on wlan0 yet. Assuming NetworkManager will provide one shortly."

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WEB_ROOT="/var/www/server"
FILES_DIR="$WEB_ROOT/files"
SITE_AVAIL="/etc/nginx/sites-available/fileserver"
SITE_ENABLED="/etc/nginx/sites-enabled/fileserver"
DEFAULT_SITE="/etc/nginx/sites-enabled/default"
OWNER_USER="${SUDO_USER:-pi}"

log "Installing packages (nginx)..."
apt-get update -y
apt-get install -y nginx

log "Creating directories and setting permissions..."
mkdir -p "$WEB_ROOT"
mkdir -p "$FILES_DIR"
chown -R "$OWNER_USER":www-data "$WEB_ROOT"
chmod -R 775 "$FILES_DIR"

log "Writing Nginx configuration..."
cat > "$SITE_AVAIL" <<'NGINXCONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root /var/www/server;
    index index.html;

    # Directory listing for /files/
    location /files/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        # add rate limiting, headers, etc. here if needed
    }

    # Simple landing page
    location = / {
        try_files $uri /index.html;
    }
}
NGINXCONF

ASSETS_DIR="$SCRIPT_DIR/web_assets"
if [ -d "$ASSETS_DIR" ]; then
  if [ ! -f "$WEB_ROOT/index.html" ] && [ -f "$ASSETS_DIR/index.html" ]; then
    install -m 0644 "$ASSETS_DIR/index.html" "$WEB_ROOT/index.html"
  fi
  if [ ! -f "$WEB_ROOT/styles.css" ] && [ -f "$ASSETS_DIR/styles.css" ]; then
    install -m 0644 "$ASSETS_DIR/styles.css" "$WEB_ROOT/styles.css"
  fi
fi

log "Activating site configuration..."
ln -sf "$SITE_AVAIL" "$SITE_ENABLED"
[ -e "$DEFAULT_SITE" ] && rm -f "$DEFAULT_SITE"

log "Testing configuration and restarting Nginx..."
nginx -t
systemctl enable nginx
systemctl restart nginx

echo
echo "[OK] Completed. Place your files in: $FILES_DIR"
echo "   HTTP: http://${WLAN_IP:-<wlan0-IP>}/files/  (once wlan0 has an IP)"
echo "   AP subnet: ${AP_SUBNET:-unknown} (for reference only)"

info "Web server installed."

sleep 5


# === Logrotate config ============================================================
info "Configuring log rotation."

install -m 0644 -o root -g root /dev/null /etc/logrotate.d/mesh-install
cat >/etc/logrotate.d/mesh-install <<'EOF'
/var/log/mesh-install.log {
  rotate 7
  daily
  missingok
  notifempty
  compress
  delaycompress
  create 0640 root adm
}
EOF

info "Log rotation configuration complete."


# === Clean up after installation is complete ====================================
info "Starting final cleanup."

apt-get autoremove -y
apt-get clean

info "Final cleanup complete."

sleep 5

# === Log status of all installed software ===============================================================
info "Summary: OS=$(. /etc/os-release; echo $PRETTY_NAME), Kernel=$(uname -r), batctl=$(batctl -v | head -n1 || echo n/a)"

info "Installation complete."

sleep 5

# === Reboot prompt ==============================================================
info "Prompting for reboot."

if confirm "Do you want to reboot the system?" "y"; then
  info "Initiating reboot."
  /sbin/shutdown -r now
else
  info "No reboot requested; exiting in 10 seconds."
  sleep 10
  info "Exiting installer without reboot."
fi

exit
