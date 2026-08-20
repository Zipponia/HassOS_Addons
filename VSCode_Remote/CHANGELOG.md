# Changelog

All notable changes to this add-on are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

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
