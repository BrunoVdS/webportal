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

  read -r -p "$prompt_text" input || return 1
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

  read -rs -p "$prompt_text" input || return 1
  echo
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
    read -r -p "$prompt $suffix " reply || return 1
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
        echo "Antwoord met 'y' of 'n'."
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
echo "Creating log file."

install -m 0640 -o root -g adm /dev/null "$LOGFILE"
exec 3>&1
exec >>"$LOGFILE" 2>&1


  # First logs added
info ""
info "================================================="
info "===                                           ==="
info "===    Installation of the Mesh Radio v1.0.   ==="
info "===                                           ==="
info "================================================="
info ""
info ""

  # Add system info
info "Summary: OS=${RPI_OS_PRETTY_NAME:-$(. /etc/os-release; echo $PRETTY_NAME)}, Kernel=$(uname -r))"

  #add some info that before did not got logged,
info "Log file is created."
info "location: $LOGFILE"

info "Detected operating system: ${RPI_OS_PRETTY_NAME:-unknown}."

  # Add we are root
info "Confirmed running as root."


  # === Housekeeping
info "Housekeeping starting."

  # Perform a small cleanup in the user’s home directory
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
info "Upgrade and Update of the operatingsystem starting."

apt-get update -y
apt-get -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        dist-upgrade -y

info "Update and Upgrade of the operatingsystem is complete."

sleep 5


# === Prerequisites - install needed packages ===================================
  # === Pakages list
PACKAGES=(
  nano
  python3
  python3-pip
  batctl
  iw
  iproute2
  wireless-regdb
)

info "Package install starting."

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

info "Installation of all packages is complete."

sleep 5

# === Mesh ============================================================
info "Creating mesh network."

# ---- Interactieve defaults ------------------------------------------------------
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
prompt_with_default FREQ "Frequency (MHz for 5GHz, of 2412/2437/2462 etc.)" "5180"
prompt_with_default BANDWIDTH "Bandwidth" "HT20"
prompt_with_default MTU "MTU voor bat0" "1468"
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
  # Desingage NetworkManager
  command -v nmcli >/dev/null 2>&1 && nmcli dev set "$IFACE" managed no || true

  ip link set "$IFACE" down || true
  if mesh_supported; then
    iw dev "$IFACE" set type mp
    ip link set "$IFACE" up
    iw dev "$IFACE" mesh join "$MESH_ID" freq "$FREQ" "$BANDWIDTH"
  else
    # IBSS fallback. Huil maar niet.
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


# === Reticulum ============================================================
info "Installing Reticulum."

pip3 install --upgrade rns --break-system-packages

bashrc="$TARGET_HOME/.bashrc"
touch "$bashrc"
if ! grep -Fxq 'export PATH="$PATH:$HOME/.local/bin"' "$bashrc" 2>/dev/null; then
  printf '%s\n' 'export PATH="$PATH:$HOME/.local/bin"' >>"$bashrc"
  info "Added ~/.local/bin to PATH in $bashrc"
fi

# shellcheck disable=SC1090
. "$bashrc" || true

if ! command -v rnsd >/dev/null 2>&1; then
  warn "rnsd not found in PATH; attempting to locate binary."
  RN_PATH=$(find / -type f -name "rnsd" 2>/dev/null | head -n1 || true)
  if [[ -n "$RN_PATH" && -e "$RN_PATH" ]]; then
    if ln -sf "$RN_PATH" /usr/local/bin/rnsd; then
      info "Created symlink for rnsd at /usr/local/bin/rnsd"
    else
      warn "Failed to create rnsd symlink from $RN_PATH"
    fi
  else
    warn "Could not locate rnsd binary automatically."
  fi
fi

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

info "Reticulum installed"


# === Access Point setup =======================================================
echo "=== Raspberry Pi Access Point (wlan0) Setup — Interactieve modus ==="

SSID_D="MyPiAP"
PSK_D="SuperSecret123"
CHAN_D="6"      # 1,6,11 zijn veiligst
CTRY_D="BE"

SSID=""; PSK=""; CHANNEL=""; COUNTRY=""

ask "SSID (naam van je Wi-Fi)" "$SSID_D" SSID

# === WPA2 PSK validatie
while :; do
  ask_hidden "WPA2-wachtwoord (8–63 tekens)" "$PSK_D" PSK
  (( ${#PSK}>=8 && ${#PSK}<=63 )) && break || echo "❌ Wachtwoord moet 8–63 tekens zijn. Probeer opnieuw."
done

echo "Kies 2.4 GHz kanaal (1/6/11 zijn verstandig; 12/13 = iPhone-blind)."
ask "Kanaal (1, 6 of 11)" "$CHAN_D" CHANNEL
while ! [[ "$CHANNEL" =~ ^(1|6|11)$ ]]; do
  echo "❌ Ongeldig kanaal. Kies 1, 6 of 11."
  ask "Kanaal (1, 6 of 11)" "$CHAN_D" CHANNEL
done

ask "Wi-Fi landcode (REGDOM, bv. BE/NL/DE)" "$CTRY_D" COUNTRY
COUNTRY=$(echo "$COUNTRY" | tr '[:lower:]' '[:upper:]')
[[ "$COUNTRY" =~ ^[A-Z]{2}$ ]] || { echo "⚠️ Landcode onhandig. Gebruik '$CTRY_D'."; COUNTRY="$CTRY_D"; }

echo
echo "Samenvatting:"
echo "  SSID     : $SSID"
echo "  WPA2 PSK : (verborgen — verrassing)"
echo "  Kanaal   : $CHANNEL"
echo "  Landcode : $COUNTRY"
echo

CLEAN=true
confirm "Alle bestaande Wi-Fi-profielen opruimen vóór we beginnen?" || CLEAN=false
echo
confirm "Doorgaan en AP configureren?" || die "Afgebroken. Commitment is moeilijk, snap ik."

# 1) Landcode persistent + runtime
log "Landcode instellen op ${COUNTRY}…"
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_wifi_country "${COUNTRY}" || true
fi
iw reg set "${COUNTRY}" || true
  # === Zet country= ook in wpa_supplicant (consistentie)
if [[ -f /etc/wpa_supplicant/wpa_supplicant.conf ]]; then
  grep -q "^country=${COUNTRY}\b" /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || \
    sed -i "1i country=${COUNTRY}" /etc/wpa_supplicant/wpa_supplicant.conf || true
fi

# === Driver herladen (reset chanspec/PMF capriolen)
log "Broadcom/CFG80211 driver herladen…"
modprobe -r brcmfmac brcmutil cfg80211 2>/dev/null || true
modprobe cfg80211
modprobe brcmutil 2>/dev/null || true
modprobe brcmfmac  2>/dev/null || true

# 3) rfkill/Radio & powersave uit
log "Wi-Fi radio aan en powersave uit…"
rfkill unblock all || true
nmcli radio wifi on
mkdir -p /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/wifi-powersave-off.conf <<'EOF'
[connection]
wifi.powersave=2
EOF

# 4) NetworkManager herstarten
log "NetworkManager herstarten…"
systemctl restart NetworkManager
sleep 2

# 5) Opruimen
if $CLEAN; then
  log "Profielen opruimen (alle 802-11-wireless)…"
  nmcli device disconnect wlan0 || true
  while read -r NAME; do
    [[ -n "$NAME" ]] && nmcli connection delete "$NAME" || true
  done < <(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1}')
else
  log "Profielen blijven staan; we disconnecten wlan0 in elk geval."
  nmcli device disconnect wlan0 || true
fi

# 6) AP-profiel maken
log "AP-profiel maken: SSID='${SSID}', kanaal=${CHANNEL}, WPA2…"
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

# 6b) Kanaalbreedte 20 MHz (verschillende NM builds: probeer beide varianten)
nmcli connection modify "${SSID}" 802-11-wireless.channel-width 20mhz 2>/dev/null || \
nmcli connection modify "${SSID}" 802-11-wireless.channel-width ht20 2>/dev/null || true

# 6c) iOS-vriendelijk + PMF uit (802.11w verplicht breekt op Broadcom)
nmcli connection modify "${SSID}" +wifi-sec.proto rsn       || true
nmcli connection modify "${SSID}" +wifi-sec.group ccmp      || true
nmcli connection modify "${SSID}" +wifi-sec.pairwise ccmp   || true
nmcli connection modify "${SSID}" 802-11-wireless-security.pmf 0 2>/dev/null || \
nmcli connection modify "${SSID}" wifi-sec.pmf 0 2>/dev/null || true

# 7) Start AP met fallback-kanalen (1/6/11, want Broadcom houdt van keuzes)
start_ap() {
  local ch="$1"
  log "AP starten op kanaal ${ch}…"
  nmcli connection modify "${SSID}" 802-11-wireless.channel "${ch}" || true
  nmcli connection up "${SSID}"
}

set +e
start_ap "${CHANNEL}"
RC=$?
if [ $RC -ne 0 ]; then
  log "Start faalde. Fallback proberen op 1/6/11…"
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
  echo "✅ Klaar. SSID: ${SSID}"
  echo "   WPA2-wachtwoord: (ja, nog steeds verborgen — omdat het kan)"
  echo "   Kanaal: ${CHANNEL}"
  echo "   Pi-adres op wlan0: ${IP4:-(nog geen IPv4 gezien)}"
  echo
  echo "Tips:"
  echo "  • Kanaal wisselen: nmcli con mod \"${SSID}\" 802-11-wireless.channel 1 && nmcli con up \"${SSID}\""
  echo "  • SSID wijzigen : nmcli con mod \"${SSID}\" 802-11-wireless.ssid \"NieuwSSID\" && nmcli con up \"${SSID}\""
  echo "  • Wachtwoord   : nmcli con mod \"${SSID}\" wifi-sec.psk \"NieuwWachtwoord\" && nmcli con up \"${SSID}\""
else
  die "AP niet actief. Logs checken: 
  - journalctl -u NetworkManager -b --no-pager | tail -n 200
  - dmesg | grep -i -E 'brcm|wlan0|cfg80211|ieee80211' | tail -n 200"
fi


# === Setting up webserver =======================================================
  # === Haal IP en subnet van wlan0 (AP moet al actief zijn)
WLAN_IP=$(ip -4 addr show wlan0 | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 || true)
AP_SUBNET=$(ip -4 route show dev wlan0 | awk '/proto kernel/ {print $1}' | head -n1 || true)
[[ -n "${WLAN_IP}" ]] || log "⚠️  Kon (nog) geen IP op wlan0 zien. Ga ervan uit dat NM het zo geeft."

FILES_DIR="/var/www/html/files"
SITE_AVAIL="/etc/nginx/sites-available/fileserver"
SITE_ENABLED="/etc/nginx/sites-enabled/fileserver"
DEFAULT_SITE="/etc/nginx/sites-enabled/default"
OWNER_USER="${SUDO_USER:-pi}"

log "Pakketjes installeren (nginx)…"
apt-get update -y
apt-get install -y nginx

log "Mappen & rechten…"
mkdir -p "$FILES_DIR"
chown -R "$OWNER_USER":www-data "$FILES_DIR"
chmod -R 775 "$FILES_DIR"

log "Nginx-config schrijven…"
cat > "$SITE_AVAIL" <<'NGINXCONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root /var/www/html;
    index index.html;

    # Directory listing voor /files/
    location /files/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        # eventueel rate limiting, headers, etc. hier
    }

    # Simpele landing page
    location = / {
        try_files $uri /index.html;
    }
}
NGINXCONF

  # === Landing page
if [ ! -f /var/www/html/index.html ]; then
cat > /var/www/html/index.html <<'HTML'
<!doctype html>
<html lang="nl"><head><meta charset="utf-8"><title>Pi Download Server</title></head>
<body>
  <h1>Welkom op de Raspberry Pi downloadserver</h1>
  <p>Bestanden: <a href="/files/">/files/</a></p>
</body></html>
HTML
fi

log "Site activeren…"
ln -sf "$SITE_AVAIL" "$SITE_ENABLED"
[ -e "$DEFAULT_SITE" ] && rm -f "$DEFAULT_SITE"

log "Config testen & herstarten…"
nginx -t
systemctl enable nginx
systemctl restart nginx

echo
echo "✅ Klaar. Zet je bestanden in: $FILES_DIR"
echo "   HTTP: http://${WLAN_IP:-<wlan0-IP>}/files/  (zodra wlan0 IP heeft)"
echo "   AP-subnet: ${AP_SUBNET:-onbekend} (alleen ter info)"


# === Logrotate config ============================================================
info "Logrotate config."

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

info "Logrotate config done."


# === Clean up after installation is complete ====================================
info "Clean up before end of script."

apt-get autoremove -y
apt-get clean

info "Clean up finished."

sleep 5

# === Log status of all installed software ===============================================================
info "Summary: OS=$(. /etc/os-release; echo $PRETTY_NAME), Kernel=$(uname -r), batctl=$(batctl -v | head -n1 || echo n/a)"

info "Installation complete."

sleep 5

# === Reboot prompt ==============================================================
info "Reboot or not"

read -r -p "Do you want to reboot the system? [Y/n]: " REPLY || REPLY=""
REPLY="${REPLY:-Y}"
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  info "Initiating reboot."
  /sbin/shutdown -r now
else
  info "we will exit the script now."
fi

exit
