How to Install:

wget https://raw.githubusercontent.com/rayye515/singbox-installer-script/main/deploy-singbox.sh

chmod +x deploy-singbox.sh

dos2unix deploy-singbox.sh 

./deploy-singbox.sh




How to Re-install:

1. Stop the running sing-box service:

systemctl stop sing-box

3. Remove (optional, but for clean start):

rm -rf /etc/sing-box/

rm -f /usr/local/bin/sing-box





