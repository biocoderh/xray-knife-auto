FROM alpine:latest

RUN apk add --no-cache curl bash ca-certificates tzdata unzip gcompat libc6-compat haproxy

WORKDIR /app

RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        ZIP_NAME="Xray-knife-linux-64.zip"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        ZIP_NAME="Xray-knife-linux-arm64-v8a.zip"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    curl -sSL "https://github.com/lilendian0x00/xray-knife/releases/latest/download/${ZIP_NAME}" -o /tmp/xray-knife.zip && \
    unzip -q /tmp/xray-knife.zip -d /tmp/xray-knife && \
    mv /tmp/xray-knife/xray-knife /app/xray-knife && \
    chmod +x /app/xray-knife && \
    rm -rf /tmp/xray-knife.zip /tmp/xray-knife

COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

EXPOSE 21170

ENTRYPOINT ["/app/entrypoint.sh"]
