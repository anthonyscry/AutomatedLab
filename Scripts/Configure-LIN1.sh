#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi

# Pick the first non-lo interface (installer often shows eth0, but this is safer)
IFACE=$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')
if [ -z "$IFACE" ]; then IFACE="eth0"; fi

LIN_USER="__LIN_USER__"
LIN_HOME="__LIN_HOME__"
DOMAIN="__DOMAIN__"
NETBIOS="__NETBIOS__"
SHARE="__SHARE__"
PASS='__PASS__'
GATEWAY="__GATEWAY__"
DNS="__DNS__"
STATIC_IP="__STATIC_IP__"
HOST_PUBKEY_FILE="__HOST_PUBKEY__"

echo "[LIN1] Updating packages..."
$SUDO apt-get update -qq

echo "[LIN1] Installing base tools + OpenSSH..."
$SUDO apt-get install -y -qq \
  openssh-server git curl wget jq cifs-utils net-tools build-essential python3 python3-pip \
  nodejs npm 2>/dev/null || true

$SUDO systemctl enable --now ssh || true

# Ensure SSH allows password auth (optional; helps if you ever need it)
$SUDO tee /etc/ssh/sshd_config.d/99-opencodelab.conf >/dev/null <<'SSHEOF'
PasswordAuthentication yes
PubkeyAuthentication yes
SSHEOF
$SUDO systemctl restart ssh || true

echo "[LIN1] Setting up SSH authorized_keys for ${LIN_USER}..."
mkdir -p "$LIN_HOME/.ssh"
chmod 700 "$LIN_HOME/.ssh"
touch "$LIN_HOME/.ssh/authorized_keys"
chmod 600 "$LIN_HOME/.ssh/authorized_keys"

if [ -f "/tmp/$HOST_PUBKEY_FILE" ]; then
  cat "/tmp/$HOST_PUBKEY_FILE" >> "$LIN_HOME/.ssh/authorized_keys" || true
fi

chown -R "${LIN_USER}:${LIN_USER}" "$LIN_HOME/.ssh"

echo "[LIN1] Generating local SSH keypair (LIN1->DC1)..."
sudo -u "$LIN_USER" bash -lc 'test -f ~/.ssh/id_ed25519 || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "LIN1-to-DC1"'

echo "[LIN1] Configuring SMB mount..."
$SUDO mkdir -p /mnt/labshare
CREDS_FILE="/etc/opencodelab-labshare.cred"
if [ ! -f "$CREDS_FILE" ]; then
  $SUDO tee "$CREDS_FILE" >/dev/null <<CREDEOF
username=$LIN_USER
password=$PASS
domain=$NETBIOS
CREDEOF
  $SUDO chmod 600 "$CREDS_FILE"
fi
FSTAB_ENTRY="//DC1.$DOMAIN/$SHARE /mnt/labshare cifs credentials=$CREDS_FILE,iocharset=utf8,_netdev 0 0"
if ! grep -qF "DC1.$DOMAIN/$SHARE" /etc/fstab 2>/dev/null; then
  echo "$FSTAB_ENTRY" | $SUDO tee -a /etc/fstab >/dev/null
fi
$SUDO mount -a 2>/dev/null || true

echo "[LIN1] Pinning static IP ($STATIC_IP) for stable SSH..."
$SUDO tee /etc/netplan/99-opencodelab-static.yaml >/dev/null <<NETEOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      addresses: [$STATIC_IP/24]
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$DNS, 1.1.1.1]
NETEOF

# Apply netplan in the background so we don't hang the remote session mid-flight
(sleep 2; $SUDO netplan apply) >/dev/null 2>&1 &

echo "[LIN1] Done."
