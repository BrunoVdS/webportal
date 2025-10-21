#!/bin/bash

    # ==============================================================================

    ###                       NEW NODE INSTALL SCRIPT                            ###

    ###          Version 1.2                                                     ###

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

  # === Attended or unattended install funtion
usage() {
  cat <<'EOF'
Usage: install_mesh.sh [--attended | --unattended]

By default the installer starts in attended (interactive) mode.
Pass --unattended to skip prompts and use existing configuration values.
EOF
}

UNATTENDED_INSTALL=${UNATTENDED_INSTALL:-0}
INSTALL_MODE="attended"
if [ "$UNATTENDED_INSTALL" -eq 1 ]; then
  INSTALL_MODE="unattended"
fi

parse_cli_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --attended)
        INSTALL_MODE="attended"
        UNATTENDED_INSTALL=0
        ;;
      --unattended)
        INSTALL_MODE="unattended"
        UNATTENDED_INSTALL=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        error "Unknown option: $1"
        usage
        exit 1
        ;;
      *)
        error "Unexpected positional argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

  # === Network_manager helpers
ensure_network_manager_ready() {
  local nmcli_bin
  nmcli_bin=$(command -v nmcli || true)

  if [[ -z "$nmcli_bin" ]]; then
    error "NetworkManager (nmcli) is not installed. Install the 'network-manager' package before running the access point setup."
    return 1
  fi

  if [[ -z "$SYSTEMCTL" ]]; then
    error "systemctl is not available; cannot manage NetworkManager."
    return 1
  fi

  if ! "$SYSTEMCTL" show NetworkManager >/dev/null 2>&1; then
    error "NetworkManager service is not available. Install and enable 'network-manager' before continuing."
    return 1
  fi

  if ! "$SYSTEMCTL" is-active --quiet NetworkManager; then
    warn "NetworkManager service is not active; attempting to start it."
    if ! "$SYSTEMCTL" start NetworkManager >/dev/null 2>&1; then
      error "Failed to start NetworkManager service."
      return 1
    fi
  fi

  return 0
}

wait_for_wlan_network_details() {
  local attempt ip subnet
  for ((attempt=1; attempt<=10; attempt++)); do
    ip=$(ip -4 addr show dev wlan0 | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 || true)
    subnet=$(ip -4 route show dev wlan0 | awk '/proto kernel/ {print $1}' | head -n1 || true)
    if [[ -n "$ip" && -n "$subnet" ]]; then
      WLAN_IP="$ip"
      AP_SUBNET="$subnet"
      return 0
    fi
    sleep 3
  done

  WLAN_IP="${ip:-}"
  AP_SUBNET="${subnet:-}"
  return 1
}

CONFIG_FILE="/etc/default/mesh.conf"

declare -A SYSTEMD_UNIT_CONTENTS=()
declare -a SYSTEMD_ENABLE_QUEUE=()
declare -a SYSTEMD_START_QUEUE=()

  # === Systemd services helpers
register_systemd_unit() {
  local unit_name="$1"
  local content
  content="$(cat)"
  SYSTEMD_UNIT_CONTENTS["$unit_name"]="$content"
}

queue_enable_service() {
  SYSTEMD_ENABLE_QUEUE+=("$1")
}

queue_start_service() {
  SYSTEMD_START_QUEUE+=("$1")
}

apply_systemd_configuration() {
  local unit

  if [ "${#SYSTEMD_UNIT_CONTENTS[@]}" -eq 0 ]; then
    return
  fi

  for unit in "${!SYSTEMD_UNIT_CONTENTS[@]}"; do
    printf '%s\n' "${SYSTEMD_UNIT_CONTENTS[$unit]}" >"/etc/systemd/system/${unit}.service"
  done

  if [ -z "$SYSTEMCTL" ]; then
    warn "systemctl not available; created unit files but could not enable/start services."
    return
  fi

  "$SYSTEMCTL" daemon-reload

  if [ "${#SYSTEMD_ENABLE_QUEUE[@]}" -gt 0 ]; then
    local -A enabled_seen=()
    for unit in "${SYSTEMD_ENABLE_QUEUE[@]}"; do
      if [ -z "${enabled_seen[$unit]+x}" ]; then
        "$SYSTEMCTL" enable "$unit"
        enabled_seen["$unit"]=1
      fi
    done
  fi

  if [ "${#SYSTEMD_START_QUEUE[@]}" -gt 0 ]; then
    local -A started_seen=()
    for unit in "${SYSTEMD_START_QUEUE[@]}"; do
      if [ -z "${started_seen[$unit]+x}" ]; then
        "$SYSTEMCTL" restart "$unit"
        started_seen["$unit"]=1
      fi
    done
  fi
}

  # === VENV helper
create_venv_service() {
  local name="$1" venv_dir="$2" service_name="$3"
  shift 3
  local -a packages=("$@")

  info "Setting up ${name} virtual environment at ${venv_dir}."

  if [ ! -d "$venv_dir" ]; then
    python3 -m venv "$venv_dir"
    info "Created virtual environment in $venv_dir"
  else
    info "Using existing virtual environment in $venv_dir"
  fi

  "$venv_dir/bin/pip" install --upgrade pip wheel

  if [ "${#packages[@]}" -gt 0 ]; then
    "$venv_dir/bin/pip" install --upgrade "${packages[@]}"
  fi

  local unit_content
  unit_content="$(cat)"
  SYSTEMD_UNIT_CONTENTS["$service_name"]="$unit_content"
  queue_enable_service "$service_name"
  queue_start_service "$service_name"

  info "Queued ${service_name}.service for enablement."
}


  # === Post-install verification helpers
log_apt_package_versions() {
  local pkg version status
  for pkg in "$@"; do
    status=$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)
    if printf '%s' "$status" | grep -q "install ok installed"; then
      version=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)
      info "Package '$pkg' installed (version ${version:-unknown})."
    else
      warn "Package '$pkg' is not installed."
    fi
  done
}

log_python_package_version() {
  local pip_path="$1" package="$2" label="${3:-$2}" version
  if [ -x "$pip_path" ]; then
    version=$("$pip_path" show "$package" 2>/dev/null | awk '/^Version:/{print $2; exit}' || true)
    if [ -n "$version" ]; then
      info "$label package '$package' installed (version $version)."
    else
      warn "$label package '$package' not found via ${pip_path%.*/pip}."
    fi
  else
    warn "pip executable '$pip_path' missing; cannot determine version for $label."
  fi
}

log_service_status() {
  local service active enabled
  if [ -z "$SYSTEMCTL" ]; then
    warn "systemctl not available; skipping service status logging."
    return
  fi

  for service in "$@"; do
    if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
      active=$(systemctl is-active "${service}.service" 2>/dev/null || true)
      enabled=$(systemctl is-enabled "${service}.service" 2>/dev/null || true)
      info "Service ${service}.service status: active=$active, enabled=$enabled."
    else
      warn "Service ${service}.service not found."
    fi
  done
}

log_installation_summary() {
  local os_name kernel_version
  local -a apt_packages=()
  local rns_pip meshtastic_pip flask_pip

  os_name=${RPI_OS_PRETTY_NAME:-$(. /etc/os-release; echo $PRETTY_NAME)}
  kernel_version=$(uname -r)

  info "System summary: OS=${os_name}, Kernel=${kernel_version}."

    # Apt packages installed by this script
  if declare -p PACKAGES >/dev/null 2>&1; then
    apt_packages+=("${PACKAGES[@]}")
  fi
  log_apt_package_versions "${apt_packages[@]}"

    # Python packages installed in virtual environments
  rns_pip="${RNS_VENV_DIR:-/opt/reticulum-venv}/bin/pip"
  meshtastic_pip="${MESHTASTIC_VENV_DIR:-/opt/meshtastic-venv}/bin/pip"
  flask_pip="${FLASK_VENV_DIR:-/opt/flask-venv}/bin/pip"

  log_python_package_version "$rns_pip" "rns" "Reticulum"
  log_python_package_version "$meshtastic_pip" "meshtastic" "Meshtastic CLI"
  log_python_package_version "$flask_pip" "flask" "Flask"
  log_python_package_version "$flask_pip" "gunicorn" "Gunicorn"

  if command_exists batctl; then
    info "batctl detailed version: $(batctl -v | head -n1)"
  fi

  # Services created/managed by this script
  log_service_status mesh rnsd meshtasticd flask-app tailscale mediamtx nftables nginx
}


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

validate_ipv4_cidr() {
  local cidr="$1" ip prefix o1 o2 o3 o4 octet

  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]] || return 1

  IFS=/ read -r ip prefix <<<"$cidr"
  IFS=. read -r o1 o2 o3 o4 <<<"$ip"

  for octet in "$o1" "$o2" "$o3" "$o4"; do
    if ! [[ "$octet" =~ ^[0-9]+$ ]] || [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
      return 1
    fi
  done

  if ! [[ "$prefix" =~ ^[0-9]+$ ]] || [ "$prefix" -lt 0 ] || [ "$prefix" -gt 32 ]; then
    return 1
  fi

  return 0
}


# === Attended or unattended global settings =====================================================
INTERACTIVE_MODE=1

gather_configuration() {
  local interactive=1
  if [ "$UNATTENDED_INSTALL" -eq 1 ]; then
    interactive=0
  elif [ ! -t 0 ] || [ ! -t 1 ]; then
    if [ "$INSTALL_MODE" = "attended" ]; then
      warn "Attended mode requested but no interactive terminal detected; falling back to unattended defaults."
    fi
    interactive=0
  fi

  if [ -r "$CONFIG_FILE" ]; then
    info "Loading configuration defaults from $CONFIG_FILE"
    # shellcheck disable=SC1091
    . "$CONFIG_FILE"
  fi

  : "${MESH_ID:=MYMESH}"
  : "${IFACE:=wlan1}"
  : "${IP_CIDR:=192.168.0.1/24}"
  : "${COUNTRY:=BE}"
  : "${FREQ:=5180}"
  : "${BANDWIDTH:=HT20}"
  : "${MTU:=1468}"
  : "${BSSID:=02:12:34:56:78:9A}"

  if [ -n "${SSID:-}" ] && [ -z "${AP_SSID:-}" ]; then
    AP_SSID="$SSID"
  fi
  if [ -n "${PSK:-}" ] && [ -z "${AP_PSK:-}" ]; then
    AP_PSK="$PSK"
  fi
  if [ -n "${CHANNEL:-}" ] && [ -z "${AP_CHANNEL:-}" ]; then
    AP_CHANNEL="$CHANNEL"
  fi
  if [ -n "${AP_COUNTRY:-}" ]; then
    :
  elif [ -n "${WIFI_COUNTRY:-}" ]; then
    AP_COUNTRY="$WIFI_COUNTRY"
  else
    AP_COUNTRY="${COUNTRY:-BE}"
  fi

  : "${AP_SSID:=MyPiAP}"
  : "${AP_PSK:=SuperSecret123}"
  : "${AP_CHANNEL:=6}"
  : "${AP_COUNTRY:=BE}"
  : "${AP_IP_CIDR:=10.42.10.1/24}"

  if [ $interactive -eq 1 ]; then
    info "Gathering mesh configuration."
    ask "Mesh ID" "$MESH_ID" MESH_ID
    ask "Wireless interface" "$IFACE" IFACE
    ask "Node IP/CIDR on bat0" "$IP_CIDR" IP_CIDR
    ask "Country code (regdom)" "$COUNTRY" COUNTRY
    ask "Frequency (MHz for 5GHz, or 2412/2437/2462 etc.)" "$FREQ" FREQ
    ask "Bandwidth" "$BANDWIDTH" BANDWIDTH
    ask "MTU for bat0" "$MTU" MTU
    ask "IBSS fallback BSSID" "$BSSID" BSSID

    info "Gathering access point configuration."
    ask "SSID (name of your Wi-Fi)" "$AP_SSID" AP_SSID
    while :; do
      ask_hidden "WPA2 password (8-63 characters)" "$AP_PSK" AP_PSK
      if (( ${#AP_PSK}>=8 && ${#AP_PSK}<=63 )); then
        break
      fi
      warn "Password must be 8-63 characters. Please try again."
    done

    while :; do
      ask "Channel (1, 6, or 11)" "$AP_CHANNEL" AP_CHANNEL
      case "$AP_CHANNEL" in
        1|6|11)
          break
          ;;
        *)
          warn "Invalid channel. Choose 1, 6, or 11."
          ;;
      esac
    done

    ask "Wi-Fi country code (REGDOM, e.g., BE/NL/DE)" "$AP_COUNTRY" AP_COUNTRY

    while :; do
      ask "Access point IP/CIDR on wlan0" "$AP_IP_CIDR" AP_IP_CIDR
      if validate_ipv4_cidr "$AP_IP_CIDR"; then
        break
      fi
      warn "Enter an IPv4 address in CIDR notation (e.g., 10.10.10.1/24)."
    done
  else
    info "Running in unattended mode; using configuration defaults for mesh and access point."
  fi

  AP_COUNTRY=$(printf '%s' "$AP_COUNTRY" | tr '[:lower:]' '[:upper:]')
  if ! [[ "$AP_COUNTRY" =~ ^[A-Z]{2}$ ]]; then
    if [ $interactive -eq 1 ]; then
      warn "Unrecognized country code. Falling back to 'BE'."
    fi
    AP_COUNTRY="BE"
  fi

  if (( ${#AP_PSK} < 8 || ${#AP_PSK} > 63 )); then
    die "Access point WPA2 password must be 8-63 characters. Update $CONFIG_FILE or rerun interactively."
  fi

  if ! validate_ipv4_cidr "$AP_IP_CIDR"; then
    die "Access point IP/CIDR '$AP_IP_CIDR' is invalid. Update $CONFIG_FILE or rerun interactively."
  fi

  case "$AP_CHANNEL" in
    1|6|11)
      ;;
    *)
      if [ $interactive -eq 1 ]; then
        warn "Invalid access point channel '$AP_CHANNEL'. Using default channel 6."
      fi
      AP_CHANNEL=6
      ;;
  esac

  INTERACTIVE_MODE=$interactive

  install -m 0644 -o root -g root /dev/null "$CONFIG_FILE"
  cat >"$CONFIG_FILE" <<EOF
MESH_ID="$MESH_ID"
IFACE="$IFACE"
IP_CIDR="$IP_CIDR"
COUNTRY="$COUNTRY"
FREQ="$FREQ"
BANDWIDTH="$BANDWIDTH"
MTU="$MTU"
BSSID="$BSSID"
BATIF="bat0"
AP_SSID="$AP_SSID"
AP_PSK="$AP_PSK"
AP_CHANNEL="$AP_CHANNEL"
AP_COUNTRY="$AP_COUNTRY"
AP_IP_CIDR="$AP_IP_CIDR"
EOF

  info "Saved configuration to $CONFIG_FILE."
}

parse_cli_args "$@"


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

    # Add some info that before did not got logged
info "Log file created."
info "Log file location: $LOGFILE"

info "Installer running in ${INSTALL_MODE} mode."

    # Add we are root
info "Confirmed running as root."


  # === Configuration ===
gather_configuration


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
  network-manager
  curl
  nginx
  php-cli
  php-fpm
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
info "Package installation complete."

sleep 5

# === Mesh ============================================================
info "Creating mesh network."

# ---- Interactive defaults -------------------------------------------------------
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
register_systemd_unit "mesh" <<'EOF'
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

queue_enable_service mesh
queue_start_service mesh

info "Mesh setup done. Gebruik 'meshctl status' voor je daily dosis realiteit."

sleep 5

# === Reticulum ============================================================
  # === Install Reticulum (rnsd)
info "Installing Reticulum."

RNS_VENV_DIR="/opt/reticulum-venv"

create_venv_service "Reticulum" "$RNS_VENV_DIR" "rnsd" rns <<'EOF'
[Unit]
Description=Reticulum Network Stack
After=network.target

[Service]
ExecStart=/usr/local/bin/rnsd
Restart=always

[Install]
WantedBy=multi-user.target
EOF

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
info "Reticulum service configuration queued for activation."

sleep 5

# === Meshtastic CLI =======================================================
  # === Install Meshtastic CLI
info "Installing Meshtastic CLI."

MESHTASTIC_VENV_DIR="/opt/meshtastic-venv"

create_venv_service "Meshtastic CLI" "$MESHTASTIC_VENV_DIR" "meshtasticd" meshtastic <<'EOF'
[Unit]
Description=Meshtastic Daemon
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/meshtasticd
Restart=always

[Install]
WantedBy=multi-user.target
EOF

for cli_tool in meshtastic meshtasticd; do
  cli_path="$MESHTASTIC_VENV_DIR/bin/$cli_tool"
  if [ -f "$cli_path" ] && [ -x "$cli_path" ]; then
    ln -sf "$cli_path" "/usr/local/bin/$cli_tool"
  fi
done

info "Meshtastic CLI installed in isolated virtual environment."
info "Meshtastic service configuration queued for activation."

sleep 5


# === Flask Web Application ====================================================
info "Setting up Flask web application environment."

FLASK_VENV_DIR="/opt/flask-venv"
FLASK_APP_DIR="/opt/flask-app"
FLASK_USER="${SUDO_USER:-root}"
FLASK_GROUP="$(id -gn "$FLASK_USER" 2>/dev/null || echo "$FLASK_USER")"

create_venv_service "Flask web application" "$FLASK_VENV_DIR" "flask-app" flask gunicorn <<EOF_FLASK
[Unit]
Description=Mesh Flask Web Application
After=network.target

[Service]
Type=simple
User=$FLASK_USER
Group=$FLASK_GROUP
WorkingDirectory=$FLASK_APP_DIR
Environment="PATH=$FLASK_VENV_DIR/bin"
ExecStart=$FLASK_VENV_DIR/bin/gunicorn --bind 0.0.0.0:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF_FLASK

install -d -m 0755 -o "$FLASK_USER" -g "$FLASK_GROUP" "$FLASK_APP_DIR"

if [ ! -f "$FLASK_APP_DIR/app.py" ]; then
  cat <<'EOF_APP' >"$FLASK_APP_DIR/app.py"
from flask import Flask

app = Flask(__name__)


@app.route("/")
def index():
    return "Mesh Flask application is running."


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF_APP
  chown "$FLASK_USER":"$FLASK_GROUP" "$FLASK_APP_DIR/app.py"
  info "Created example Flask application at $FLASK_APP_DIR/app.py"
else
  info "Existing Flask application detected at $FLASK_APP_DIR/app.py"
fi

chown -R "$FLASK_USER":"$FLASK_GROUP" "$FLASK_APP_DIR"

info "Flask application environment configured and service queued for activation."

apply_systemd_configuration

sleep 5





# === Tailscale secure networking =================================================
info "Installing Tailscale secure networking."

TAILSCALE_DIST=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  TAILSCALE_DIST="${VERSION_CODENAME:-}"
  TAILSCALE_ID="${ID:-}"
  TAILSCALE_ID_LIKE="${ID_LIKE:-}"
fi

if [ -z "$TAILSCALE_DIST" ]; then
  TAILSCALE_DIST="$(lsb_release -cs 2>/dev/null || true)"
fi

if [ -z "$TAILSCALE_DIST" ]; then
  die "Unable to determine distribution codename for Tailscale repository configuration."
fi

TAILSCALE_FLAVOR="debian"
case "${TAILSCALE_ID:-}" in
  ubuntu)
    TAILSCALE_FLAVOR="ubuntu"
    ;;
  raspbian)
    TAILSCALE_FLAVOR="raspbian"
    ;;
  debian)
    TAILSCALE_FLAVOR="debian"
    ;;
  *)
    if printf '%s' "${TAILSCALE_ID_LIKE:-}" | grep -qi 'ubuntu'; then
      TAILSCALE_FLAVOR="ubuntu"
    elif printf '%s' "${TAILSCALE_ID_LIKE:-}" | grep -qi 'raspbian'; then
      TAILSCALE_FLAVOR="raspbian"
    else
      TAILSCALE_FLAVOR="debian"
    fi
    ;;
esac

TAILSCALE_REPO_BASE="https://pkgs.tailscale.com/stable/${TAILSCALE_FLAVOR}"
TAILSCALE_KEYRING="/usr/share/keyrings/tailscale-archive-keyring.gpg"
TAILSCALE_APT_SOURCE="/etc/apt/sources.list.d/tailscale.list"

info "Configuring Tailscale repository (${TAILSCALE_FLAVOR}) for '${TAILSCALE_DIST}'."

install -d -m 0755 /usr/share/keyrings
curl -fsSL "${TAILSCALE_REPO_BASE}/${TAILSCALE_DIST}.gpg" -o "$TAILSCALE_KEYRING"
chmod 0644 "$TAILSCALE_KEYRING"

cat <<EOF_TAILSCALE_LIST >"$TAILSCALE_APT_SOURCE"
deb [signed-by=$TAILSCALE_KEYRING] ${TAILSCALE_REPO_BASE} ${TAILSCALE_DIST} main
EOF_TAILSCALE_LIST

chmod 0644 "$TAILSCALE_APT_SOURCE"

apt-get update -y
apt-get install -y tailscale

register_systemd_unit "tailscaled" <<'EOF'
[Unit]
Description=Tailscale node agent
Documentation=https://tailscale.com/kb/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/sbin/tailscaled
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

queue_enable_service tailscaled
queue_start_service tailscaled

info "Tailscale installed and service configuration queued for activation."

apply_systemd_configuration

sleep 5



# === MediaMTX streaming server ==================================================
info "Installing MediaMTX streaming server."

MEDIAMTX_VERSION="${MEDIAMTX_VERSION:-v1.15.2}"
MEDIAMTX_BINARY="/usr/local/bin/mediamtx"
MEDIAMTX_DATA_DIR="/var/lib/mediamtx"

MEDIAMTX_ARCH="$(dpkg --print-architecture)"
case "$MEDIAMTX_ARCH" in
  amd64)
    MEDIAMTX_RELEASE_ARCH="amd64"
    ;;
  arm64)
    MEDIAMTX_RELEASE_ARCH="arm64v8"
    ;;
  armhf)
    MEDIAMTX_RELEASE_ARCH="arm32v7"
    ;;
  *)
    die "Unsupported architecture '$MEDIAMTX_ARCH' for MediaMTX installation."
    ;;
esac

MEDIAMTX_TARBALL="mediamtx_${MEDIAMTX_VERSION}_linux_${MEDIAMTX_RELEASE_ARCH}.tar.gz"
MEDIAMTX_URL="https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/${MEDIAMTX_TARBALL}"
MEDIAMTX_TMPDIR="$(mktemp -d)"

info "Downloading MediaMTX (${MEDIAMTX_VERSION}) for ${MEDIAMTX_ARCH}."
curl -fsSL "$MEDIAMTX_URL" -o "$MEDIAMTX_TMPDIR/$MEDIAMTX_TARBALL"

tar -xzf "$MEDIAMTX_TMPDIR/$MEDIAMTX_TARBALL" -C "$MEDIAMTX_TMPDIR"
install -m 0755 -o root -g root "$MEDIAMTX_TMPDIR/mediamtx" "$MEDIAMTX_BINARY"
install -d -m 0755 -o root -g root "$MEDIAMTX_DATA_DIR"

rm -rf "$MEDIAMTX_TMPDIR"

register_systemd_unit "mediamtx" <<'EOF'
[Unit]
Description=MediaMTX Streaming Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mediamtx
WorkingDirectory=/var/lib/mediamtx
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

queue_enable_service mediamtx
queue_start_service mediamtx

info "MediaMTX installed and service configuration queued for activation."

apply_systemd_configuration

sleep 5


# === NFtables configuration =====================================================
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
    iifname "eth0" tcp dport 22 accept
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

if [ $INTERACTIVE_MODE -eq 1 ]; then
  echo
  echo "Summary:"
  echo "  SSID        : $AP_SSID"
  echo "  WPA2 PSK    : (hidden for security)"
  echo "  Channel     : $AP_CHANNEL"
  echo "  IPv4/CIDR   : $AP_IP_CIDR"
  echo "  Country code: $AP_COUNTRY"
  echo
fi

CLEAN=true
if [ $INTERACTIVE_MODE -eq 1 ]; then
  confirm "Remove all existing Wi-Fi profiles before continuing?" || CLEAN=false
  echo
  confirm "Proceed with access point configuration?" || die "Operation cancelled by user."
fi

if ! ensure_network_manager_ready; then
  die "Access point setup requires NetworkManager (nmcli). Please install and enable 'network-manager' before rerunning."
fi

# 1) Persist and apply country code
log "Setting country code to ${AP_COUNTRY}..."
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_wifi_country "${AP_COUNTRY}" || true
fi
iw reg set "${AP_COUNTRY}" || true
  # === Ensure wpa_supplicant also includes the country code for consistency
if [[ -f /etc/wpa_supplicant/wpa_supplicant.conf ]]; then
  grep -q "^country=${AP_COUNTRY}\b" /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || \
    sed -i "1i country=${AP_COUNTRY}" /etc/wpa_supplicant/wpa_supplicant.conf || true
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
"$SYSTEMCTL" restart NetworkManager
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
log "Creating AP profile: SSID='${AP_SSID}', channel=${AP_CHANNEL}, WPA2..."
nmcli -t -f NAME connection show | grep -Fxq "$AP_SSID" && nmcli connection delete "$AP_SSID" || true
nmcli connection add type wifi ifname wlan0 con-name "${AP_SSID}" ssid "${AP_SSID}"

nmcli connection modify "${AP_SSID}" \
  802-11-wireless.mode ap \
  802-11-wireless.band bg \
  802-11-wireless.channel "${AP_CHANNEL}" \
  802-11-wireless.hidden no \
  ipv4.method shared \
  ipv6.method ignore \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "${AP_PSK}" \
  connection.autoconnect yes \
  wifi.cloned-mac-address permanent

if [ -n "${AP_IP_CIDR:-}" ]; then
  nmcli connection modify "${AP_SSID}" ipv4.addresses "${AP_IP_CIDR}"
  AP_IP_ADDR="${AP_IP_CIDR%%/*}"
  if [ -n "$AP_IP_ADDR" ]; then
    nmcli connection modify "${AP_SSID}" ipv4.gateway "$AP_IP_ADDR"
  fi
  unset AP_IP_ADDR
fi

# 6b) Channel width 20 MHz (different NM builds: try both variants)
nmcli connection modify "${AP_SSID}" 802-11-wireless.channel-width 20mhz 2>/dev/null || \
nmcli connection modify "${AP_SSID}" 802-11-wireless.channel-width ht20 2>/dev/null || true

# 6c) iOS-friendly + disable PMF (mandatory 802.11w breaks on Broadcom)
nmcli connection modify "${AP_SSID}" +wifi-sec.proto rsn       || true
nmcli connection modify "${AP_SSID}" +wifi-sec.group ccmp      || true
nmcli connection modify "${AP_SSID}" +wifi-sec.pairwise ccmp   || true
nmcli connection modify "${AP_SSID}" 802-11-wireless-security.pmf 0 2>/dev/null || \
nmcli connection modify "${AP_SSID}" wifi-sec.pmf 0 2>/dev/null || true

# 7) Start AP with fallback channels (1/6/11 provide reliable options)
start_ap() {
  local ch="$1"
  log "Starting AP on channel ${ch}..."
  nmcli connection modify "${AP_SSID}" 802-11-wireless.channel "${ch}" || true
  nmcli connection up "${AP_SSID}"
}

set +e
start_ap "${AP_CHANNEL}"
RC=$?
if [ $RC -ne 0 ]; then
  log "Start failed. Attempting fallback on channels 1/6/11..."
  for ch in 1 6 11; do
    [[ "$ch" == "$AP_CHANNEL" ]] && continue
    start_ap "$ch"; RC=$?
    [ $RC -eq 0 ] && { AP_CHANNEL="$ch"; break; }
  done
fi
set -e

if ! wait_for_wlan_network_details; then
  die "Unable to detect wlan0 IPv4 details after waiting for NetworkManager. Access point setup cannot continue."
fi

echo
nmcli -f DEVICE,TYPE,STATE,CONNECTION device status | sed 's/^/    /'
echo

if nmcli -t -f GENERAL.STATE connection show "${AP_SSID}" >/dev/null 2>&1; then
  echo "[OK] Completed. SSID: ${AP_SSID}"
  echo "   WPA2 password: (still hidden for security)"
  echo "   Channel: ${AP_CHANNEL}"
  echo "   Device IP on wlan0: ${WLAN_IP:-(no IPv4 address detected yet)}"
  echo
  echo "Helpful commands:"
  echo "  - Change channel: nmcli con mod \"${AP_SSID}\" 802-11-wireless.channel 1 && nmcli con up \"${AP_SSID}\""
  echo "  - Update SSID   : nmcli con mod \"${AP_SSID}\" 802-11-wireless.ssid \"NewSSID\" && nmcli con up \"${AP_SSID}\""
  echo "  - Update password: nmcli con mod \"${AP_SSID}\" wifi-sec.psk \"NewPassword\" && nmcli con up \"${AP_SSID}\""
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

log "Detected wlan0 IPv4 address ${WLAN_IP} on subnet ${AP_SUBNET}."

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WEB_ROOT="/var/www/server"
FILES_DIR="$WEB_ROOT/files"
SITE_AVAIL="/etc/nginx/sites-available/fileserver"
SITE_ENABLED="/etc/nginx/sites-enabled/fileserver"
DEFAULT_SITE="/etc/nginx/sites-enabled/default"
OWNER_USER="${SUDO_USER:-pi}"

log "Installing packages (nginx)..."
info "nginx installation handled with base package setup."

log "Creating directories and setting permissions..."
mkdir -p "$WEB_ROOT"
mkdir -p "$FILES_DIR"
chown -R "$OWNER_USER":www-data "$WEB_ROOT"
chmod -R 775 "$FILES_DIR"

log "Writing Nginx configuration..."
PHP_FPM_SERVICE=$(systemctl list-unit-files 'php*-fpm.service' --no-legend 2>/dev/null | awk 'NR==1 {print $1}' || true)
if [ -n "$PHP_FPM_SERVICE" ]; then
  info "Ensuring $PHP_FPM_SERVICE is enabled."
  systemctl enable "$PHP_FPM_SERVICE"
  systemctl restart "$PHP_FPM_SERVICE"
else
  warn "No php-fpm service detected; PHP content may not be served until the service is installed."
fi

PHP_FPM_SOCKET=""
if [ -d /run/php ]; then
  PHP_FPM_SOCKET=$(find /run/php -maxdepth 1 -type s -name 'php*-fpm.sock' | head -n1 || true)
fi
if [ -z "$PHP_FPM_SOCKET" ]; then
  PHP_FPM_SOCKET="/run/php/php-fpm.sock"
  warn "Defaulting to PHP-FPM socket path $PHP_FPM_SOCKET in Nginx configuration."
else
  info "Using PHP-FPM socket $PHP_FPM_SOCKET."
fi

cat > "$SITE_AVAIL" <<'NGINXCONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    root /var/www/server;
    index index.php index.html;

    location /files/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass FASTCGI_SOCKET;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINXCONF

sed -i "s|FASTCGI_SOCKET|unix:$PHP_FPM_SOCKET|" "$SITE_AVAIL"

ASSETS_DIR="$SCRIPT_DIR/web_assets"
if [ -d "$ASSETS_DIR" ]; then
  info "Deploying web assets from $ASSETS_DIR to $WEB_ROOT."
  cp -a "$ASSETS_DIR/." "$WEB_ROOT/"
  chown -R "$OWNER_USER":www-data "$WEB_ROOT"
  chmod -R 775 "$FILES_DIR"
else
  warn "Web assets directory $ASSETS_DIR not found; default site will be empty."
fi

log "Activating site configuration..."
ln -sf "$SITE_AVAIL" "$SITE_ENABLED"
[ -e "$DEFAULT_SITE" ] && rm -f "$DEFAULT_SITE"

log "Testing configuration and restarting Nginx..."
nginx -t
systemctl enable nginx
systemctl restart nginx

if [ -n "$PHP_FPM_SERVICE" ]; then
  systemctl restart "$PHP_FPM_SERVICE"
fi

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
log_installation_summary

info "Installation complete."

sleep 5

# === Reboot prompt ==============================================================
info "Prompting for reboot."

if [ $INTERACTIVE_MODE -eq 1 ]; then
  if confirm "Do you want to reboot the system?" "y"; then
    info "Initiating reboot."
    /sbin/shutdown -r now
  else
    info "No reboot requested; exiting in 3 seconds."
    sleep 3
    info "Exiting installer without reboot."
  fi
else
  info "Unattended mode detected; skipping reboot prompt."
fi

exit
