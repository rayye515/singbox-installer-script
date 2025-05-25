#!/bin/bash

# Sing-box Reality Installer Script (auto keygen, VLESS link, interactive domain/uuid)
# Compatible: Ubuntu/Debian

# ==========================
# STEP 1: User Input
# ==========================
read -rp "Enter your domain (e.g., mydomain.com): " DOMAIN
read -rp "Enter SNI (default: www.cloudflare.com): " SNI
SNI=${SNI:-www.cloudflare.com}
read -rp "Enter short ID (8 hex chars, default: $(openssl rand -hex 4)): " SHORT_ID
SHORT_ID=${SHORT_ID:-$(openssl rand -hex 4)}
read -rp "Enter UUID (default: auto-generate): " UUID
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PORT=443
FINGERPRINT="chrome"

# ==========================
# STEP 2: Dependencies
# ==========================
apt update && apt install -y wget unzip curl jq

# ==========================
# STEP 3: Download Sing-box
# ==========================
cd /root
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
wget -q https://github.com/SagerNet/sing-box/releases/download/$LATEST/sing-box-${LATEST#v}-linux-amd64.tar.gz
tar -xzf sing-box-*-linux-amd64.tar.gz
mv sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# ==========================
# STEP 4: Generate Reality Key Pair
# ==========================
KEYPAIR_JSON=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYPAIR_JSON" | grep private_key | awk -F'"' '{print $4}')
PUBLIC_KEY=$(echo "$KEYPAIR_JSON" | grep public_key | awk -F'"' '{print $4}')

# ==========================
# STEP 5: Create Config
# ==========================
mkdir -p /etc/sing-box
cat <<EOF > /etc/sing-box/config.json
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        { "uuid": "$UUID", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": { "server": "$SNI", "server_port": $PORT },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [{ "type": "direct" }]
}
EOF

# ==========================
# STEP 6: Systemd Service
# ==========================
cat <<EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# ==========================
# STEP 7: Output Connection Info
# ==========================
echo "============================================"
echo "✅ Sing-box installed and running at $DOMAIN:$PORT"
echo "----------- Connection Info ---------------"
echo "  Domain: $DOMAIN"
echo "  Port: $PORT"
echo "  UUID: $UUID"
echo "  Public Key: $PUBLIC_KEY"
echo "  Short ID: $SHORT_ID"
echo "  SNI: $SNI"
echo
echo "----------- VLESS Import Link -------------"
echo "vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=$FINGERPRINT&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Singbox-Reality-$DOMAIN"
echo "--------------------------------------------"
echo "⚠️  Copy & import this link into v2rayN, NekoBox, Shadowrocket (with tweaks), or other Reality-compatible clients!"
echo "============================================"
