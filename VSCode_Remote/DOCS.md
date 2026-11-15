# VS Code Remote SSH (Debian)

Run an OpenSSH server on Home Assistant OS so the **VS Code desktop app** can
attach to it with **Remote-SSH** and edit your Home Assistant configuration with
the full editor: extensions, IntelliSense, integrated terminal, source control.

## Why Debian and not Alpine

The VS Code Server ships a bundled Node binary linked against **glibc**. The
Alpine-based SSH add-ons use **musl**, so Remote-SSH breaks on recent VS Code
versions (`gcompat` / `fcntl64` errors). This add-on uses a Debian base image,
where that binary runs natively.

## Installation

1. Add this repository to Home Assistant:
   **Settings → Add-ons → Add-on Store → ⋮ → Repositories**, then paste
   `https://github.com/Zipponia/HassOS_Addons`.
2. Install **VS Code Remote SSH (Debian)**.
3. Put your SSH **public** key in the `authorized_keys` option (see below).
4. Start the add-on.

## Configuration

```yaml
authorized_keys:
  - "ssh-ed25519 AAAAC3Nz... you@your-mac"
prune_old_vscode_servers: true
keep_vscode_servers: 2
prune_interval_hours: 12
update_claude_code: true
update_interval_hours: 24
extra_packages: []
```

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `authorized_keys` | list of strings | `[]` | SSH **public** keys allowed to connect. Password login is disabled, so at least one key is required. |
| `prune_old_vscode_servers` | bool | `true` | Delete old VS Code Server builds. VS Code keeps every build it downloads (~500 MB each), which otherwise fills `/data`. |
| `keep_vscode_servers` | int (1–10) | `2` | How many of the most recent server builds to keep when pruning. |
| `prune_interval_hours` | int (0–168) | `12` | Prune again every N hours while the add-on runs. `0` prunes at startup only. |
| `update_claude_code` | bool | `true` | Keep the Claude Code CLI current (see below). |
| `update_interval_hours` | int (0–168) | `24` | Check for a Claude Code update every N hours while the add-on runs. `0` checks at startup only. |
| `extra_packages` | list of strings | `[]` | Debian packages to `apt install` on every start, in the background. For a tool the image does not ship, without waiting for a new image. |

Pruning runs at add-on start and then every `prune_interval_hours`, because the
container runs for weeks while VS Code downloads a new build on every desktop
update. A build with a running server process is always skipped, so an active
session is never broken. Old copies of the Remote-SSH CLI
(`~/.vscode-server/code-<commit>`, ~32 MB each) are pruned too, keeping the
newest one, together with the `.cli.<commit>.log` file each of them leaves
behind. If VS Code needs a pruned build again, it simply re-downloads it.

## Connecting

The add-on listens on **host port 22**. On your machine:

```
ssh -p 22 root@<home-assistant-ip>
```

Or in `~/.ssh/config`:

```
Host homeassistant
    HostName <home-assistant-ip>
    User root
    Port 22
```

Then in VS Code: **Remote-SSH: Connect to Host…** → `homeassistant`.

> If you also run the *Advanced SSH & Web Terminal* add-on on port 22, change
> the host port of one of the two to avoid a conflict.

### What you will see

VS Code opens root's home (`/root`), where the add-on creates symlinks to every
mapped folder. Open **`/homeassistant`** to edit your configuration
(`configuration.yaml`, `automations.yaml`, …). VS Code remembers the folder and
reopens it on the next connection.

| Path | Contents |
| ---- | -------- |
| `/homeassistant` | Home Assistant configuration |
| `/addons` | Local add-ons |
| `/addon_configs` | Every add-on's config directory |
| `/ssl` | Certificates |
| `/share`, `/media`, `/backup` | Shared files, media, backups |

⚠️ Do not hand-edit `/homeassistant/.storage` — Home Assistant owns those files
and editing them can corrupt its state. Validate YAML with
**Settings → System → Check configuration** before restarting.

## Home Assistant API from the shell

Every SSH session — a terminal, the VS Code server, Claude Code — has
`SUPERVISOR_TOKEN` set and runs in Home Assistant's timezone. No long-lived
token and no LAN address are needed:

```
curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons/self/info
curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/core/api/config
ha core info
```

| What | Where |
| ---- | ----- |
| Supervisor API | `http://supervisor/…` |
| Home Assistant REST API | `http://supervisor/core/api/…` |
| Home Assistant websocket | `ws://supervisor/core/websocket` |

The token is written into `/etc/ssh/sshd_config` (`SetEnv`), which is readable
by root only. It is the add-on's own token, valid while the add-on is installed.

## Included tools

`git`, `jq`, `curl`, the `docker` CLI, the `ha` CLI, `python3` (with `pip`,
`venv`, and the `websockets`, `aiohttp` and `yaml` modules), `sqlite3`,
`yamllint`, `rsync`, `unzip`, `less`, and for the network `ping`, `nc`, `dig`
and `ip`.

Python is there mainly because several Home Assistant operations exist only on
the websocket API — Lovelace dashboards, the entity and device registries.
Debian marks the system Python as externally managed, so for other modules
create a venv under `/data` rather than `pip install` system-wide.

For anything else, list the Debian package in `extra_packages`. It is installed
in the background on every start, so it is back a minute or so after a rebuild.

## What persists

The container filesystem is ephemeral: everything outside `/data` is lost on
restart or rebuild. These are symlinked onto `/data`, so they survive:

| Path in container | Stored at |
| ----------------- | --------- |
| `~/.vscode-server` | `/data/vscode-server` |
| `~/.claude` | `/data/claude-home` |
| `~/.claude.json` | `/data/claude-home/.claude.json` |
| `~/.local/share/claude` (Claude Code binaries) | `/data/claude-share` |
| `~/.bash_history`, `~/.gitconfig` | `/data/dotfiles` |
| SSH host keys, `~/.ssh/known_hosts` | `/data/ssh` |

Persisting the host keys means your SSH client never warns about a changed host
key after an add-on restart.

Migrations copy with `-n` (no-clobber): whatever is already on `/data` is the
real state and always wins over a file the image ships at the same path.

**Programs are not persisted, and should not be.** Anything you install by hand
in a shell (`apt install`, `npm -g`, a downloaded binary) lands on the container
overlay and is erased by the next rebuild — only `/data` survives. That is why
the Claude Code CLI is installed in the Dockerfile rather than by hand: its
configuration lives on `/data`, but the binary belongs in the image. Install
long-lived tooling the same way, by adding it to the Dockerfile — or, for a
plain Debian package, to the `extra_packages` option.

## Backups

🔴 **An add-on backup contains credentials in plain text**: the Claude Code
login (`claude-home/.credentials.json`), anything you keep under
`claude-home/` (tokens, passwords in your own files), and the SSH host key.
Protect backups that include this add-on with a password, and treat a copy
stored off the machine accordingly.

What can be downloaded again is left out of the backup: VS Code Server builds,
the Remote-SSH CLI, VS Code extensions, logs and the Claude Code binaries —
about 2.5 GB that used to make every backup over 1 GB. After restoring on a
fresh system, VS Code downloads its server on the first connection; **remote
extensions have to be installed again** (or list them in
`remote.SSH.defaultExtensions` on your machine so that happens by itself).
Settings, Claude Code history and configuration, shell history and keys are in
the backup.

## Full-system access

The add-on requests `hassio_api` (role `admin`), `homeassistant_api`,
`docker_api`, `full_access` and extra capabilities, plus `all_addon_configs:rw`.
Together these let a shell in the container manage Home Assistant, the
Supervisor and **every Docker container** on the host.

🔴 These take effect only with **Protection mode turned off** in the add-on's
*Info* tab, followed by a **Stop/Start** — toggling protection alone does not
recreate the container. With protection off, anything running in this container
effectively has root over your whole Home Assistant system. That is the intended
trade-off for a development add-on; disable the extra privileges if you do not
need them.

The add-on keeps the privileges it has always had. What each one is for:

| Setting | What it gives |
| ------- | ------------- |
| `hassio_api`, `hassio_role: admin`, `homeassistant_api` | The Supervisor and Home Assistant APIs through `SUPERVISOR_TOKEN`. |
| `docker_api` | The Docker socket: `docker ps` / `logs` / `exec` on every container. |
| `full_access` | Host devices (`/dev`), for example to inspect a Zigbee stick or a disk. |
| `NET_ADMIN`, `NET_RAW` | Network diagnosis: `ip`, `ping`, packet capture. |
| `SYS_ADMIN`, `SYS_RAWIO`, `DAC_READ_SEARCH` | Mounting and reading host filesystems and raw devices. |
| `SYS_PTRACE` | Attaching to processes (`strace`, debuggers). |
| `apparmor: false` | No AppArmor profile, so none of the above is filtered. |

The Docker socket alone is already equivalent to root on the host, so the rest
adds convenience rather than exposure. If you never touch raw devices from this
shell, `full_access` and the capability list can be removed from `config.yaml`
in a fork without losing the API or Docker access.

## Keeping Claude Code current

The CLI is installed in the image, and its own auto-updater is off, so on its
own it would stay at the version current on the last rebuild. With
`update_claude_code` enabled (the default), the add-on runs `claude update` in
the background at start and then every `update_interval_hours` (default 24),
because the container runs for weeks. SSH is never delayed by it.

The binaries (about 300 MB per version) live on `/data/claude-share`, so an
update survives a rebuild instead of being downloaded again. After a successful
update the older versions are deleted, except one a running session still
uses. The log says which of three things happened — updated, already up to
date, or failed with the exit code and the last line of the error.

## Claude Code permissions

The Claude Code CLI ships with the add-on, and the add-on configures its
permissions on every start: **it runs without prompting, except for commands
that delete things, which still ask for confirmation.**

Two pieces make that work:

| Piece | Where |
| ----- | ----- |
| `allow` / `ask` rules | `~/.claude/settings.json` |
| Deletion guard hook | `~/.claude/hooks/deletion-guard.sh` |

Your own settings are **merged, not replaced** — custom rules, `model`, themes
and anything else you set are preserved. If `settings.json` is not valid JSON
the add-on leaves it alone and logs a warning (Claude Code silently ignores a
file it cannot parse, so overwriting it would hide the real problem).

The guard asks before:

| Kind | Commands |
| ---- | -------- |
| Removal | `rm`, `rmdir`, `shred`, `unlink`, `truncate`, `docker rm` / `rmi` / `volume rm` / `prune`, `docker compose rm` / `down -v`, `apt remove` / `purge`, `git clean`, `mkfs`, `dd of=`, `mv … /dev/null`, `--delete` flags |
| Removal run elsewhere | any of the removal verbs after `docker exec …` or `ssh …` |
| Overwrites | `> file` and `: > file` with no command, `cp /dev/null file`, `git reset --hard`, `git checkout .`, `git restore .` |
| Home Assistant | `ha … uninstall` / `remove` / `restore` / `reboot` / `shutdown`, `docker stop` / `kill` of `homeassistant` or a `hassio_*` container, `-X DELETE` requests, and POSTs to the Supervisor's `…/uninstall`, `/host/reboot`, `/host/shutdown` and `/backups/…/restore` |

It matches at command position, so a harmless `grep rm file` is not flagged.
The usual ways around it are covered too: leading spaces, `/bin/rm`, `\rm`,
wrappers (`sudo`, `command`, `env`, `timeout`, `nohup`, `time`, `nice`,
`ionice`), `xargs rm`, `find -exec rm`, `sh -c "…"` / `bash -c "…"` / `eval`,
and commands inside `( )`, `{ }`, `$( )`, backticks or `if` / `for` bodies. The
body of a heredoc is treated as text — a commit message with a line starting
`rm` does not prompt — unless the heredoc is fed to a shell, `ssh` or `docker`.
Edit the `patterns` array in the hook to change what is covered.

⚠️ **The guard is a second net, not the only one.** It reads the text of the
command, so it cannot see a deletion done by a script, by `python -c`, or
assembled from variables. Keep backups and version control as the first net.

### Environment notes for Claude

On the first start the add-on installs `~/.claude/CLAUDE.md`, which tells every
Claude Code session where it is: the folder layout, the Supervisor and Home
Assistant API addresses, the rule about `.storage`, the available tools. It is
installed once and never overwritten, so edit it as you like. If you already
had a `CLAUDE.md` there, yours is kept and the add-on's text stays at
`/usr/share/vscode-remote/CLAUDE.md` for you to copy from.

### Why not `bypassPermissions`

Because it cannot work here. The container runs as root, and Claude Code
refuses to bypass permission checks for root:

```
--dangerously-skip-permissions cannot be used with root/sudo privileges
```

`--allow-dangerously-skip-permissions` does not override that guard. Setting
`permissions.defaultMode: "bypassPermissions"` is therefore ignored, and the
session falls back to prompting for **everything** — which looks like the
setting was never read. `dontAsk` is not a substitute either: it hands each
decision to an automatic classifier, which denies legitimate work such as POSTs
to the Home Assistant API.

Plain `allow`/`ask` rules are unaffected by the root guard, so those are what
the add-on installs. It also strips a `defaultMode` of `bypassPermissions` or
`dontAsk` if it finds one; other modes, such as `acceptEdits`, are left alone.

## Troubleshooting

**The add-on starts but I cannot log in.**
Check the log for `No authorized_keys configured`. Password authentication is
disabled by design; add your public key to the options and restart.

**The log has scrolled past the startup messages.**
They are kept in `/data/startup.log`, rewritten on every start, together with
the later messages from pruning and Claude Code updates. The add-on log itself
no longer fills up with the Supervisor watchdog's probes of port 22 (two lines
every two minutes); those are filtered out, real logins and failures are not.

**`docker ps` says `/var/run/docker.sock: no such file or directory`.**
Protection mode is still on. Turn it off in *Info*, then Stop and Start the
add-on. A plain restart after the toggle is not enough on some versions.

**The add-on crash-loops with `s6-overlay-suexec: fatal: can only run as pid 1`.**
Something set `host_pid: true`. The base image runs s6-overlay as PID 1, which
that option breaks. Remove it.

**VS Code fails to connect, and retrying times out instantly.**
Usually the network path, not the add-on. Add keepalives on the client so a
dropped connection is detected instead of reused:

```
Host homeassistant
    ConnectTimeout 30
    ServerAliveInterval 15
    ServerAliveCountMax 6
    TCPKeepAlive yes
    Compression yes
```

and raise `remote.SSH.connectTimeout` to `60` in VS Code settings. If it is
already wedged, run **Remote-SSH: Kill VS Code Server on Host** and reconnect.

**`/data` is getting large.**
Check `du -sh /data/*`. The VS Code Server cache is the usual culprit; leave
`prune_old_vscode_servers` enabled, or lower `keep_vscode_servers` or
`prune_interval_hours`. `/data/claude-share` holds one Claude Code version
(about 300 MB), briefly two during an update.
