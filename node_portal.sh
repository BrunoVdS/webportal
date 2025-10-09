#!/usr/bin/env bash
# install_node_portal.sh — zet node.local + nginx portal neer zonder je AP-setup te slopen.
# Vereist: Raspberry Pi OS (Bookworm), sudo.
set -euo pipefail

die(){ echo "💀 $*" >&2; exit 1; }
say(){ echo -e "[*] $*"; }

[[ $EUID -eq 0 ]] || die "Run met sudo, rebel zonder oorzaak."

# --- 0) Basis checks ---
command -v apt-get >/dev/null || die "apt-get ontbreekt. Dit is geen Debian-achtig systeem?"
# NetworkManager/nmcli is voor je AP-script; niet strikt nodig hier.

say "Pakketlijst verversen…"
apt-get update -y

# --- 1) mDNS & webserver ---
say "Installeren: avahi-daemon, libnss-mdns, nginx…"
DEBIAN_FRONTEND=noninteractive apt-get install -y avahi-daemon libnss-mdns nginx

# --- 2) nsswitch.conf: mdns inschakelen voor .local resolutie ---
if ! grep -E '^[# ]*hosts:.*mdns' /etc/nsswitch.conf >/dev/null; then
  say "mdns in /etc/nsswitch.conf toevoegen…"
  sed -i 's/^\([# ]*hosts:.*\)files dns.*/\1files mdns_minimal [NOTFOUND=return] dns mdns/' /etc/nsswitch.conf || true
fi

# --- 3) Avahi configureren zonder system hostname te forceren ---
AVAHI_CONF="/etc/avahi/avahi-daemon.conf"
if grep -q '^#*host-name=' "$AVAHI_CONF"; then
  say "Avahi host-name op 'node' zetten…"
  sed -i 's/^#*host-name=.*/host-name=node/' "$AVAHI_CONF"
else
  say "host-name=node toevoegen aan Avahi config…"
  sed -i '/^\[server\]/a host-name=node' "$AVAHI_CONF"
fi

systemctl enable avahi-daemon
systemctl restart avahi-daemon

# --- 4) Webroot + bestanden ---
ROOT="/var/www/node"
mkdir -p "$ROOT/files"

# index.html & styles.css invoegen (alleen overschrijven als ze ontbreken of als --force is meegegeven)
FORCE="${1:-}"
copy_file(){
  local name="$1"
  local tmp="/tmp/$name"
  cat >"$tmp" <<'EOF_HTML_CSS'
__PAYLOAD__
EOF_HTML_CSS
  if [[ ! -f "$ROOT/$name" || "$FORCE" == "--force" ]]; then
    say "Bijwerken $name → $ROOT/$name"
    mv "$tmp" "$ROOT/$name"
  else
    say "$name bestaat al — overslaan (gebruik --force om te overschrijven)."
    rm -f "$tmp"
  fi
}

# payloads vervangen we zometeen met echte content via here-doc substitution
# (we plaatsen markers en vervangen ze met sed)
INDEX_PAYLOAD='__INDEX__'
CSS_PAYLOAD='__CSS__'

# index.html
sed "s|__PAYLOAD__|$INDEX_PAYLOAD|" >/tmp/_index.tpl
# styles.css
sed "s|__PAYLOAD__|$CSS_PAYLOAD|" >/tmp/_styles.tpl

# kopiëren
if [[ ! -f "$ROOT/index.html" || "$FORCE" == "--force" ]]; then
  say "Schrijven index.html…"
  sed '1,/$INDEX_START/d;/$INDEX_END/,$d' "$0" > "$ROOT/index.html"
fi
if [[ ! -f "$ROOT/styles.css" || "$FORCE" == "--force" ]]; then
  say "Schrijven styles.css…"
  sed '1,/$CSS_START/d;/$CSS_END/,$d' "$0" > "$ROOT/styles.css"
fi

# --- 5) Nginx site config ---
SITE="/etc/nginx/sites-available/node"
cat >"$SITE" <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name node.local;

    root /var/www/node;
    index index.html;

    # Statische bestanden
    location / {
        try_files $uri $uri/ =404;
    }

    # Eenvoudige fileserver
    location /files/ {
        autoindex on;
        alias /var/www/node/files/;
    }

    # Toekomstige API placeholders (kun je later via FastCGI/uwsgi/proxy vullen)
    location /api/status { return 204; }
    location /api/mesh   { return 204; }
}
NGINX

ln -sf "$SITE" /etc/nginx/sites-enabled/node
# optioneel: default-site uitschakelen als die bestaat (we gebruiken deze al als default_server)
if [[ -f /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default
fi

nginx -t
systemctl enable nginx
systemctl restart nginx

# --- 6) Info uit je AP-config (best effort) ---
SSID="(onbekend)"
APIP="(onbekend)"
if command -v nmcli >/dev/null 2>&1; then
  SSID=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="802-11-wireless"{print $1; exit}' || echo "$SSID")
fi
APIP=$(ip -4 addr show dev wlan0 | awk '/inet /{print $2; exit}' || echo "$APIP")

# --- 7) Permissies en afronding ---
chown -R www-data:www-data "$ROOT" || true
chmod -R a+rX "$ROOT" || true

echo
echo "✅ Klaar. Probeer:  http://node.local  (zelfde LAN/AP, mDNS nodig)"
echo "   SSID (indicatief): ${SSID}"
echo "   AP IPv4 (indicatief): ${APIP}"
echo "   Webroot: ${ROOT}"
echo "   Bestanden droppen in: ${ROOT}/files/"
echo
echo "Tip: wil je de meegeleverde index/styles overschrijven bij een update?"
echo "     Run: sudo bash $0 --force"
exit 0

# === EMBEDDED ASSETS (laat staan) ===
$INDEX_START
<!doctype html>
<html lang="nl">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Node Portal — node.local</title>
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
  <header class="site-header">
    <h1>Node Portal</h1>
    <p>Welkom op <strong>node.local</strong>. Ja, een echte URL. Zonder die sexy cijfers.</p>
  </header>
  <main class="grid">
    <section class="card">
      <h2>Netwerkmonitoring</h2>
      <div class="keyvals" id="netmon">
        <div><span>SSID</span><strong id="ssid">—</strong></div>
        <div><span>AP IPv4</span><strong id="apip">—</strong></div>
        <div><span>Clients</span><strong id="clients">—</strong></div>
        <div><span>Uptime</span><strong id="uptime">—</strong></div>
      </div>
      <p class="muted">Data wordt later gevoed door <code>/api/status</code>. Voor nu: placeholders. Doe alsof.</p>
    </section>
    <section class="card">
      <h2>Bestanden</h2>
      <p>Alles wat je in <code>/var/www/node/files</code> gooit, verschijnt hier. Downloadfeestje.</p>
      <ul id="filelist" class="filelist">
        <li><a href="/files/" rel="nofollow">Open de bestandslijst</a> (autoindex)</li>
      </ul>
    </section>
    <section class="card">
      <h2>Mesh Monitoring</h2>
      <div class="mesh">
        <div class="mesh-node">
          <div class="dot"></div>
          <div class="label">node.local (dit ben jij)</div>
        </div>
        <div class="mesh-links">
          <span class="link dashed"></span>
          <span class="link dashed"></span>
          <span class="link dashed"></span>
        </div>
        <p class="muted">Toekomstmuziek via <code>/api/mesh</code>. Nu vooral decoratie. Mooi hè.</p>
      </div>
    </section>
  </main>
  <footer class="site-footer">
    <small>© <span id="year"></span> Node Portal — Gemaakt voor jouw glorieuze Raspberry Pi AP.</small>
  </footer>
  <script>
    document.getElementById('year').textContent = new Date().getFullYear();
    const demo = { ssid: 'MyPiAP', apip: '192.168.12.1/24', clients: 0, uptime: '—' };
    document.getElementById('ssid').textContent = demo.ssid;
    document.getElementById('apip').textContent = demo.apip;
    document.getElementById('clients').textContent = demo.clients;
    document.getElementById('uptime').textContent = demo.uptime;
  </script>
</body>
</html>
$INDEX_END
$CSS_START
:root{--bg:#0b1020;--card:#121a33;--text:#e9eef8;--muted:#a6b0c3;--accent:#6ea8fe;--line:#243055}
*{box-sizing:border-box}
html,body{margin:0;padding:0;background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,"Helvetica Neue",Arial,"Noto Sans",sans-serif;line-height:1.45}
a{color:var(--accent);text-decoration:none}
a:hover{text-decoration:underline}
.site-header{padding:2rem 1.25rem;border-bottom:1px solid var(--line)}
.site-header h1{margin:0 0 .25rem 0;font-size:1.75rem}
.grid{display:grid;gap:1rem;padding:1.25rem;grid-template-columns:repeat(auto-fit,minmax(280px,1fr))}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:1rem;box-shadow:0 4px 20px rgba(0,0,0,.25)}
.card h2{margin-top:0;font-size:1.2rem}
.keyvals{display:grid;grid-template-columns:1fr 1fr;gap:.5rem 1rem;margin:.5rem 0}
.keyvals div{display:flex;justify-content:space-between;border-bottom:1px dashed var(--line);padding:.25rem 0}
.keyvals span{color:var(--muted)}
.filelist{margin:.5rem 0 0 0;padding:0;list-style:none}
.filelist li{padding:.35rem 0;border-bottom:1px dashed var(--line)}
.mesh{display:flex;flex-direction:column;gap:.75rem}
.mesh-node{display:flex;align-items:center;gap:.5rem}
.mesh .dot{width:12px;height:12px;border-radius:50%;background:var(--accent);box-shadow:0 0 12px var(--accent)}
.mesh .label{font-size:.95rem}
.mesh-links{display:flex;gap:.5rem}
.mesh-links .link{flex:1;height:6px;background:linear-gradient(90deg,var(--line) 50%,transparent 0);background-size:12px 6px}
.mesh-links .dashed{opacity:.7}
.muted{color:var(--muted)}
.site-footer{padding:1rem 1.25rem;border-top:1px solid var(--line);text-align:center;color:var(--muted)}
$CSS_END
