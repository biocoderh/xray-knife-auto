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
| `CHECK_URL` | `https://www.instagram.com/robots.txt` | Proxy check URL to fetch |
| `UPDATE_INTERVAL` | `1h` | Update interval (sleep NUMBER\[SUFFIX\]) |
| `SOURCE_URL` | https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt | Source URL |
| `MAX_DELAY` | `600` | Maximum allowed delay (ms) |
| `THREADS` | `10` | Number of threads |

## Deployment unprivileged (Podman Quadlet)

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
Network=host
Volume=xray-knife-auto-cache:/cache:Z
Environment=PROXY_PORT=21170
Environment=PROXY_AUTH=
Environment=HTTP_PORT=21180
Environment=HTTP_SLUG=
Environment=CHECK_INTERVAL=1
Environment=CHECK_URL=https://www.instagram.com/robots.txt
Environment=UPDATE_INTERVAL=1h
Environment=SOURCE_URL=https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt
Environment=MAX_DELAY=600
Environment=THREADS=10

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
```

Reload and restart:
```bash
systemctl --user daemon-reload
podman pull ghcr.io/biocoderh/xray-knife-auto:latest
systemctl --user restart xray-knife-auto
journalctl --user -f -u xray-knife-auto.service -n 50
```

## Deployment root (systemd service)

Create `/etc/systemd/system/xray-knife-auto.service`:

```ini
[Unit]
Description=xray-knife-auto
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
Restart=on-failure

ExecStartPre=-/usr/bin/podman rm -f -i xray-knife-auto

ExecStart=/usr/bin/podman run \
    --name xray-knife-auto \
    --rm \
    --label io.containers.autoupdate=registry \
    --hostname %H \
    --tz local \
    --network host \
    -v xray-knife-auto-cache:/cache:Z \
    -e PROXY_PORT=21170 \
    -e PROXY_AUTH= \
    -e HTTP_PORT=21180 \
    -e HTTP_SLUG= \
    -e CHECK_INTERVAL=1 \
    -e CHECK_URL=https://www.instagram.com/robots.txt \
    -e UPDATE_INTERVAL=1h \
    -e SOURCE_URL=https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt \
    -e MAX_DELAY=600 \
    -e THREADS=10 \
    ghcr.io/biocoderh/xray-knife-auto:latest

ExecStop=/usr/bin/podman stop -t 10 xray-knife-auto

[Install]
WantedBy=multi-user.target
```

Reload and restart:
```bash
systemctl daemon-reload
podman pull ghcr.io/biocoderh/xray-knife-auto:latest
systemctl enable xray-knife-auto
systemctl restart xray-knife-auto
journalctl -f -u xray-knife-auto.service -n 50
```
