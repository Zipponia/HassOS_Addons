# Where you are

This is a shell inside the **VS Code Remote SSH (Debian)** add-on, running on a
**Home Assistant OS host**. You are root in a Debian container with broad
access to the whole system. This file was installed once by the add-on; edit
it freely, it is never overwritten.

## Layout

- `/homeassistant` is the **live** Home Assistant configuration.
- `/addons`, `/addon_configs`, `/share`, `/media`, `/ssl`, `/backup` are the
  Supervisor-mapped folders.
- Only `/data` and the mapped folders persist. Everything else is the container
  overlay and is lost on rebuild: anything installed by hand (apt, pip, a
  downloaded binary) disappears. Lasting tools go in the add-on's Dockerfile or
  its `extra_packages` option.
- `/data/startup.log` has the add-on's startup and maintenance messages.

## Talking to Home Assistant

`$SUPERVISOR_TOKEN` is set in every SSH session. Use it instead of a
hand-made long-lived token or the LAN address.

- Supervisor API: `http://supervisor/…`, for example
  `curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons/self/info`
- Home Assistant REST API: `http://supervisor/core/api/…`
- Home Assistant websocket: `ws://supervisor/core/websocket`, same token
- The `ha` CLI is installed and uses the same token (`ha core info`,
  `ha addons logs <slug>`).

## Rules

- **Never edit `/homeassistant/.storage/*.json` while Home Assistant runs.** It
  rewrites those files from memory and the edit is lost or corrupts state. Use
  the websocket or REST API instead: Lovelace dashboards, the entity and device
  registries and similar exist only on the websocket API.
- After a YAML change, validate before reloading or restarting:
  `curl -s -X POST -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/core/api/config/core/check_config`
- Commands that delete or destroy ask for confirmation (a hook in
  `~/.claude/hooks/deletion-guard.sh`). It is a net for accidents, not a
  complete one: think before destructive actions it cannot see, such as a
  script that deletes.

## Tools

- The Docker socket is mounted: `docker ps`, `docker logs`, `docker exec` reach
  every container, including `homeassistant` and the other add-ons.
- `python3` with `websockets`, `aiohttp` and `yaml`. For other packages make a
  venv under `/data` (`python3 -m venv`); system-wide `pip install` is refused.
- `sqlite3`, `jq`, `git`, `yamllint`, `rsync`, `ping`, `nc`, `dig`, `ip`.
- Times are in the Home Assistant timezone (`$TZ`).
