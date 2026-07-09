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
```

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `authorized_keys` | list of strings | `[]` | SSH **public** keys allowed to connect. Password login is disabled, so at least one key is required. |
| `prune_old_vscode_servers` | bool | `true` | Delete old VS Code Server builds at startup. VS Code keeps every build it downloads (~500 MB each), which otherwise fills `/data`. |
| `keep_vscode_servers` | int (1–10) | `2` | How many of the most recent server builds to keep when pruning. |

Pruning runs at add-on start, before `sshd` accepts connections, so it never
removes a build that is in use. If VS Code needs a pruned build again, it simply
re-downloads it.

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

## What persists

The container filesystem is ephemeral: everything outside `/data` is lost on
restart or rebuild. These are symlinked onto `/data`, so they survive:

| Path in container | Stored at |
| ----------------- | --------- |
| `~/.vscode-server` | `/data/vscode-server` |
| `~/.claude` | `/data/claude-home` |
| `~/.claude.json` | `/data/claude-home/.claude.json` |
| SSH host keys | `/data/ssh` |

Persisting the host keys means your SSH client never warns about a changed host
key after an add-on restart.

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

## Troubleshooting

**The add-on starts but I cannot log in.**
Check the log for `No authorized_keys configured`. Password authentication is
disabled by design; add your public key to the options and restart.

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
`prune_old_vscode_servers` enabled, or lower `keep_vscode_servers`.
