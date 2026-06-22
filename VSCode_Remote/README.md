# VS Code Remote SSH (Debian)

A glibc-based SSH server so VS Code desktop **Remote-SSH** can run its server
on Home Assistant OS. Uses a Debian (`bookworm`) base image instead of Alpine,
which avoids the musl / `gcompat` / `fcntl64` problem that breaks Remote-SSH on
the standard Alpine-based SSH add-ons with recent VS Code versions.

Listens on host port **2222** so it can run alongside the existing
Advanced SSH & Web Terminal add-on (port 22).

## Configuration

```yaml
authorized_keys:
  - "ssh-ed25519 AAAA... your-public-key"
```

| Option            | Description                                                    |
| ----------------- | -------------------------------------------------------------- |
| `authorized_keys` | List of SSH public keys allowed to connect (password login is disabled). |

## Usage

Connect from your machine with VS Code Remote-SSH (user `root`, host port `2222`):

```
ssh -p 2222 root@<home-assistant-ip>
```

Host keys are persisted under `/data/ssh` so they survive add-on restarts.
