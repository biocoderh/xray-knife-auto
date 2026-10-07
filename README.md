# xray-knife-auto

[![ShellCheck](https://github.com/biocoderh/xray-knife-auto/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/biocoderh/xray-knife-auto/actions/workflows/shellcheck.yml)

[xray-knife](https://github.com/lilendian0x00/xray-knife) workflow automation loop:
 - Test configs and share via http
 - Rotate proxy inbounds behind HAProxy

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PROXY_PORT` | `21170` | Port for the proxy server |
| `PROXY_AUTH` |  | Proxy inbound user:pass base64 encoded, empty no auth |
| `HTTP_PORT` | `21180` | Port for the HTTP server, return plain/text configs |
| `HTTP_SLUG` |  | Serve configs file behind HTTP path for security |
| `CHECK_INTERVAL` | `1` | Proxy check interval in seconds |
| `CHECK_URL` | `https://www.linkedin.com/robots.txt` | Proxy check URL to fetch |
| `UPDATE_INTERVAL` | `1h` | Update interval (sleep NUMBER\[SUFFIX\]) |
| `SOURCE_URL` | https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt | Source URL |
| `MAX_DELAY` | `1000` | Maximum allowed delay (ms) |
| `THREADS` | `50` | Number of threads |

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
PublishPort=21170:21170
PublishPort=21180:21180
Environment=PROXY_PORT=21170
Environment=PROXY_AUTH=
Environment=HTTP_PORT=21180
Environment=HTTP_SLUG=
Environment=CHECK_INTERVAL=1
Environment=CHECK_URL=https://www.linkedin.com/robots.txt
Environment=UPDATE_INTERVAL=1h
Environment=SOURCE_URL=https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt
Environment=MAX_DELAY=1000
Environment=THREADS=50

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
