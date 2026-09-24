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
if [ "${KEYCOUNT}" -eq 0 ]; then
  echo "[warn] No authorized_keys configured. Password login is disabled, so"
  echo "[warn] nobody can log in. Add your SSH public key in the add-on options."
fi

# --- persistent VS Code Server (survives restarts/updates) -----------------
# VS Code downloads its server into ~/.vscode-server. Keeping it on /data
# means it is not re-downloaded on every add-on restart and reconnects fast
# (also works offline after the first connection).
mkdir -p /data/vscode-server
if [ ! -L /root/.vscode-server ]; then
  rm -rf /root/.vscode-server
  ln -s /data/vscode-server /root/.vscode-server
fi

# VS Code keeps every server build it ever downloaded (~500 MB each), so /data
# grows without bound. Pruning only at startup is not enough: this container
# runs for weeks, and VS Code downloads a new build every time the desktop app
# updates. So prune now and then periodically, skipping any build that has a
# running server process so an active session is never broken.
PRUNE=$(jq -r '.prune_old_vscode_servers // true' "${CONFIG_PATH}" 2>/dev/null || echo true)
KEEP=$(jq -r '.keep_vscode_servers // 2' "${CONFIG_PATH}" 2>/dev/null || echo 2)
PRUNE_HOURS=$(jq -r '.prune_interval_hours // 12' "${CONFIG_PATH}" 2>/dev/null || echo 12)
SERVERS_DIR=/data/vscode-server/cli/servers

prune_vscode_servers() {
  [ "${PRUNE}" = "true" ] || return 0
  [ -d "${SERVERS_DIR}" ] || return 0
  # Newest first by mtime; consider everything past the first ${KEEP} entries.
  ls -1dt "${SERVERS_DIR}"/Stable-* 2>/dev/null | tail -n "+$((KEEP + 1))" | while read -r old; do
    name=$(basename "${old}")
    if pgrep -f "servers/${name}" >/dev/null 2>&1; then
      echo "[info] Keeping ${name}: still in use by a running server."
      continue
    fi
    echo "[info] Pruning old VS Code server: ${name}"
    rm -rf "${old}" || true
  done
  # The Remote-SSH CLI (~/.vscode-server/code-<commit>, ~32 MB each) updates on
  # its own schedule and its commits do not match the server builds, so keep
  # just the newest one plus any that is still running.
  ls -1t /data/vscode-server/code-* 2>/dev/null | tail -n +2 | while read -r old; do
    if pgrep -f "${old}" >/dev/null 2>&1; then
      continue
    fi
    echo "[info] Pruning old VS Code CLI: $(basename "${old}")"
    rm -f "${old}" || true
  done
  return 0
}

prune_vscode_servers
if [ "${PRUNE}" = "true" ] && [ "${PRUNE_HOURS}" -gt 0 ] 2>/dev/null; then
  echo "[info] Periodic VS Code server pruning every ${PRUNE_HOURS}h (keeping ${KEEP})."
  (
    while true; do
      sleep "$((PRUNE_HOURS * 3600))"
      prune_vscode_servers || true
    done
  ) &
fi

# --- persistent Claude Code home (auth + chat history, survives restarts/updates) ---
# The `claude` CLI stores auth, chat history and memory under ~/.claude, plus MCP
# config, trust settings and the project list in ~/.claude.json. Keep both on
# /data so they survive restarts and add-on upgrades. On the first run where the
# real paths still exist, migrate their contents instead of deleting them.
# The copies are no-clobber (-n) on purpose: whatever is already on /data is
# the real, persisted state, and must win over anything the image happens to
# ship at the same path.
mkdir -p /data/claude-home
if [ ! -L /root/.claude ]; then
  if [ -d /root/.claude ]; then
    cp -an /root/.claude/. /data/claude-home/ 2>/dev/null || true
    rm -rf /root/.claude
  fi
  ln -s /data/claude-home /root/.claude
fi

if [ ! -L /root/.claude.json ]; then
  if [ -f /root/.claude.json ]; then
    cp -an /root/.claude.json /data/claude-home/.claude.json 2>/dev/null || true
    rm -f /root/.claude.json
  fi
  ln -s /data/claude-home/.claude.json /root/.claude.json
fi

# --- Claude Code permissions (managed by the add-on) -----------------------
# This container runs as root, and Claude Code refuses to bypass permission
# checks for root ("--dangerously-skip-permissions cannot be used with
# root/sudo privileges"). So `defaultMode: bypassPermissions` is silently
# ignored and every single command ends up prompting, while `dontAsk` hands
# the decision to an automatic classifier that denies legitimate work. Plain
# allow/ask rules are unaffected by any of that, so those are what we install:
# everything runs unprompted, deletions still ask. Existing keys are merged,
# not replaced, so anything else the user configured survives.
mkdir -p /data/claude-home/hooks
install -m 0755 /usr/share/vscode-remote/deletion-guard.sh \
  /data/claude-home/hooks/deletion-guard.sh 2>/dev/null \
  || echo "[warn] Could not install the deletion-guard hook."

CLAUDE_SETTINGS=/data/claude-home/settings.json
[ -s "${CLAUDE_SETTINGS}" ] || echo '{}' > "${CLAUDE_SETTINGS}"

if jq -e . "${CLAUDE_SETTINGS}" >/dev/null 2>&1; then
  jq --arg hook 'bash ~/.claude/hooks/deletion-guard.sh' '
    ["Bash(*)","Read","Edit","Write","Glob","Grep","WebFetch","WebSearch",
     "TodoWrite","NotebookEdit","Task","Agent"] as $allow
    | ["Bash(rm *)","Bash(rmdir *)","Bash(shred *)","Bash(unlink *)",
       "Bash(docker rm *)","Bash(docker rmi *)","Bash(docker volume rm *)",
       "Bash(git clean *)","Bash(find * -delete*)"] as $ask
    | .permissions //= {}
    | .permissions.allow = ((.permissions.allow // []) + $allow | unique)
    | .permissions.ask   = ((.permissions.ask   // []) + $ask   | unique)
    | if (.permissions.defaultMode == "bypassPermissions"
          or .permissions.defaultMode == "dontAsk")
      then del(.permissions.defaultMode) else . end
    | .hooks //= {}
    | .hooks.PreToolUse //= []
    | if ([.hooks.PreToolUse[]?.hooks[]?.command] | index($hook))
      then .
      else .hooks.PreToolUse += [{matcher:"Bash",
             hooks:[{type:"command",command:$hook}]}]
      end
  ' "${CLAUDE_SETTINGS}" > "${CLAUDE_SETTINGS}.tmp" \
    && mv "${CLAUDE_SETTINGS}.tmp" "${CLAUDE_SETTINGS}" \
    && echo "[info] Claude Code permissions set: runs unprompted, deletions ask."
else
  echo "[warn] ${CLAUDE_SETTINGS} is not valid JSON; leaving it untouched."
fi

# --- keep Claude Code current -------------------------------------------------
# The CLI is baked into the image and its own auto-updater is off, so without
# this it stays at whatever version was current on the last rebuild (it once
# sat a month behind). An update lands on the overlay and is lost with the
# container, so check on every start. Runs in the background: sshd must never
# wait on the network.
UPDATE_CLAUDE=$(jq -r '.update_claude_code // true' "${CONFIG_PATH}" 2>/dev/null || echo true)
if [ "${UPDATE_CLAUDE}" = "true" ]; then
  (
    before=$(claude --version 2>/dev/null | cut -d' ' -f1)
    timeout 300 claude update >/dev/null 2>&1 || true
    after=$(claude --version 2>/dev/null | cut -d' ' -f1)
    if [ "${before}" != "${after}" ]; then
      echo "[info] Claude Code updated: ${before} -> ${after}."
    else
      echo "[info] Claude Code ${after} is up to date (or the update check failed)."
    fi
  ) &
fi

# --- persistent shell and git state ----------------------------------------
# Command history, git identity and known_hosts also live on the ephemeral
# overlay, so a rebuild silently resets them. Same treatment as the rest.
mkdir -p /data/dotfiles /data/ssh
link_dotfile() {
  target="$1"   # path under /root
  store="$2"    # path under /data
  [ -L "${target}" ] && return 0
  if [ -f "${target}" ]; then
    cp -an "${target}" "${store}" 2>/dev/null || true
    rm -f "${target}"
  fi
  [ -e "${store}" ] || : > "${store}"
  ln -s "${store}" "${target}"
}
link_dotfile /root/.bash_history    /data/dotfiles/.bash_history
link_dotfile /root/.gitconfig       /data/dotfiles/.gitconfig
link_dotfile /root/.ssh/known_hosts /data/ssh/known_hosts

# --- convenience symlinks in root's home -----------------------------------
# VS Code Remote-SSH opens the user's home (/root) by default. Linking the
# mapped Home Assistant folders here makes them show up in the Explorer right
# after connecting, without changing $HOME.
for d in homeassistant addons ssl share media backup; do
  if [ -d "/${d}" ]; then
    ln -sfn "/${d}" "/root/${d}"
  fi
done

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
TCPKeepAlive yes
# Remote-SSH opens several connections at once and retries after network blips;
# the default MaxStartups (10) starts refusing them on a flaky link.
MaxStartups 30:50:100
LoginGraceTime 120
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
