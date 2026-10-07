#!/bin/sh -e

PROXY_PORT="${PROXY_PORT:-21170}"
HTTP_PORT="${HTTP_PORT:-21180}"
CHECK_INTERVAL="${CHECK_INTERVAL:-1}"
CHECK_URL="${CHECK_URL:-https://www.linkedin.com/robots.txt}"
UPDATE_INTERVAL="${UPDATE_INTERVAL:-1h}"
SOURCE_URL="${SOURCE_URL:-https://raw.githubusercontent.com/whoahaow/rjsxrd/refs/heads/main/githubmirror/bypass/bypass-all.txt}"
THREADS="${THREADS:-50}"
MAX_DELAY="${MAX_DELAY:-1000}"

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

shutdown() {
    printf "Shutting down...\n"
    [ "$PID_A" -gt 0 ] && kill -TERM "$PID_A" 2>/dev/null || true
    [ "$PID_B" -gt 0 ] && kill -TERM "$PID_B" 2>/dev/null || true
    [ -f $HAPROXY_DIR/haproxy.pid ] && kill -TERM "$(cat $HAPROXY_DIR/haproxy.pid)" 2>/dev/null || true
    [ -f $DARKHTTPD_DIR/darkhttpd.pid ] && kill -TERM "$(cat $DARKHTTPD_DIR/darkhttpd.pid)" 2>/dev/null || true
    rm -f "$HAPROXY_DIR/haproxy.pid" "$DARKHTTPD_DIR/darkhttpd.pid"
    exit 0
}

trap shutdown INT TERM EXIT

mkdir -p "$DARKHTTPD_DIR"
chown -R darkhttpd:darkhttpd "$DARKHTTPD_DIR"
echo '# Initialization...' > "$CONFIGS_FILE"
darkhttpd "$DARKHTTPD_DIR" --single-file "$CONFIGS_FILE" --addr 127.0.0.1 --port "$DARKHTTPD_PORT" \
    --no-listing --hide-dotfiles --no-keepalive --no-server-id \
    --chroot --uid darkhttpd --gid darkhttpd \
    --daemon --pidfile "$DARKHTTPD_DIR/darkhttpd.pid"

mkdir -p "$HAPROXY_DIR"
chown -R haproxy:haproxy "$HAPROXY_DIR"

cat << EOF > "$HAPROXY_DIR/haproxy.cfg"
global
    stats socket $HAPROXY_DIR/haproxy.sock mode 600 level admin
    log $HAPROXY_DIR/haproxy.log format raw local0
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

INBOUND_PREFIX="socks://${PROXY_AUTH:+${PROXY_AUTH}@}127.0.0.1:"

while true; do
    curl -sSL "$SOURCE_URL" -o "$WORKDIR/source.txt"
    "$XRAY_KNIFE_BIN" http -f "$WORKDIR/source.txt" -o "$CONFIGS_FILE" \
        --threads "$THREADS" --mdelay "$MAX_DELAY" --url "$CHECK_URL" --speedtest --sort || true

    sed -i '/^$/d' "$CONFIGS_FILE"
    sed -i "1i # $(date)\n" "$CONFIGS_FILE"
    echo >> "$CONFIGS_FILE"

    SOURCE_COUNT=$(grep -v '^[[:space:]]*#' "$WORKDIR/source.txt" | grep -c '.')
    CONFIGS_COUNT=$(grep -v '^[[:space:]]*#' "$CONFIGS_FILE" | grep -c '.')
    printf "Update configs: %s passed from %s total \n" "$CONFIGS_COUNT" "$SOURCE_COUNT"

    if [ "$PID_A" -eq 0 ]; then
        NEXT_PORT="$PORT_A"; PREV_PORT="$PORT_B"; PREV_PID="$PID_B"
    else
        NEXT_PORT="$PORT_B"; PREV_PORT="$PORT_A"; PREV_PID="$PID_A"
    fi

    "$XRAY_KNIFE_BIN" proxy inbound -f "$CONFIGS_FILE" \
        --port "$NEXT_PORT" --threads "$THREADS" --mdelay "$MAX_DELAY" \
        --rotate 0 --blacklist-strikes 3 \
        --health-check "$CHECK_INTERVAL" --health-url "$CHECK_URL" \
        --inbound-config "$INBOUND_PREFIX$NEXT_PORT#Listener" --quiet &
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

    sleep "$UPDATE_INTERVAL"
done
