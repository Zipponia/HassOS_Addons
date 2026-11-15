#!/usr/bin/env bash
set -e

CONFIG_PATH=/data/options.json

# --- container environment ---------------------------------------------------
# s6 starts this script with a bare environment (PATH and little else): the
# variables the Supervisor gave the container are only in
# /run/s6/container_environment. Load the ones needed here and by SSH sessions.
export HOME=/root
for v in SUPERVISOR_TOKEN HASSIO_TOKEN TZ; do
  if [ -r "/run/s6/container_environment/${v}" ]; then
    export "${v}=$(cat "/run/s6/container_environment/${v}")"
  fi
done

# --- startup log that survives -------------------------------------------------
# The add-on log is a ring buffer: after a few weeks of uptime the startup
# lines have scrolled out. Everything this script prints, including the later
# messages of its background jobs, is also kept in /data/startup.log (rewritten
# on every start). sshd's own output is not: fds are restored before it starts.
STARTUP_LOG=/data/startup.log
exec 3>&1 4>&2
exec > >(tee "${STARTUP_LOG}") 2>&1
ts() { date '+%F %T'; }
echo "[info] Add-on starting at $(date '+%F %T %Z')."

# Read an option, with a default for when it is missing. Not `.x // default`:
# jq's // also replaces an explicit false, so a switch could never be turned off.
opt() {
  jq -r --arg d "$2" "if .$1 == null then \$d else .$1 end" "${CONFIG_PATH}" 2>/dev/null \
    || echo "$2"
}

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
PRUNE=$(opt prune_old_vscode_servers true)
KEEP=$(opt keep_vscode_servers 2)
PRUNE_HOURS=$(opt prune_interval_hours 12)
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
  # Each CLI build also leaves a .cli.<commit>.log behind, forever. Drop the
  # ones whose build is gone.
  for log in /data/vscode-server/.cli.*.log; do
    [ -e "${log}" ] || continue
    commit=${log##*/.cli.}
    commit=${commit%.log}
    [ -e "/data/vscode-server/code-${commit}" ] && continue
    [ -e "${SERVERS_DIR}/Stable-${commit}" ] && continue
    rm -f "${log}" || true
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

# An interrupted write of ~/.claude.json leaves a .claude.json.tmp.* orphan.
find /data/claude-home -maxdepth 1 -name '.claude.json.tmp.*' -mtime +0 \
  -exec rm -f {} + 2>/dev/null || true

# Tell a new Claude session where it is. No-clobber: once installed the file
# is the user's to edit, and an existing CLAUDE.md is never touched.
if [ ! -e /data/claude-home/CLAUDE.md ]; then
  install -m 0644 /usr/share/vscode-remote/CLAUDE.md /data/claude-home/CLAUDE.md \
    && echo "[info] Installed ~/.claude/CLAUDE.md (environment notes for Claude Code)."
elif ! grep -q 'Home Assistant OS host' /data/claude-home/CLAUDE.md; then
  echo "[info] ~/.claude/CLAUDE.md is yours and was left alone; the add-on's"
  echo "[info] environment notes are in /usr/share/vscode-remote/CLAUDE.md."
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

# --- Claude Code binaries on /data -------------------------------------------
# The native installer keeps each version as one ~300 MB file under
# ~/.local/share/claude/versions, and ~/.local/bin/claude is a symlink to the
# current one. On the overlay an update was lost with the container and
# downloaded again after every rebuild, so the directory lives on /data.
#
# On the first start of a new container the image still has its own copy. Use
# the newest version on /data that actually runs; copy the image's version
# over only when it is newer than that (or nothing on /data works).
CLAUDE_SHARE=/data/claude-share
CLAUDE_BIN=/root/.local/bin/claude
claude_versions() {
  ls -1 "$1" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)+$' | sort -V
}
persist_claude_binaries() {
  mkdir -p "${CLAUDE_SHARE}/versions"
  if [ -L /root/.local/share/claude ]; then
    # Same container as before. Leave a working launcher alone; repair one
    # that points at a version no longer on /data.
    [ -x "$(readlink -f "${CLAUDE_BIN}" 2>/dev/null)" ] && return 0
    echo "[warn] ${CLAUDE_BIN} points at a missing version; relinking."
  fi
  best=""
  for v in $(claude_versions "${CLAUDE_SHARE}/versions" | tac); do
    if timeout 30 "${CLAUDE_SHARE}/versions/${v}" --version >/dev/null 2>&1; then
      best="${v}"
      break
    fi
    echo "[warn] Claude Code ${v} on /data does not run; ignoring it."
  done
  baked=$(claude_versions /root/.local/share/claude/versions | tail -n 1)
  if [ -n "${baked}" ]; then
    newest=$(printf '%s\n%s\n' "${best}" "${baked}" | sort -V | tail -n 1)
    if [ "${newest}" != "${best}" ]; then
      if ! cp -a "/root/.local/share/claude/versions/${baked}" "${CLAUDE_SHARE}/versions/"; then
        rm -f "${CLAUDE_SHARE}/versions/${baked}"
        echo "[warn] Could not copy Claude Code ${baked} to /data; using the image's copy."
        return 0
      fi
      best="${baked}"
    fi
  fi
  if [ -z "${best}" ]; then
    echo "[warn] No usable Claude Code binary found."
    return 0
  fi
  if [ ! -L /root/.local/share/claude ]; then
    rm -rf /root/.local/share/claude
    ln -s "${CLAUDE_SHARE}" /root/.local/share/claude
  fi
  mkdir -p "$(dirname "${CLAUDE_BIN}")"
  ln -sfn "/root/.local/share/claude/versions/${best}" "${CLAUDE_BIN}"
  echo "[info] Claude Code ${best} in use, stored on /data."
}
persist_claude_binaries || echo "[warn] Could not move the Claude Code binaries to /data."

# --- keep Claude Code current -------------------------------------------------
# The CLI's own auto-updater is off, so without this it stays at whatever
# version was current on the last rebuild (it once sat a month behind). Check
# at start and then every update_interval_hours: the container runs for weeks.
# Runs in the background: sshd must never wait on the network.
UPDATE_CLAUDE=$(opt update_claude_code true)
UPDATE_HOURS=$(opt update_interval_hours 24)

prune_claude_versions() {
  [ -L /root/.local/share/claude ] || return 0
  current=$(basename "$(readlink -f "${CLAUDE_BIN}")")
  [ -e "${CLAUDE_SHARE}/versions/${current}" ] || return 0
  for v in $(claude_versions "${CLAUDE_SHARE}/versions"); do
    [ "${v}" = "${current}" ] && continue
    # A running session keeps using the binary it started from.
    if ls -l /proc/[0-9]*/exe 2>/dev/null | grep -qF "claude-share/versions/${v}"; then
      continue
    fi
    echo "[info] $(ts) Removing old Claude Code ${v}."
    rm -rf "${CLAUDE_SHARE}/versions/${v}" || true
  done
}

update_claude() {
  before=$(claude --version 2>/dev/null | cut -d' ' -f1)
  rc=0
  out=$(timeout 600 claude update 2>&1) || rc=$?
  after=$(claude --version 2>/dev/null | cut -d' ' -f1)
  if [ "${rc}" -ne 0 ]; then
    echo "[warn] $(ts) Claude Code update failed (exit ${rc}), still at ${after:-unknown}:" \
      "$(printf '%s\n' "${out}" | grep . | tail -n 1)"
    return 0
  fi
  if [ "${before}" != "${after}" ]; then
    echo "[info] $(ts) Claude Code updated: ${before} -> ${after}."
  else
    echo "[info] $(ts) Claude Code ${after} is up to date."
  fi
  prune_claude_versions
}

if [ "${UPDATE_CLAUDE}" = "true" ]; then
  (
    update_claude || true
    if [ "${UPDATE_HOURS}" -gt 0 ] 2>/dev/null; then
      while true; do
        sleep "$((UPDATE_HOURS * 3600))"
        update_claude || true
      done
    fi
  ) &
fi

# --- extra packages ---------------------------------------------------------
# Tools the image does not ship, installed with apt on every start so they come
# back after a rebuild. In the background, for the same reason as above.
EXTRA_PKGS=()
while IFS= read -r pkg; do
  [ -n "${pkg}" ] || continue
  if ! printf '%s' "${pkg}" | grep -qE '^[a-z0-9][a-z0-9+.-]+$'; then
    echo "[warn] extra_packages: ignoring invalid package name '${pkg}'."
    continue
  fi
  dpkg -s "${pkg}" >/dev/null 2>&1 || EXTRA_PKGS+=("${pkg}")
done < <(jq -r '.extra_packages[]?' "${CONFIG_PATH}" 2>/dev/null || true)
if [ "${#EXTRA_PKGS[@]}" -gt 0 ]; then
  echo "[info] Installing extra packages in the background: ${EXTRA_PKGS[*]}"
  (
    if apt-get update -qq >/tmp/extra-packages.log 2>&1 \
      && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
           "${EXTRA_PKGS[@]}" >>/tmp/extra-packages.log 2>&1; then
      echo "[info] $(ts) Extra packages installed: ${EXTRA_PKGS[*]}"
    else
      echo "[warn] $(ts) Extra packages failed: $(grep . /tmp/extra-packages.log | tail -n 1)"
    fi
    rm -rf /var/lib/apt/lists/* 2>/dev/null || true
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
# ed25519 only: every client that can run VS Code Remote-SSH supports it.
if [ ! -f /data/ssh/ssh_host_ed25519_key ]; then
  echo "[info] Generating ed25519 host key..."
  ssh-keygen -t ed25519 -f /data/ssh/ssh_host_ed25519_key -N "" < /dev/null
fi
if [ -f /data/ssh/ssh_host_rsa_key ]; then
  echo "[info] Removing the unused RSA host key."
  rm -f /data/ssh/ssh_host_rsa_key /data/ssh/ssh_host_rsa_key.pub
fi

# --- sshd config ------------------------------------------------------------
mkdir -p /run/sshd
# The file holds the Supervisor token (SetEnv below), so root-only.
rm -f /etc/ssh/sshd_config
( umask 077; : > /etc/ssh/sshd_config )
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

# sshd starts sessions with a clean environment, so the Supervisor token and
# the timezone never reached a shell, the VS Code server or Claude Code — the
# add-on had API access nobody could use, and `date` printed UTC. SetEnv is
# the one mechanism that also covers non-interactive sessions, which is what
# the VS Code server runs in; /etc/profile.d would not.
SETENV=""
for v in SUPERVISOR_TOKEN HASSIO_TOKEN TZ; do
  val="${!v:-}"
  [ -n "${val}" ] || continue
  if printf '%s' "${val}" | grep -qE '^[A-Za-z0-9_./+:=-]+$'; then
    SETENV="${SETENV} ${v}=${val}"
  else
    echo "[warn] ${v} has unexpected characters; not passed to SSH sessions."
  fi
done
if [ -n "${SETENV}" ]; then
  echo "SetEnv${SETENV}" >> /etc/ssh/sshd_config
  echo "[info] SSH sessions get:$(printf '%s' "${SETENV}" | sed -E 's/=[^ ]*//g')"
else
  echo "[warn] No Supervisor token or TZ found to pass to SSH sessions."
fi
chmod 600 /etc/ssh/sshd_config
# Never let this line be the reason nobody can log in.
if ! /usr/sbin/sshd -t; then
  echo "[warn] sshd rejected the configuration; retrying without SetEnv."
  sed -i '/^SetEnv /d' /etc/ssh/sshd_config
fi

# The Supervisor watchdog opens and closes a TCP connection to port 22 every
# two minutes, and sshd logs two lines per probe — over 99.9% of the add-on
# log. A `Match Address` block cannot silence them: sshd applies Match only
# once a user name is known, and the probe hangs up before that. So drop
# exactly those two lines on the way out. A failed handshake from any other
# address still shows its "Connection closed by <address>" line.
SSHD_NOISE='^(kex_exchange_identification: (read: )?Connection (closed|reset) by (remote host|peer)|Connection (closed|reset) by 172\.30\.32\.2 port [0-9]+)'

echo "[info] Starting sshd (container :22 -> host :22)..."
exec 1>&3 2>&4 3>&- 4>&-
exec /usr/sbin/sshd -D -e 2> >(grep --line-buffered -v -E "${SSHD_NOISE}" >&2)
