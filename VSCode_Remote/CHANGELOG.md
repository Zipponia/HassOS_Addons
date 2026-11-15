# Changelog

All notable changes to this add-on are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.9.0] - 2026-11-15

### Added

- **`SUPERVISOR_TOKEN` and the timezone now reach SSH sessions.** The add-on
  has had Supervisor and Home Assistant API access all along, but sshd starts
  sessions with a clean environment, so no shell, VS Code server or Claude Code
  session could see the token, and `date` printed UTC. They are passed with
  `SetEnv`, which also covers the non-interactive sessions VS Code uses;
  `sshd_config` is now readable by root only.
- **A working toolbox in the image**: `python3` with `pip`, `venv`,
  `websockets`, `aiohttp` and `yaml` (several Home Assistant operations exist
  only on the websocket API), the `ha` CLI, `sqlite3`, `ping`, `nc`, `dig`,
  `ip`, `yamllint`, `less`, `rsync`, `unzip`.
- **`extra_packages` option**: Debian packages installed in the background on
  every start, for a tool the image does not ship.
- **`update_interval_hours` option** (default 24): Claude Code is now checked
  for updates periodically, not only at start. The container had been up 16
  days with the CLI at 2.1.314 while the VS Code extension was at 2.1.325.
- **`~/.claude/CLAUDE.md` is installed on first start**, describing the
  environment to Claude Code: folder layout, API addresses, the `.storage`
  rule, the tools. Never overwritten; an existing file is left alone.
- **`/data/startup.log`** keeps the startup and maintenance messages, which
  scroll out of the add-on log within days.
- The deletion guard now also asks for: removal through `docker exec`, `ssh`,
  `sh -c` / `bash -c` / `eval`; removal behind `timeout`, `nohup`, `time`,
  `nice`, `ionice`; overwrites (`> file`, `cp /dev/null file`,
  `git reset --hard`, `git checkout .`, `git restore .`); POSTs to the
  Supervisor's uninstall, host reboot/shutdown and backup restore endpoints;
  `ha … restore` / `reboot` / `shutdown`; `docker compose down -v`; and
  `docker stop` / `kill` of the Home Assistant containers.

### Changed

- **Claude Code binaries live on `/data/claude-share`.** An update used to land
  on the container overlay, so every rebuild downloaded ~300 MB again. Older
  versions are deleted after a successful update.
- **Add-on backups no longer carry ~2.5 GB of re-downloadable data** (VS Code
  Server builds, the Remote-SSH CLI, extensions, logs, Claude Code binaries).
  After a restore on a fresh system, remote extensions must be reinstalled.
  DOCS now states that the backup contains credentials in plain text.
- **The add-on log is readable again.** The Supervisor watchdog's probe of
  port 22 wrote two sshd lines every two minutes — 4,326 of 4,327 lines. Those
  two lines are filtered out; logins and real failures are not.
- Only an ed25519 host key is used; the RSA key is removed. Clients that
  connected before already know the ed25519 key.
- Old `.cli.<commit>.log` files are pruned with their CLI builds, and orphaned
  `.claude.json.tmp.*` files older than a day are removed at start.
- DOCS: what each privilege is for.

### Fixed

- **`update_claude_code: false` and `prune_old_vscode_servers: false` were
  ignored.** The options were read with jq's `//`, which replaces an explicit
  `false` with the default, so neither switch could be turned off.
- **The update log could not tell success from failure** ("is up to date (or
  the update check failed)"). It now reports the exit code and the error.
- The deletion guard prompted on heredoc bodies and quoted text — a commit
  message with a line starting `rm`, or the word `--delete` in a string.

## [1.8.1] - 2026-09-24

### Added

- **Claude Code updates itself on every start** (`update_claude_code`, default
  on). The CLI is baked into the image with its auto-updater off, so it stayed
  at the version current on the last rebuild — it was found a month behind. The
  check runs in the background, so sshd never waits on the network.
- Old copies of the Remote-SSH CLI (`~/.vscode-server/code-<commit>`, ~32 MB
  each) are now pruned too, keeping the newest one and any still running. They
  were never removed and had piled up to five.

### Fixed

- **The deletion guard was easy to slip past.** It only matched at the very
  start of a line or right after `;` `&` `|`, so `  rm x`, `/bin/rm x`,
  `\rm x`, `command rm x`, `ls | xargs rm`, `find . -exec rm {} \;`,
  `(rm x)`, `$(rm x)` and `rm` inside `if`/`for` bodies all ran without asking.
  Every one of those now asks; harmless commands such as `grep rm file` still
  do not.
- `mv … /dev/null` was matched only with a leading space.
- `Agent` added to the allow rules next to `Task`, the tool's former name.
- `~/.local/bin` is now on `PATH`, silencing Claude Code's warning about it.

### Changed

- Dropped the unused `gnupg` package from the image.
- DOCS: pruning section described the pre-1.6.1 startup-only behaviour and
  left out `prune_interval_hours`.

## [1.8.0] - 2026-08-29

### Added

- **The add-on now manages Claude Code's permissions**, so the CLI runs
  unprompted while deletions still ask for confirmation. Previously both the
  rules and the guard hook only existed as hand-made files on `/data` — not
  versioned, not reproducible, and gone if `/data` were ever reset.
  - `deletion-guard.sh` ships in the image and is installed into
    `~/.claude/hooks/` on every start.
  - `~/.claude/settings.json` gets the `allow` rules (Bash, Read, Edit, Write,
    Glob, Grep, WebFetch, WebSearch, …) and the `ask` rules for deletions.
    Existing keys are **merged, not replaced**, so your own rules, model and
    other settings survive.

### Fixed

- **Claude Code prompted for every single command and file read.** The
  container runs as root, and Claude Code refuses to bypass permission checks
  for root (`--dangerously-skip-permissions cannot be used with root/sudo
  privileges` — `--allow-dangerously-skip-permissions` does not override it).
  So `permissions.defaultMode: "bypassPermissions"` was silently ignored and
  the session fell back to asking about everything. `dontAsk` is not a fix
  either: it defers to an automatic classifier that denies legitimate calls,
  such as POSTs to the Home Assistant API. Plain `allow`/`ask` rules are
  unaffected by the root guard, so the add-on installs those and strips a
  `defaultMode` of `bypassPermissions` or `dontAsk` when it finds one. Other
  modes (e.g. `acceptEdits`) are left alone.
- A `settings.json` that is not valid JSON is now left untouched with a warning
  instead of being overwritten — Claude Code silently ignores the whole file
  when it cannot parse it.

## [1.7.0] - 2026-08-20

### Added

- **Claude Code CLI is now part of the image.** It had been installed by hand
  inside the running container, i.e. on the ephemeral overlay — so the 1.6.1
  rebuild deleted it, while its credentials and history sat safely on `/data`.
  Installing it in the Dockerfile means every rebuild reinstalls it instead of
  wiping it. A `/usr/local/bin/claude` symlink puts it on `PATH` for
  non-interactive SSH sessions, which never source `~/.bashrc`.
- **Watchdog on the SSH port** (`watchdog: tcp://[HOST]:[PORT:22]`). The
  Supervisor previously only noticed a dead container, not a hung `sshd` — the
  failure mode that actually locks you out of a remote-access add-on.
- **Persistent shell and git state**: `~/.bash_history`, `~/.gitconfig` and
  `~/.ssh/known_hosts` now live on `/data` instead of being reset by rebuilds.

### Changed

- The image applies `apt-get dist-upgrade` at build time. The base image lagged
  months behind on security updates — `ca-certificates` was still the 2023
  release, old enough to reject recently issued certificates, alongside stale
  `curl`, `xz-utils` and `liblzma`.
- Persistence migrations copy with `-n` (no-clobber), so state already on
  `/data` always wins over a file the image ships at the same path. Without
  this, the build-time `~/.claude` stub the Claude installer creates would have
  been copied over the real credentials and the deletion-guard hook.

## [1.6.1] - 2026-07-22

### Fixed

- Pruning old VS Code Server builds only ran at startup, but this container
  stays up for weeks — three new ~590 MB builds accumulated over 13 days of
  uptime and `/data/vscode-server` climbed back to 2.9 GB. Pruning now also
  runs periodically (default every 12 h, option `prune_interval_hours`,
  `0` disables it).
- Pruning now skips any build with a running server process, so it can no
  longer remove the build an active VS Code session is using.

### Added

- Option `prune_interval_hours` (int, 0–168, default `12`).

## [1.6.0] - 2026-07-09

### Added

- `icon.png` and `logo.png` so the add-on renders properly in the HA store.
- `CHANGELOG.md` and `DOCS.md` (shown as the add-on's *Documentation* tab).
- Options `prune_old_vscode_servers` (default `true`) and `keep_vscode_servers`
  (default `2`): VS Code keeps every server build it downloads (~500 MB each),
  which had grown `/data/vscode-server` to 3 GB. Old builds are now pruned at
  startup, when no client is connected.
- A startup warning when `authorized_keys` is empty — password login is
  disabled, so an empty list means nobody can log in.

### Changed

- **`boot: auto`** (was `manual`). A remote-access add-on that does not come
  back after a Home Assistant reboot leaves you locked out until you start it
  from the local UI.
- `sshd`: `MaxStartups 30:50:100`, `LoginGraceTime 120` and `TCPKeepAlive yes`.
  Remote-SSH opens several connections at once and retries after network blips;
  the default `MaxStartups` (10) started refusing them on a flaky link.
- Dockerfile derives the Debian codename from `/etc/os-release` instead of
  hard-coding `bookworm`, so the Docker CLI repo keeps working if the base
  image moves to a newer Debian.

## [1.5.2] - 2026-07-08

### Fixed

- Persist `~/.claude.json` (MCP config, trust settings, project list), not just
  the `~/.claude` directory. It lived on the ephemeral overlay and was lost on
  every rebuild. Existing files are migrated to `/data` rather than deleted.

## [1.5.1] - 2026-07-03

### Fixed

- Removed `host_pid: true`, which shared the host PID namespace so the container
  init was no longer PID 1 and the s6-overlay base image crash-looped with
  `s6-overlay-suexec: fatal: can only run as pid 1`. `docker_api` already
  provides full host control, so `host_pid` was unnecessary.

## [1.5.0] - 2026-07-03

### Added

- Full-system access: `hassio_api`, `hassio_role: admin`, `homeassistant_api`,
  `docker_api`, `full_access`, `privileged` capabilities and
  `all_addon_configs:rw`. Requires **Protection mode off** in the add-on UI.
- Docker CLI (client only) in the image, so the mounted Docker socket can be
  used to inspect and exec into any container.

## [1.4.0] - 2026-07-03

### Added

- Persist the Claude Code home `~/.claude` (auth, chat history, memory) on
  `/data/claude-home` so it survives restarts and upgrades.

## [1.3.0] - 2026-06-22

### Added

- Convenience symlinks in `/root` to the mapped folders (`homeassistant`,
  `addons`, `ssl`, `share`, `media`, `backup`), so they appear in the VS Code
  Explorer right after connecting.

## [1.2.0] - 2026-06-22

### Changed

- SSH now listens on host port **22** (was 2222).
- Added `StreamLocalBindUnlink yes` for clean socket forwarding.

## [1.1.0] - 2026-06-22

### Added

- Persist the VS Code Server on `/data/vscode-server` so it is not re-downloaded
  on every restart.
- `tar`, `gzip`, `procps` and `git` in the image (server extraction, process
  detection, source control).
- SSH forwarding options required by Remote-SSH features.

### Changed

- Map the HA config with `homeassistant_config:rw` (mounted at
  `/homeassistant`); the old `config` mapping is deprecated.

## [1.0.0] - 2026-06-22

### Added

- Initial release: Debian (glibc) OpenSSH server so VS Code desktop Remote-SSH
  can run its server on Home Assistant OS, avoiding the Alpine/musl
  `gcompat`/`fcntl64` problem. Public-key authentication only; SSH host keys
  persisted on `/data/ssh`.

[1.9.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.9.0
[1.8.1]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.8.1
[1.8.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.8.0
[1.7.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.7.0
[1.6.1]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.6.1
[1.6.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.6.0
[1.5.2]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.5.2
[1.5.1]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.5.1
[1.5.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.5.0
[1.4.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.4.0
[1.3.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.3.0
[1.2.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.2.0
[1.1.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.1.0
[1.0.0]: https://github.com/Zipponia/HassOS_Addons/releases/tag/v1.0.0
