#!/bin/bash
set -e

# ========== Sing-box Reality Automated Installer ==========

echo "=============================="
echo "      Sing-box Reality Installer"
echo "=============================="

# 1. Get user input
read -rp "Enter your domain (e.g., mydomain.com): " DOMAIN
read -rp "Enter SNI (default: www.cloudflare.com): " SNI
SNI=${SNI:-www.cloudflare.com}
read -rp "Enter short ID (8 hex chars, default: $(openssl rand -hex 4)): " SHORT_ID
SHORT_ID=${SHORT_ID:-$(openssl rand -hex 4)}
read -rp "Enter UUID (default: auto-generate): " UUID
UUID=${UUID:-$(cat /proc/sys/kernel/random/uuid)}
PORT=443
FINGERPRINT="chrome"

# 2. Install dependencies
echo "[*] Installing dependencies..."
apt update -y && apt install -y wget unzip curl jq

# 3. Download and install sing-box
echo "[*] Downloading sing-box..."
cd /root
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name)
wget -q "https://github.com/SagerNet/sing-box/releases/download/${LATEST}/sing-box-${LATEST#v}-linux-amd64.tar.gz"
tar -xzf sing-box-*-linux-amd64.tar.gz
mv sing-box-*/sing-box /usr/local/bin/
chmod +x /usr/local/bin/sing-box

if ! command -v sing-box >/dev/null 2>&1; then
    echo "❌ Error: sing-box is not installed or not in PATH."
    exit 1
fi

# 4. Generate Reality key pair with error checking
echo "[*] Generating Reality keypair..."
KEYPAIR_OUTPUT=$(/usr/local/bin/sing-box generate reality-keypair 2>/dev/null)
if [[ $? -ne 0 || -z "$KEYPAIR_OUTPUT" ]]; then
    echo "❌ Error: sing-box key pair generation failed."
    exit 1
fi

PRIVATE_KEY=$(echo "$KEYPAIR_OUTPUT" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYPAIR_OUTPUT" | grep 'PublicKey' | awk '{print $2}')

if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    echo "❌ Error: Could not extract keys from sing-box output:"
    echo "$KEYPAIR_OUTPUT"
    exit 1
fi

# 5. Write config
echo "[*] Writing sing-box configuration..."
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

# 6. Create systemd service
echo "[*] Setting up systemd service..."
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

# 7. Print all info and ready-to-import VLESS link
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

exit 0

