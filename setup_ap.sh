#!/usr/bin/env bash
# raspi_ap_final.sh — Interactieve AP-setup voor Raspberry Pi OS (Bookworm/NetworkManager)
# Doet: landcode, Broadcom-driver herladen, powersave uit, AP op wlan0 (2.4 GHz), WPA2, internetdeling.
# Lost 'htmode' property op door 'channel-width' te gebruiken.

set -euo pipefail

die(){ echo "💀 $*" >&2; exit 1; }
log(){ echo -e "[*] $*"; }

sudo apt-get update 
sudo apt-get upgrade -y

[[ $EUID -eq 0 ]] || die "Run dit script met sudo, kampioen."
command -v nmcli >/dev/null || die "nmcli ontbreekt. Dit vereist Raspberry Pi OS Bookworm met NetworkManager."
ip link show wlan0 >/dev/null 2>&1 || die "Interface wlan0 niet gevonden."

# --- Helpers ---
ask() { local p="$1" d="${2:-}" v; read -r -p "$p${d:+ [$d]}: " v || true; printf -v "$3" "%s" "${v:-$d}"; }
ask_hidden(){ local p="$1" d="${2:-}" v; read -r -s -p "$p${d:+ [$d]}: " v || true; echo; printf -v "$3" "%s" "${v:-$d}"; }
confirm(){ local q="$1" a; read -r -p "$q [y/N]: " a || true; [[ "$a" =~ ^[Yy]$ ]]; }

echo "=== Raspberry Pi Access Point (wlan0) Setup — Interactieve modus ==="

SSID_D="MyPiAP"
PSK_D="SuperSecret123"
CHAN_D="6"      # 1,6,11 zijn veiligst
CTRY_D="BE"

SSID=""; PSK=""; CHANNEL=""; COUNTRY=""

ask "SSID (naam van je Wi-Fi)" "$SSID_D" SSID

# WPA2 PSK validatie
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
# Zet country= ook in wpa_supplicant (consistentie)
if [[ -f /etc/wpa_supplicant/wpa_supplicant.conf ]]; then
  grep -q "^country=${COUNTRY}\b" /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || \
    sed -i "1i country=${COUNTRY}" /etc/wpa_supplicant/wpa_supplicant.conf || true
fi

# 2) Driver herladen (reset chanspec/PMF capriolen)
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
