# Zipponia Home Assistant Add-ons

Custom Home Assistant OS add-ons.

## Add-ons

### VS Code Remote SSH (Debian)

A glibc-based SSH server so VS Code desktop **Remote-SSH** can run its server
on Home Assistant OS. Uses a Debian base image instead of Alpine, which avoids
the musl/`gcompat`/`fcntl64` problem that breaks Remote-SSH on the standard
Alpine-based SSH add-ons with recent VS Code versions.

Listens on host port **2222** so it can run alongside the existing
Advanced SSH & Web Terminal add-on (port 22).

## Installation

In Home Assistant: **Settings → Add-ons → Add-on Store → ⋮ → Repositories**,
then add:

```
https://github.com/Zipponia/HassOS_Addons
```

The add-on then appears in the store.
