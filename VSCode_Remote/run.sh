#!/usr/bin/env bash
set -e

CONFIG_PATH=/data/options.json

# --- authorized_keys from add-on options -----------------------------------
mkdir -p /root/.ssh
chmod 700 /root/.ssh
: > /root/.ssh/authorized_keys
if [ -f "${CONFIG_PATH}" ]; then
  jq -r '.authorized_keys[]?' "${CONFIG_PATH}" >> /root/.ssh/authorized_keys || true
fi
chmod 600 /root/.ssh/authorized_keys

KEYCOUNT=$(grep -c . /root/.ssh/authorized_keys || true)
echo "[info] Loaded ${KEYCOUNT} authorized key(s)."

# --- persistent VS Code Server (survives restarts/updates) -----------------
# VS Code downloads its server into ~/.vscode-server. Keeping it on /data
# means it is not re-downloaded on every add-on restart and reconnects fast
# (also works offline after the first connection).
mkdir -p /data/vscode-server
if [ ! -L /root/.vscode-server ]; then
  rm -rf /root/.vscode-server
  ln -s /data/vscode-server /root/.vscode-server
fi

# --- persistent host keys (survive restarts) -------------------------------
mkdir -p /data/ssh
for t in rsa ed25519; do
  if [ ! -f "/data/ssh/ssh_host_${t}_key" ]; then
    echo "[info] Generating ${t} host key..."
    ssh-keygen -t "${t}" -f "/data/ssh/ssh_host_${t}_key" -N "" < /dev/null
  fi
done

# --- sshd config ------------------------------------------------------------
mkdir -p /run/sshd
cat > /etc/ssh/sshd_config <<EOF
Port 22
AddressFamily any
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PrintMotd no
PrintLastLog no
HostKey /data/ssh/ssh_host_rsa_key
HostKey /data/ssh/ssh_host_ed25519_key
Subsystem sftp internal-sftp
AcceptEnv LANG LC_*
ClientAliveInterval 60
ClientAliveCountMax 3
# VS Code Remote-SSH features: port forwarding, agent forwarding, and
# many concurrent channels/sessions.
AllowTcpForwarding yes
AllowStreamLocalForwarding yes
AllowAgentForwarding yes
StreamLocalBindUnlink yes
PermitTunnel no
X11Forwarding no
MaxSessions 30
EOF

echo "[info] Starting sshd (container :22 -> host :22)..."
exec /usr/sbin/sshd -D -e
