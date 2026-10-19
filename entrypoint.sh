#!/bin/sh -e

PROXY_PORT="${PROXY_PORT:-21170}"
HTTP_PORT="${HTTP_PORT:-21180}"
SOURCE_URL="${SOURCE_URL:-https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt}"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-1h}"
THREADS="${THREADS:-10}"
MAX_DELAY="${MAX_DELAY:-600}"
CHECK_URL="${CHECK_URL:-https://www.notion.so/robots.txt}"
CHECK_INTERVAL="${CHECK_INTERVAL:-3}"
CHECK_THRESHOLD="${CHECK_THRESHOLD:-3}"
ROTATE="${ROTATE:-0}"
BLACKLIST_STRIKES="${BLACKLIST_STRIKES:-3}"
BLACKLIST_DURATION="${BLACKLIST_DURATION:-600}"

CACHEDIR="/cache"
WORKDIR="/app"
HAPROXY_DIR="$WORKDIR/haproxy"
DARKHTTPD_DIR="$WORKDIR/darkhttpd"
CONFIGS_FILE="$WORKDIR/configs.txt"
XRAY_KNIFE_BIN="/usr/local/bin/xray-knife"

DARKHTTPD_PORT=21188
PORT_A=21171
PORT_B=21172
PID_A=0
PID_B=0

REAL_IP=$(curl -s --connect-timeout 5 api.ipify.org 2>/dev/null || echo "127.0.0.1")
PROXY_PREFIX="socks5://${PROXY_AUTH:+${PROXY_AUTH}@}"
PROXY_URL="$PROXY_PREFIX$REAL_IP:$PROXY_PORT"
HTTP_URL="http://$REAL_IP:$HTTP_PORT/$HTTP_SLUG"

printf "\n xray-knife-auto\n"
printf " - Hostname: %s\n" "$(hostname)"
printf " - External IP: %s\n" "$REAL_IP"
printf " - Proxy URL: %s\n" "$PROXY_URL"
printf " - HTTP URL: %s\n\n" "$HTTP_URL"

shutdown() {
    EXIT_CODE=$?
    printf "Shutting down...\n"
    [ "$PID_A" -gt 0 ] && kill -TERM "$PID_A" 2>/dev/null || true
    [ "$PID_B" -gt 0 ] && kill -TERM "$PID_B" 2>/dev/null || true
    [ -f $HAPROXY_DIR/haproxy.pid ] && kill -TERM "$(cat $HAPROXY_DIR/haproxy.pid)" 2>/dev/null || true
    [ -f $DARKHTTPD_DIR/darkhttpd.pid ] && kill -TERM "$(cat $DARKHTTPD_DIR/darkhttpd.pid)" 2>/dev/null || true
    rm -f "$HAPROXY_DIR/haproxy.pid" "$DARKHTTPD_DIR/darkhttpd.pid"
    exit "$EXIT_CODE"
}

trap shutdown INT TERM EXIT

echo '# Initialization...' > "$CONFIGS_FILE"
chmod 644 "$CONFIGS_FILE"

mkdir -p "$DARKHTTPD_DIR"
chown -R darkhttpd:www-data "$DARKHTTPD_DIR"
cp "$CONFIGS_FILE" "$DARKHTTPD_DIR/index.txt"
darkhttpd "$DARKHTTPD_DIR/index.txt" --single-file --addr 127.0.0.1 --port "$DARKHTTPD_PORT" \
    --no-listing --hide-dotfiles --no-keepalive --no-server-id \
    --chroot --uid darkhttpd --gid www-data \
    --daemon --pidfile "/darkhttpd.pid"

mkdir -p "$HAPROXY_DIR"
chown -R haproxy:haproxy "$HAPROXY_DIR"

cat << EOF > "$HAPROXY_DIR/haproxy.cfg"
global
    stats socket $HAPROXY_DIR/haproxy.sock mode 600 level admin
    log stdout format raw local0
    chroot $HAPROXY_DIR
    user haproxy
    group haproxy
    maxconn 4096

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
    server $PORT_A 127.0.0.1:$PORT_A disabled
    server $PORT_B 127.0.0.1:$PORT_B disabled

frontend http
    bind *:$HTTP_PORT
    mode http

    acl is_slug path_beg /$HTTP_SLUG
    use_backend darkhttpd if is_slug

backend darkhttpd
    mode http
    server darkhttpd1 127.0.0.1:$DARKHTTPD_PORT check
EOF

haproxy_cmd() {
    echo "$1" | socat stdio $HAPROXY_DIR/haproxy.sock >/dev/null
}

haproxy -f "$HAPROXY_DIR/haproxy.cfg" -p "$HAPROXY_DIR/haproxy.pid" -D
printf "Listening: PROXY port %s, HTTP port %s \n" "$PROXY_PORT" "$HTTP_PORT"

COLD_START=1

while true; do
    if [ "$COLD_START" -eq 1 ] && [ -f "$CACHEDIR/configs.txt" ]; then
        cp "$CACHEDIR/configs.txt" "$CONFIGS_FILE"
        cp "$CONFIGS_FILE" "$DARKHTTPD_DIR/index.txt"
        printf "Cold start. Using configs from cache.\n"
        COLD_START=2
    else
        curl --connect-timeout 5 --max-time 15 --retry 5 --retry-all-errors --retry-delay 3 --retry-max-time 60 \
            -fsSL "$SOURCE_URL" -o "$WORKDIR/source.txt" || continue

         grep -v 'type=ws' "$WORKDIR/source.txt" > "$WORKDIR/filtered.txt" || true

        "$XRAY_KNIFE_BIN" http -f "$WORKDIR/filtered.txt" -o "$CONFIGS_FILE" \
            --threads "$THREADS" --mdelay "$MAX_DELAY" --url "$CHECK_URL" \
            --speedtest --sort || true

        sed -i '/^$/d' "$CONFIGS_FILE"
        sed -i "1i # $(date)\n" "$CONFIGS_FILE"
        echo >> "$CONFIGS_FILE"
        cp "$CONFIGS_FILE" "$CACHEDIR/configs.txt"
        cp "$CONFIGS_FILE" "$DARKHTTPD_DIR/index.txt"

        SOURCE_COUNT=$(grep -v '^[[:space:]]*#' "$WORKDIR/source.txt" | grep -c '.')
        CONFIGS_COUNT=$(grep -v '^[[:space:]]*#' "$CONFIGS_FILE" | grep -c '.')
        printf "Update configs: %s passed from %s total \n" "$CONFIGS_COUNT" "$SOURCE_COUNT"
    fi

    if [ "$PID_A" -eq 0 ]; then
        NEXT_PORT="$PORT_A"; PREV_PORT="$PORT_B"; PREV_PID="$PID_B"
    else
        NEXT_PORT="$PORT_B"; PREV_PORT="$PORT_A"; PREV_PID="$PID_A"
    fi

    "$XRAY_KNIFE_BIN" proxy inbound -f "$CONFIGS_FILE" \
        --port "$NEXT_PORT" --threads "$THREADS" --mdelay "$MAX_DELAY" \
        --rotate "$ROTATE" --blacklist-strikes "$BLACKLIST_STRIKES" --blacklist-duration "$BLACKLIST_DURATION" \
        --health-url "$CHECK_URL" --health-check "$CHECK_INTERVAL" --health-fail-threshold "$CHECK_THRESHOLD" \
        --inbound-config "${PROXY_PREFIX}127.0.0.1:$NEXT_PORT" --quiet &
    NEXT_PID=$!

    haproxy_cmd "set server pool/$NEXT_PORT state ready"

    if [ "$PREV_PID" -gt 0 ]; then
        haproxy_cmd "set server pool/$PREV_PORT state drain"
        sleep 30
        haproxy_cmd "set server pool/$PREV_PORT state maint"
        kill -TERM "$PREV_PID" 2>/dev/null || true
    fi

    if [ "$PID_A" -eq 0 ]; then
        PID_A="$NEXT_PID"; PID_B=0
    else
        PID_B="$NEXT_PID"; PID_A=0
    fi

    if [ "$COLD_START" -eq 2 ]; then
        COLD_START=0
    else
        sleep "$UPDATE_INTERVAL"
    fi
done
