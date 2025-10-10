#!/usr/bin/env bash
# setup_fileserver_nginx.sh
# Bestandsserver bovenop bestaande AP (NetworkManager/nmcli). Wijzig GEEN AP-instellingen.
# Resultaat: http://<wlan0-IP>/files/

set -euo pipefail

die(){ echo "💀 $*" >&2; exit 1; }
log(){ echo -e "[*] $*"; }

[[ $EUID -eq 0 ]] || die "Run dit script met sudo, kampioen."
ip link show wlan0 >/dev/null 2>&1 || die "Interface wlan0 niet gevonden. Start je AP-script eerst."

# Haal IP en subnet van wlan0 (AP moet al actief zijn)
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

# Landing page (als die er nog niet is)
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
