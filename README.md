# xray-knife-auto

[![ShellCheck](https://github.com/biocoderh/xray-knife-auto/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/biocoderh/xray-knife-auto/actions/workflows/shellcheck.yml)

[xray-knife](https://github.com/lilendian0x00/xray-knife) workflow automation loop:
 - Test configs and share via http
 - Rotate proxy inbounds behind HAProxy

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `HTTP_PORT` | `21169` | Port for the HTTP server, return plain/text configs |
| `PROXY_PORT` | `21170` | Port for the proxy server |
| `PROXY_CREDENTIALS` | `` | Proxy inbound user:pass base64 encoded, empty no auth |
| `THREADS` | `50` | Number of threads |
| `MAX_DELAY` | `600` | Maximum allowed delay (ms) |
| `UPDATE_INTERVAL` | `1h` | Update interval (sleep NUMBER\[SUFFIX\]) |
| `SOURCE_URL` | https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt | Source URL |

## Deployment (Podman Quadlet)

Create `~/.config/containers/systemd/xray-knife-auto.container`:

```ini
[Unit]
Description=xray-knife-auto
After=network-online.target

[Container]
Image=ghcr.io/biocoderh/xray-knife-auto:latest
ContainerName=xray-knife-auto
AutoUpdate=registry
HostName=%H
Timezone=local
PublishPort=21169:21169
PublishPort=21170:21170
Volume=xray-knife-auto:/var/www:Z
Environment=HTTP_PORT=21169
Environment=PROXY_PORT=21170
Environment=THREADS=50
Environment=MAX_DELAY=600
Environment=UPDATE_INTERVAL=1h
Environment=SOURCE_URL=https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt

[Service]
Restart=on-failure
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

Reload and restart:
```bash
systemctl --user daemon-reload
podman pull ghcr.io/biocoderh/xray-knife-auto:latest
systemctl --user restart xray-knife-auto
```
