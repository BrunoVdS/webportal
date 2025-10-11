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
    echo "[$(timestamp)] ${message}"
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
info "location: /var/log/mesh_radio.log"

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
# ---- Interactieve defaults ------------------------------------------------------

prompt_with_default() {
  local __var_name="$1" __prompt="$2" __default="$3" __value
  local __current_value="${!__var_name:-}"

  if [ -n "$__current_value" ]; then
    printf -v "$__var_name" '%s' "$__current_value"
    info "Using preset value for $__var_name: ${!__var_name}"
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
prompt_with_default IP_CIDR "Node IP/CIDR on bat0" "10.42.0.1/24"
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

info "Install Reticulum "
sudo pip3 install --upgrade rns --break-system-packages

info "Update PATH to local bin folder"
if ! grep -Fxq "export PATH=\$PATH:~/.local/bin" ~/.bashrc
then
    info 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
fi
source ~/.bashrc

info "Check install status"
if ! command -v rnsd &> /dev/null
then
    info "Reticulum not found in PATH, tryign to relink"
    sudo ln -s $(find / -type f -name "rnsd" 2>/dev/null | head -n 1) /usr/local/bin/rnsd 2>/dev/null
fi

info "Create Systemd service (automated startup)"
sudo tee /etc/systemd/system/rnsd.service > /dev/null <<EOF
[Unit]
Description=Reticulum Network Stack
After=network.target

[Service]
ExecStart=/usr/local/bin/rnsd
Restart=always
User=pi

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable rnsd
sudo systemctl start rnsd

info "Reticulum installed"


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
