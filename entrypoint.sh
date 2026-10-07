#!/bin/sh -e

HTTP_PORT="${HTTP_PORT:-21169}"
PROXY_PORT="${PROXY_PORT:-21170}"
THREADS="${THREADS:-50}"
MAX_DELAY="${MAX_DELAY:-600}"
CHECK_INTERVAL="${CHECK_INTERVAL:-1}"
CHECK_URL="${CHECK_URL:-https://www.linkedin.com/robots.txt}"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-1h}"
SOURCE_URL="${SOURCE_URL:-https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt}"

CONFIGS_TXT="/var/www/configs.txt"

PORT_A=21171
PORT_B=21172
PID_A=0
PID_B=0

shutdown() {
    printf "Shutting down...\n"
    [ "$PID_A" -gt 0 ] && kill -TERM "$PID_A" 2>/dev/null || true
    [ "$PID_B" -gt 0 ] && kill -TERM "$PID_B" 2>/dev/null || true
    [ -f /var/run/haproxy.pid ] && kill -TERM "$(cat /var/run/haproxy.pid)" 2>/dev/null || true
    [ -f /var/run/darkhttpd.pid ] && kill -TERM "$(cat /var/run/darkhttpd.pid)" 2>/dev/null || true
    exit 0
}

trap shutdown INT TERM EXIT

echo '# Initialization...' > "$CONFIGS_TXT"
darkhttpd "$CONFIGS_TXT" --single-file --port "$HTTP_PORT" --chroot --uid darkhttpd --pidfile /var/run/darkhttpd.pid --daemon
printf "Listening HTTP port %s \n" "$HTTP_PORT"

cat << EOF > /etc/haproxy/haproxy.cfg
global
    stats socket /var/lib/haproxy/admin.sock mode 600 level admin
    log /var/log/haproxy.log format raw local0
    chroot /var/lib/haproxy
    pidfile /var/run/haproxy.pid
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    timeout connect 5s
    timeout client  2h
    timeout server  2h

frontend proxy
    bind *:$PROXY_PORT
    default_backend pool

backend pool
    server a 127.0.0.1:$PORT_A disabled
    server b 127.0.0.1:$PORT_B disabled
EOF

haproxy_cmd() {
    echo "$1" | socat stdio /var/lib/haproxy/admin.sock >/dev/null
}

haproxy -f /etc/haproxy/haproxy.cfg -D
printf "Listening TCP port %s \n" "$PROXY_PORT"

while true; do
    curl -sSL "$SOURCE_URL" -o "/tmp/source.txt"
    ./xray-knife http -f "/tmp/source.txt" -o "$CONFIGS_TXT" \
        --threads "$THREADS" --mdelay "$MAX_DELAY" --url "$CHECK_URL" --speedtest --sort || true

    sed -i '/^$/d' "$CONFIGS_TXT"
    sed -i "1i # $(date)\n" "$CONFIGS_TXT"
    echo >> "$CONFIGS_TXT"

    SOURCE_COUNT=$(grep -v '^[[:space:]]*#' "/tmp/source.txt" | grep -c '.')
    CONFIGS_COUNT=$(grep -v '^[[:space:]]*#' "$CONFIGS_TXT" | grep -c '.')
    printf "Update configs: %s passed from %s total \n" "$CONFIGS_COUNT" "$SOURCE_COUNT"

    INBOUND_PART="socks://0.0.0.0:"
    [ -z "$PROXY_CREDENTIALS" ] || INBOUND_PART="socks://$PROXY_CREDENTIALS@0.0.0.0:"

    if [ "$PID_A" -eq 0 ]; then
        ./xray-knife proxy inbound -f "$CONFIGS_TXT" \
            --port "$PORT_A" --threads "$THREADS" --mdelay "$MAX_DELAY" \
            --rotate 0 --blacklist-strikes 3 \
            --health-check "$CHECK_INTERVAL" --health-url "$CHECK_URL" \
            --inbound-config "$INBOUND_PART$PORT_A#Listener" --quiet &
        PID_A=$!
        haproxy_cmd "set server pool/a state ready"
        if [ "$PID_B" -gt 0 ]; then
            haproxy_cmd "set server pool/b state drain"
            sleep 30
            haproxy_cmd "set server pool/b state maint"
            kill -TERM "$PID_B" 2>/dev/null || true
            PID_B=0
        fi
    else
        ./xray-knife proxy inbound -f "$CONFIGS_TXT" \
            --port "$PORT_B" --threads "$THREADS" --mdelay "$MAX_DELAY" \
            --rotate 0 --blacklist-strikes 3 \
            --health-check "$CHECK_INTERVAL" --health-url "$CHECK_URL" \
            --inbound-config "$INBOUND_PART$PORT_B#Listener" --quiet &
        PID_B=$!
        haproxy_cmd "set server pool/b state ready"
        if [ "$PID_A" -gt 0 ]; then
            haproxy_cmd "set server pool/a state drain"
            sleep 30
            haproxy_cmd "set server pool/a state maint"
            kill -TERM "$PID_A" 2>/dev/null || true
            PID_A=0
        fi
    fi

    sleep "$UPDATE_INTERVAL"
done
