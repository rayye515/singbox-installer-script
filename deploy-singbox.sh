#!/bin/bash

# ======== GET DOMAIN AND SNI ========
read -p "Enter your domain (e.g. my.example.com): " DOMAIN
while [ -z "$DOMAIN" ]; do
    echo "Domain cannot be empty!"
    read -p "Enter your domain (e.g. my.example.com): " DOMAIN
done

read -p "Enter SNI/Server Name (default: www.cloudflare.com): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-www.cloudflare.com}

read -p "Enter Port [default: 443]: " PORT
PORT=${PORT:-443}

# ======== INSTALL DEPENDENCIES ========
apt update && apt install -y wget unzip curl jq

# ======== DOWNLOAD & INSTALL SING-BOX ========
cd /root
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
wget https://github.com/SagerNet/sing-box/releases/download/$LATEST/sing-box-${LATEST#v}-linux-amd64.tar.gz
tar -xzf sing-box-*-linux-amd64.tar.gz
mv sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# ======== AUTO-GENERATE VLESS INFO ========
echo "Generating private/public key and short ID..."
REALITY_KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$REALITY_KEYS" | grep 'Private Key' | awk '{print $3}')
PUBLIC_KEY=$(echo "$REALITY_KEYS" | grep 'Public Key' | awk '{print $3}')
UUID=$(cat /proc/sys/kernel/random/uuid)
SHORT_ID=$(head /dev/urandom | tr -dc a-f0-9 | head -c 8)

# ======== CREATE CONFIG ========
mkdir -p /etc/sing-box
cat <<EOF > /etc/sing-box/config.json
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SERVER_NAME",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$SERVER_NAME",
            "server_port": $PORT
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

# ======== CREATE SYSTEMD SERVICE ========
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

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# ======== GENERATE VLESS LINK ========
VLESS_LINK="vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SERVER_NAME&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp#Singbox-Reality-$DOMAIN"

# ======== FINAL INFO ========
echo "============================================"
echo "✅ Sing-box installed and running at $DOMAIN:$PORT"
echo "----------- Connection Info ---------------"
echo "  Domain: $DOMAIN"
echo "  Port: $PORT"
echo "  UUID: $UUID"
echo "  Public Key: $PUBLIC_KEY"
echo "  Short ID: $SHORT_ID"
echo "  SNI: $SERVER_NAME"
echo
echo "----------- VLESS Import Link -------------"
echo "$VLESS_LINK"
echo "--------------------------------------------"
echo "⚠️  Copy & import this link into v2rayN, NekoBox, Shadowrocket (with tweaks), or other Reality-compatible clients!"
echo "============================================"

