#!/bin/sh -e

CONFIGS_PORT="${CONFIGS_PORT:-21169}"
PROXY_PORT="${PROXY_PORT:-21170}"
THREADS="${THREADS:-50}"
MAX_DELAY="${MAX_DELAY:-300}"
INTERVAL="${INTERVAL:-1h}"
SOURCE_URL="${SOURCE_URL:-https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt}"

WORK_DIR="/tmp/xray-knife-auto"
HAPROXY_SOCK="$WORK_DIR/haproxy.sock"
HAPROXY_CFG="$WORK_DIR/haproxy.cfg"
HAPROXY_PID="$WORK_DIR/haproxy.pid"
CONFIGS_TXT="$WORK_DIR/configs.txt"

PORT_A=21171
PORT_B=21172
PID_A=0
PID_B=0

shutdown() {
    printf "\nShutting down..."

    [ "$PID_A" -gt 0 ] && kill -TERM "$PID_A" 2>/dev/null || true
    [ "$PID_B" -gt 0 ] && kill -TERM "$PID_B" 2>/dev/null || true

    [ -f "$HAPROXY_PID" ] && kill -TERM "$(cat "$HAPROXY_PID")" 2>/dev/null || true

    rm -rf "$WORK_DIR"
    exit 0
}

trap shutdown INT TERM EXIT

mkdir -p "$WORK_DIR"

echo '# Starting...' > "$CONFIGS_TXT"

cat << EOF > "$HAPROXY_CFG"
global
    stats socket $HAPROXY_SOCK mode 600 level admin
    log stdout format raw local0
    chroot /var/empty
    user haproxy
    group haproxy

defaults
    log     global
    mode    tcp
    timeout connect 5s
    timeout client  2h
    timeout server  2h

frontend configs
    bind *:$CONFIGS_PORT
    mode http
    http-request return status 200 content-type "text/plain" file "$CONFIGS_TXT"

frontend proxy
    bind *:$PROXY_PORT
    default_backend pool

backend pool
    server a 127.0.0.1:$PORT_A disabled
    server b 127.0.0.1:$PORT_B disabled
EOF

haproxy -f "$HAPROXY_CFG" -p "$HAPROXY_PID" -D
printf "\nListening ports HTTP %s and TCP %s" "$CONFIGS_PORT" "$PROXY_PORT"

while true; do
    curl -sSL "$SOURCE_URL" -o "$WORK_DIR/source.txt"
    ./xray-knife http -f "$WORK_DIR/source.txt" -o "$CONFIGS_TXT" --threads "$THREADS" --mdelay "$MAX_DELAY" --speedtest --sort > "$WORK_DIR/xray-knife-http.log" 2>&1 || true
    sed -i "1i # $(date '+%Y-%m-%d %H:%M:%S')" "$CONFIGS_TXT"

    if [ "$PID_A" -eq 0 ]; then
        ./xray-knife proxy inbound -f "$CONFIGS_TXT" --port "$PORT_A" --threads "$THREADS" --mdelay "$MAX_DELAY" --rotate 0 --health-check 1 --blacklist-strikes 3 > "$WORK_DIR/xray-knife-proxy-A.log" 2>&1 &
        PID_A=$!
        echo "set server pool/a state ready" | socat stdio "$HAPROXY_SOCK" >/dev/null
        if [ "$PID_B" -gt 0 ]; then
            echo "set server pool/b state drain" | socat stdio "$HAPROXY_SOCK" >/dev/null
            sleep 30
            echo "set server pool/b state maint" | socat stdio "$HAPROXY_SOCK" >/dev/null
            kill -TERM "$PID_B" 2>/dev/null || true
            PID_B=0
        fi
    else
        ./xray-knife proxy inbound -f "$CONFIGS_TXT" --port "$PORT_B" --threads "$THREADS" --mdelay "$MAX_DELAY" --rotate 0 --health-check 1 --blacklist-strikes 3 > "$WORK_DIR/xray-knife-proxy-B.log" 2>&1 &
        PID_B=$!
        echo "set server pool/b state ready" | socat stdio "$HAPROXY_SOCK" >/dev/null
        if [ "$PID_A" -gt 0 ]; then
            echo "set server pool/a state drain" | socat stdio "$HAPROXY_SOCK" >/dev/null
            sleep 30
            echo "set server pool/a state maint" | socat stdio "$HAPROXY_SOCK" >/dev/null
            kill -TERM "$PID_A" 2>/dev/null || true
            PID_A=0
        fi
    fi
    sleep "$INTERVAL"
done
