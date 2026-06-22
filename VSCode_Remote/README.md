# VS Code Remote SSH (Debian)

A glibc-based SSH server so VS Code desktop **Remote-SSH** can run its server
on Home Assistant OS. Uses a Debian (`bookworm`) base image instead of Alpine,
which avoids the musl / `gcompat` / `fcntl64` problem that breaks Remote-SSH on
the standard Alpine-based SSH add-ons with recent VS Code versions.

Listens on host port **22**.

> If you also run the *Advanced SSH & Web Terminal* add-on on port 22, change
> the host port of one of the two to avoid a conflict.

## Configuration

```yaml
authorized_keys:
  - "ssh-ed25519 AAAA... your-public-key"
```

| Option            | Description                                                    |
| ----------------- | -------------------------------------------------------------- |
| `authorized_keys` | List of SSH public keys allowed to connect (password login is disabled). |

## Usage

1. Generate an SSH key pair on your computer if you don't have one
   (`ssh-keygen -t ed25519`) and put the **public** key in the `authorized_keys`
   option above.
2. In VS Code install the **Remote - SSH** extension, then add an SSH host:

   ```
   Host homeassistant
       HostName <home-assistant-ip>
       User root
       Port 22
   ```

3. Connect with Remote-SSH. VS Code opens root's home (`/root`), where the add-on
   creates convenience symlinks to all mapped folders — so you immediately see
   `homeassistant`, `addons`, `ssl`, etc. in the Explorer. Open
   **`/homeassistant`** to edit the Home Assistant configuration
   (`configuration.yaml`, `automations.yaml`, etc.) with full VS Code features.
   Once opened, VS Code remembers it and reopens it on the next connection.

### Available folders

| Path             | Maps to                                   |
| ---------------- | ----------------------------------------- |
| `/homeassistant` | Home Assistant configuration (edit here)  |
| `/addons`        | Local add-ons                             |
| `/ssl`           | SSL certificates                          |
| `/share`         | Shared files                              |
| `/media`         | Media                                     |
| `/backup`        | Backups                                   |

### Notes

- Host keys are persisted under `/data/ssh` and the VS Code Server under
  `/data/vscode-server`, so both survive add-on restarts and updates.
- Password login is disabled — only the listed SSH keys can connect.
