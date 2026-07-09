# Zipponia Home Assistant Add-ons

<p align="center">
  <img src="https://img.shields.io/badge/Home%20Assistant-OS%2018%2B-41BDF5?logo=home-assistant&logoColor=white" alt="Home Assistant">
  <img src="https://img.shields.io/badge/arch-aarch64%20%7C%20amd64-lightgrey" alt="Architectures">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

Custom add-ons for **Home Assistant OS**.

## Installation

Add this repository to Home Assistant:

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FZipponia%2FHassOS_Addons)

Or manually: **Settings → Add-ons → Add-on Store → ⋮ → Repositories**, then paste

```
https://github.com/Zipponia/HassOS_Addons
```

The add-ons below then appear in the store.

## Add-ons

### [VS Code Remote SSH (Debian)](VSCode_Remote)

<img src="VSCode_Remote/icon.png" alt="" width="72" align="left" hspace="12">

A glibc-based SSH server so the VS Code desktop app can attach with **Remote-SSH**
and edit your Home Assistant configuration with the full editor. Uses a Debian
base image, avoiding the musl/`gcompat`/`fcntl64` problem that breaks Remote-SSH
on the Alpine-based SSH add-ons.

Persists the VS Code Server, SSH host keys and the Claude Code home across
restarts and rebuilds. Optionally grants full-system and Docker access.

<br clear="left">

📖 [Documentation](VSCode_Remote/DOCS.md) · 📝 [Changelog](VSCode_Remote/CHANGELOG.md)

## Repository layout

```
.
├── repository.yaml        # add-on repository metadata
├── LICENSE
└── VSCode_Remote/         # one folder per add-on
    ├── config.yaml
    ├── build.yaml
    ├── Dockerfile
    ├── run.sh
    ├── icon.png
    ├── logo.png
    ├── DOCS.md
    └── CHANGELOG.md
```

These are **local-build** add-ons: they have no `image:` field, so Home Assistant
builds them on your machine. An update appears only when the `version` field in
`config.yaml` is bumped; refresh with **Add-on Store → ⋮ → Check for updates**.

## License

MIT — see [LICENSE](LICENSE).
